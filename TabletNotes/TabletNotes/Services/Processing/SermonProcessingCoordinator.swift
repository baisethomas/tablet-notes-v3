import Foundation
import SwiftData

enum SermonProcessingError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "The app isn't ready to save recordings yet. Please try again."
        }
    }
}

@MainActor
final class SermonProcessingCoordinator {
    static let shared = SermonProcessingCoordinator()

    private var modelContext: ModelContext?
    private weak var sermonService: SermonService?
    private weak var syncService: (any SyncServiceProtocol)?
    private var hasBootstrappedBackgroundProcessing = false

    var backgroundBootstrapper: (@MainActor () -> Void)?
    var backgroundRefresher: (@MainActor () -> Void)?
    var syncRunner: (@MainActor () async -> Void)?

    // MARK: - Durable processing pipeline (TAB-72), flag-gated

    /// Injected so tests can exercise both sides of the branch without touching
    /// UserDefaults, and so the flag has exactly one read point in production.
    var isDurableProcessingEnabled: @MainActor () -> Bool = {
        FeatureFlags.shared.durableProcessingPipeline
    }

    var processingDispatcher: (any ProcessingJobDispatching)?
    var processingObserver: ProcessingObserver?

    private init() {}

    func configure(
        modelContext: ModelContext,
        sermonService: SermonService,
        syncService: SyncServiceProtocol? = nil
    ) {
        self.modelContext = modelContext
        self.sermonService = sermonService
        if let syncService {
            self.syncService = syncService
        }
        TranscriptionRetryService.shared.setModelContext(modelContext)
        SummaryRetryService.shared.setModelContext(modelContext)
    }

    func updateNetworkAvailability(_ isAvailable: Bool) {
        TranscriptionRetryService.shared.overrideNetworkAvailability(isAvailable)
        SummaryRetryService.shared.overrideNetworkAvailability(isAvailable)
    }

    func bootstrapBackgroundProcessingIfNeeded() {
        guard !hasBootstrappedBackgroundProcessing else { return }
        runBackgroundBootstrap()
        hasBootstrappedBackgroundProcessing = true
    }

    func refreshBackgroundProcessing() {
        if let backgroundRefresher {
            backgroundRefresher()
            return
        }

        runDefaultBackgroundRefresh()
    }

    func handleAppLaunch(syncDelayNanoseconds: UInt64 = 500_000_000) async {
        bootstrapBackgroundProcessingIfNeeded()
        startRecoveredInterruptedProcessingIfNeeded()

        if syncDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: syncDelayNanoseconds)
        }

        await triggerSync()
    }

    func handleAppDidBecomeActive() async {
        bootstrapBackgroundProcessingIfNeeded()
        refreshBackgroundProcessing()
        await triggerSync()
    }

    func handleAuthStateChange(userId: UUID?) async {
        guard let userId else {
            await processingObserver?.stop()
            return
        }
        await startProcessingObserverIfNeeded(userId: userId)
        bootstrapBackgroundProcessingIfNeeded()
        refreshBackgroundProcessing()
        await triggerSync()
    }

    func handleNetworkBecameAvailable() async {
        bootstrapBackgroundProcessingIfNeeded()
        refreshBackgroundProcessing()
        await triggerSync()
    }

    func handleBackgroundRefresh() async {
        bootstrapBackgroundProcessingIfNeeded()
        refreshBackgroundProcessing()
        await triggerSync()
    }

    func handlePeriodicMaintenance() async {
        bootstrapBackgroundProcessingIfNeeded()
        refreshBackgroundProcessing()
        await triggerSync()
    }

    func syncPendingChanges() async {
        bootstrapBackgroundProcessingIfNeeded()
        await triggerSync()
    }

    func triggerManualSync() async {
        bootstrapBackgroundProcessingIfNeeded()
        refreshBackgroundProcessing()
        await triggerSync()
    }

    private func runBackgroundBootstrap() {
        if let backgroundBootstrapper {
            backgroundBootstrapper()
            return
        }

        if isDurableProcessingEnabled() {
            // The legacy recovery/queue services are NOT started: running both
            // pipelines would submit the same audio to AssemblyAI twice, which
            // is a billing bug as well as a correctness one.
            runDefaultBackgroundRefresh()
            return
        }

        TranscriptionRetryService.shared.migrateLegacyPendingTranscriptionsIfNeeded()
        SummaryRetryService.shared.migrateLegacyPendingSummariesIfNeeded()
        TranscriptionRetryService.shared.recoverIncompleteTranscriptions()
        SummaryRetryService.shared.recoverIncompleteSummaries()
        runDefaultBackgroundRefresh()
    }

    private func runDefaultBackgroundRefresh() {
        if isDurableProcessingEnabled() {
            // No stuck-job scanning, no queue pumping: the server's reaper owns
            // both. All the client does on foreground is (re)ask for jobs that
            // never got requested — an idempotent, cheap sweep.
            Task { await self.dispatchPendingDurableJobs() }
            return
        }

        TranscriptionRetryService.shared.checkForStuckProcessingTranscriptions()
        SummaryRetryService.shared.checkForStuckProcessingSummaries()
        TranscriptionRetryService.shared.processQueue()
        SummaryRetryService.shared.processQueue()
    }

    private func startRecoveredInterruptedProcessingIfNeeded() {
        guard let sermonService else { return }

        let recovered = sermonService.consumeRecoveredInterruptedSermonIDs()
        guard !recovered.isEmpty else { return }

        if isDurableProcessingEnabled() {
            Task {
                for sermonID in recovered {
                    await self.startDurableProcessing(for: sermonID)
                }
            }
            return
        }

        for sermonID in recovered {
            retryTranscription(for: sermonID)
        }
    }

    private func triggerSync() async {
        if let syncRunner {
            await syncRunner()
            return
        }

        await syncService?.syncAllData()
    }

    func handleCompletedRecording(
        audioURL: URL,
        title: String,
        date: Date,
        serviceType: String,
        notes: [Note],
        completion: ((Result<UUID, Error>) -> Void)? = nil
    ) {
        guard let sermonService else {
            print("[SermonProcessingCoordinator] SermonService not configured")
            completion?(.failure(SermonProcessingError.notConfigured))
            return
        }

        let sermonId = UUID()
        sermonService.saveSermon(
            title: title,
            audioFileURL: audioURL,
            date: date,
            serviceType: serviceType,
            speaker: nil,
            transcript: nil,
            notes: notes,
            summary: nil,
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            id: sermonId
        ) { result in
            if case .success(let savedId) = result {
                DispatchQueue.main.async {
                    if self.isDurableProcessingEnabled() {
                        Task { await self.startDurableProcessing(for: savedId) }
                    } else {
                        _ = self.retryTranscription(for: savedId)
                    }
                }
            }
            completion?(result)
        }
    }

    // MARK: - Durable pipeline

    /// Hands a freshly saved recording to the server.
    ///
    /// The sync push has to run first, and not as an optimization: it is what
    /// uploads the audio to storage and creates the sermon row that
    /// `POST /api/jobs` resolves. If it fails, the dispatch below fails too and
    /// the sermon simply stays pending — `dispatchPendingDurableJobs()` picks it
    /// up on the next foreground. Nothing is marked complete either way.
    private func startDurableProcessing(for sermonId: UUID) async {
        await triggerSync()
        _ = await durableDispatcher().dispatch(sermonLocalId: sermonId)
    }

    /// Applies a mid-session change to the durable-processing flag.
    ///
    /// Without this, flipping the toggle only wrote a UserDefaults key: the
    /// observer was started solely on an auth-state change, so a user who
    /// enabled the flag after launch could dispatch durable jobs that no
    /// Realtime subscription was listening for, and turning it back off left
    /// the subscription running.
    func handleProcessingModeChange(userId: UUID?) async {
        if isDurableProcessingEnabled() {
            if let userId {
                await startProcessingObserverIfNeeded(userId: userId)
            }
            await dispatchPendingDurableJobs()
        } else {
            await processingObserver?.stop()
            // Hand control back to the legacy queues, which have been idle
            // while the flag was on. Goes through the same seam as every other
            // refresh rather than calling the services directly.
            refreshBackgroundProcessing()
        }
    }

    /// Re-asks for any sermon that is uploaded but has no finished transcript.
    /// Safe to run as often as we like: `POST /api/jobs` returns the existing
    /// job rather than creating a second one.
    func dispatchPendingDurableJobs() async {
        guard isDurableProcessingEnabled(), let modelContext else { return }

        // The predicate deliberately covers only the string statuses. SwiftData's
        // handling of `optional != nil` inside #Predicate is unreliable, and no
        // other predicate in this codebase relies on it — the uploaded check is
        // done in memory below, over an already-small result set.
        let descriptor = FetchDescriptor<Sermon>(
            predicate: #Predicate<Sermon> { sermon in
                sermon.transcriptionStatus == "pending" || sermon.transcriptionStatus == "failed"
            }
        )

        guard let candidates = try? modelContext.fetch(descriptor) else { return }

        // Only sermons whose audio actually reached the server can be processed;
        // the rest are waiting on a sync push that hasn't happened yet.
        let uploaded = candidates.filter { $0.remoteId != nil }
        guard !uploaded.isEmpty else { return }

        // Exactly one pipeline may own a sermon, and the legacy queue's two
        // states mean different things here:
        //
        //   running — already handed to AssemblyAI. Dispatching would pay for a
        //             second transcription, so leave it; it will finish and set
        //             its own status.
        //   queued  — nobody has spent anything yet. The durable path can take
        //             it, but only by taking OWNERSHIP: with the flag on, the
        //             legacy queue is no longer pumped, so merely skipping these
        //             would strand the sermon pending forever.
        let legacy = legacyTranscriptionJobs(in: modelContext)
        let pending = uploaded.filter { !legacy.running.contains($0.id) }
        guard !pending.isEmpty else { return }

        let dispatcher = durableDispatcher()
        for sermon in pending {
            let adoptedJob = legacy.queued[sermon.id]

            // Drop the legacy job first so the two owners never overlap — if the
            // legacy queue pumped between dispatch and delete, the same audio
            // would go to the provider twice.
            if let adoptedJob {
                modelContext.delete(adoptedJob)
                try? modelContext.save()
            }

            let dispatched = await dispatcher.dispatch(sermonLocalId: sermon.id)

            // Handing ownership over failed, so hand it back rather than leaving
            // the sermon with no owner at all.
            if !dispatched, adoptedJob != nil {
                _ = TranscriptionRetryService.shared.enqueueTranscription(for: sermon.id)
            }
        }
    }

    /// Subscribes to this user's server-side jobs. A terminal job means new rows
    /// exist in Postgres, so the reaction is simply to sync — the pull phase is
    /// already the one piece of code that knows how to land a remote transcript
    /// and summary locally, and duplicating it here is how the two would drift.
    private func startProcessingObserverIfNeeded(userId: UUID) async {
        guard isDurableProcessingEnabled() else { return }

        let observer = processingObserver ?? ProcessingObserver()
        processingObserver = observer

        await observer.start(userId: userId) { [weak self] completion in
            print("[SermonProcessingCoordinator] Job \(completion.kind.rawValue) -> \(completion.status.rawValue)")
            guard let self else { return }
            Task { await self.triggerSync() }
        }
    }

    /// What the on-device retry queue currently owns, split by whether money has
    /// already been spent on it. The two are handled differently — see the call
    /// site — so they are deliberately not collapsed into one set.
    private func legacyTranscriptionJobs(
        in context: ModelContext
    ) -> (running: Set<UUID>, queued: [UUID: ProcessingJob]) {
        let queuedStatus = ProcessingJobStatus.queued.rawValue
        let runningStatus = ProcessingJobStatus.running.rawValue
        let kind = ProcessingJobKind.transcription.rawValue

        let descriptor = FetchDescriptor<ProcessingJob>(
            predicate: #Predicate<ProcessingJob> { job in
                job.kindRawValue == kind &&
                (job.statusRawValue == queuedStatus || job.statusRawValue == runningStatus)
            }
        )

        guard let jobs = try? context.fetch(descriptor) else { return ([], [:]) }

        var running: Set<UUID> = []
        var queued: [UUID: ProcessingJob] = [:]
        for job in jobs {
            if job.statusRawValue == runningStatus {
                running.insert(job.sermonId)
            } else {
                queued[job.sermonId] = job
            }
        }
        return (running, queued)
    }

    private func durableDispatcher() -> any ProcessingJobDispatching {
        if let processingDispatcher { return processingDispatcher }
        let created = ProcessingJobDispatcher.shared
        processingDispatcher = created
        return created
    }

    func enqueueTranscription(for sermonId: UUID) {
        TranscriptionRetryService.shared.enqueueTranscription(for: sermonId)
    }

    @discardableResult
    func retryTranscription(for sermonId: UUID) -> Bool {
        TranscriptionRetryService.shared.retryTranscriptionNow(for: sermonId)
    }

    func enqueueSummary(for sermonId: UUID) {
        SummaryRetryService.shared.enqueueSummary(for: sermonId)
    }

    @discardableResult
    func retrySummary(for sermonId: UUID) -> Bool {
        SummaryRetryService.shared.retrySummaryNow(for: sermonId)
    }

    func resetForTesting() {
        modelContext = nil
        sermonService = nil
        syncService = nil
        hasBootstrappedBackgroundProcessing = false
        backgroundBootstrapper = nil
        backgroundRefresher = nil
        syncRunner = nil
        processingDispatcher = nil
        processingObserver = nil
        isDurableProcessingEnabled = { FeatureFlags.shared.durableProcessingPipeline }
    }
}
