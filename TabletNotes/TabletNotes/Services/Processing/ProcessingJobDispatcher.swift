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

    /// True when an automatic sweep should not ask again: the server already
    /// said the job is live (queued/submitted/running) or exhausted. The jobs
    /// endpoint is capped at 20 requests per user per hour, so re-asking a
    /// healthy job every sweep starves new recordings.
    func shouldSkipAutomaticDispatch(sermonLocalId: UUID) -> Bool
}

extension ProcessingJobDispatching {
    func shouldSkipAutomaticDispatch(sermonLocalId: UUID) -> Bool { false }
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

    /// Sermons the server reported exhausted. Never re-asked automatically for
    /// the life of the process; only a deliberate retry clears the entry.
    private var exhausted: Set<UUID> = []
    /// Sermons whose job the server confirmed live, with when we heard. Expires
    /// so a job row that later vanishes is repaired by a future sweep.
    private var confirmedLive: [UUID: Date] = [:]
    private let liveConfirmationTTL: TimeInterval
    private let now: () -> Date

    private(set) var lastError: String?

    init(
        client: any ProcessingJobRequesting = ProcessingJobClient(),
        liveConfirmationTTL: TimeInterval = 15 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.liveConfirmationTTL = liveConfirmationTTL
        self.now = now
    }

    func shouldSkipAutomaticDispatch(sermonLocalId: UUID) -> Bool {
        if exhausted.contains(sermonLocalId) { return true }
        if let confirmedAt = confirmedLive[sermonLocalId] {
            if now().timeIntervalSince(confirmedAt) < liveConfirmationTTL { return true }
            confirmedLive[sermonLocalId] = nil
        }
        return false
    }

    @discardableResult
    func dispatch(sermonLocalId: UUID, retry: Bool = false) async -> Bool {
        guard !inFlight.contains(sermonLocalId) else { return false }
        inFlight.insert(sermonLocalId)
        defer { inFlight.remove(sermonLocalId) }

        // A deliberate retry overrides whatever we remembered.
        if retry {
            exhausted.remove(sermonLocalId)
            confirmedLive[sermonLocalId] = nil
        }

        do {
            let job = try await client.requestTranscription(
                sermonLocalId: sermonLocalId,
                filePath: nil,
                retry: retry
            )
            lastError = nil
            if job.exhausted || job.status == .dead {
                exhausted.insert(sermonLocalId)
                confirmedLive[sermonLocalId] = nil
            } else if !job.status.isTerminal {
                confirmedLive[sermonLocalId] = now()
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
