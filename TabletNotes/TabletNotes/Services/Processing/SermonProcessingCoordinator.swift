import Foundation
import SwiftData

@MainActor
final class SermonProcessingCoordinator {
    static let shared = SermonProcessingCoordinator()

    private var modelContext: ModelContext?
    private weak var sermonService: SermonService?
    private var syncService: SyncServiceProtocol?
    private var hasBootstrappedBackgroundProcessing = false

    var backgroundBootstrapper: (@MainActor () -> Void)?
    var backgroundRefresher: (@MainActor () -> Void)?
    var syncRunner: (@MainActor () async -> Void)?

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
        guard userId != nil else { return }
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

        TranscriptionRetryService.shared.migrateLegacyPendingTranscriptionsIfNeeded()
        SummaryRetryService.shared.migrateLegacyPendingSummariesIfNeeded()
        runDefaultBackgroundRefresh()
    }

    private func runDefaultBackgroundRefresh() {
        TranscriptionRetryService.shared.recoverIncompleteTranscriptions()
        SummaryRetryService.shared.recoverIncompleteSummaries()
        SummaryRetryService.shared.checkForStuckProcessingSummaries()
        TranscriptionRetryService.shared.processQueue()
        SummaryRetryService.shared.processQueue()
    }

    private func startRecoveredInterruptedProcessingIfNeeded() {
        guard let sermonService else { return }

        for sermonID in sermonService.consumeRecoveredInterruptedSermonIDs() {
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
        completion: ((UUID) -> Void)? = nil
    ) {
        guard let sermonService else {
            print("[SermonProcessingCoordinator] SermonService not configured")
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
        ) { savedId in
            self.enqueueTranscription(for: savedId)
            completion?(savedId)
        }
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
    }
}
