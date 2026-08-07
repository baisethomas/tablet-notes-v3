import Foundation
import Observation
import Supabase

/// Watches server-side `processing_jobs` and reports terminal outcomes (TAB-72).
///
/// This replaces client-driven polling. The old path made ~200 authenticated
/// round trips per 90-minute sermon and — worse — only ran while the app was
/// foregrounded, so locking the phone after church orphaned the job forever.
/// Here the server owns the lifecycle; the device subscribes to its own rows
/// (RLS-scoped) and reacts when work finishes, whether that took thirty seconds
/// or happened while the app was dead.
///
/// It deliberately does NOT drive the work: nothing here retries, resubmits, or
/// supervises. The reaper does that server-side.
@MainActor
@Observable
final class ProcessingObserver {
    /// Emitted when a job reaches a terminal state, so callers can pull the
    /// result into SwiftData and mark it for sync.
    struct Completion: Equatable {
        let sermonLocalId: UUID
        let kind: RemoteProcessingJob.Kind
        let status: RemoteProcessingJob.Status
        let lastError: String?
    }

    private(set) var isObserving = false
    private(set) var lastError: String?

    private var channel: RealtimeChannelV2?
    private var streamTask: Task<Void, Never>?
    private let client: SupabaseClient
    private var onCompletion: ((Completion) -> Void)?

    init(client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
    }

    deinit {
        streamTask?.cancel()
    }

    /// Starts observing this user's jobs. Safe to call repeatedly — a second
    /// call for the same user is a no-op, and for a different user it rebinds.
    func start(userId: UUID, onCompletion: @escaping (Completion) -> Void) async {
        guard !isObserving else { return }
        self.onCompletion = onCompletion

        // Realtime needs the current access token or RLS will reject the
        // subscription; the app refreshes tokens ad hoc elsewhere, so set it
        // explicitly here at subscribe time.
        if let token = try? await client.auth.session.accessToken {
            await client.realtime.setAuth(token)
        }

        let channel = client.channel("processing_jobs:\(userId.uuidString)")
        self.channel = channel

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "processing_jobs",
            filter: "user_id=eq.\(userId.uuidString)"
        )

        streamTask = Task { [weak self] in
            for await change in changes {
                guard !Task.isCancelled else { return }
                await self?.handle(change)
            }
        }

        await channel.subscribe()
        isObserving = true
        print("[ProcessingObserver] Subscribed to processing_jobs for user \(userId)")
    }

    func stop() async {
        streamTask?.cancel()
        streamTask = nil
        if let channel {
            await client.removeChannel(channel)
        }
        channel = nil
        isObserving = false
    }

    private func handle(_ change: AnyAction) async {
        // Only inserts/updates carry a current record worth reacting to.
        let record: [String: AnyJSON]?
        switch change {
        case .insert(let action): record = action.record
        case .update(let action): record = action.record
        default: record = nil
        }
        guard let record else { return }

        guard let job = Self.decodeJob(from: record) else {
            print("[ProcessingObserver] Ignoring undecodable job row")
            return
        }
        guard job.status.isTerminal else { return }

        print("[ProcessingObserver] Job \(job.kind.rawValue) reached \(job.status.rawValue) for sermon \(job.sermonLocalId)")
        onCompletion?(
            Completion(
                sermonLocalId: job.sermonLocalId,
                kind: job.kind,
                status: job.status,
                lastError: job.lastError
            )
        )
    }

    /// Decodes a Realtime record payload into a job. Exposed for tests: the
    /// payload shape (snake_case, JSON-typed values) is the fragile seam here,
    /// not the socket.
    static func decodeJob(from record: [String: AnyJSON]) -> RemoteProcessingJob? {
        guard
            let id = record["id"]?.stringValue,
            let localIdString = record["sermon_local_id"]?.stringValue,
            let sermonLocalId = UUID(uuidString: localIdString),
            let kindString = record["kind"]?.stringValue,
            let kind = RemoteProcessingJob.Kind(rawValue: kindString),
            let statusString = record["status"]?.stringValue,
            let status = RemoteProcessingJob.Status(rawValue: statusString)
        else {
            return nil
        }

        return RemoteProcessingJob(
            id: id,
            sermonLocalId: sermonLocalId,
            kind: kind,
            status: status,
            lastError: record["last_error"]?.stringValue
        )
    }
}
