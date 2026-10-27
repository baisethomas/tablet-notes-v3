import Foundation

@MainActor
protocol ProcessingJobDispatching: AnyObject {
    /// Asks the server to own transcription for this sermon. Idempotent on the
    /// server, so calling it again after a lost response is safe and free.
    ///
    /// Pass `retry: true` only for a deliberate user action after the pipeline
    /// stopped — automatic sweeps must leave it false (TAB-91).
    @discardableResult
    func dispatch(sermonLocalId: UUID, retry: Bool) async -> Bool

    /// Whether the server has already answered `exhausted: true` for this
    /// sermon. The sweep skips these so a dead job is not re-asked every pass
    /// (it drained the 20/hr jobs limit once).
    func isExhausted(sermonLocalId: UUID) -> Bool
}

extension ProcessingJobDispatching {
    func isExhausted(sermonLocalId: UUID) -> Bool { false }
}

/// Client-side entry point to the durable pipeline (TAB-72).
///
/// Deliberately thin. It does not track progress, retry on a timer, or hold a
/// queue — the server's `processing_jobs` row is the queue, and the reaper is
/// the retry. Everything this type can do wrong is bounded to "the request
/// didn't get through", which the next sweep repairs.
@MainActor
final class ProcessingJobDispatcher: ProcessingJobDispatching {
    static let shared = ProcessingJobDispatcher()

    private let client: any ProcessingJobRequesting
    /// Guards against two triggers (a save and a foreground sweep) racing for the
    /// same sermon. Not a correctness requirement — the server is idempotent —
    /// but it keeps one recording from burning three token refreshes.
    private var inFlight: Set<UUID> = []

    private(set) var lastError: String?
    /// Sermons the server reported exhausted, for this process lifetime. A
    /// deliberate retry that succeeds clears the entry; a relaunch re-asks once.
    private var exhausted: Set<UUID> = []

    func isExhausted(sermonLocalId: UUID) -> Bool {
        exhausted.contains(sermonLocalId)
    }

    init(client: any ProcessingJobRequesting = ProcessingJobClient()) {
        self.client = client
    }

    @discardableResult
    func dispatch(sermonLocalId: UUID, retry: Bool = false) async -> Bool {
        guard !inFlight.contains(sermonLocalId) else { return false }
        inFlight.insert(sermonLocalId)
        defer { inFlight.remove(sermonLocalId) }

        do {
            let job = try await client.requestTranscription(
                sermonLocalId: sermonLocalId,
                filePath: nil,
                retry: retry
            )
            lastError = nil
            if job.exhausted {
                exhausted.insert(sermonLocalId)
            } else {
                exhausted.remove(sermonLocalId)
            }
            print("[ProcessingJobDispatcher] Job \(job.id) is \(job.status.rawValue) for sermon \(sermonLocalId)")
            return true
        } catch {
            // Failing here is recoverable by design: the sermon stays pending
            // locally and the next sweep re-dispatches. What must NOT happen is
            // marking anything complete — that is the optimistic ack this
            // codebase has been bitten by before.
            lastError = error.localizedDescription
            print("[ProcessingJobDispatcher] Dispatch failed for \(sermonLocalId): \(error.localizedDescription)")
            return false
        }
    }
}
