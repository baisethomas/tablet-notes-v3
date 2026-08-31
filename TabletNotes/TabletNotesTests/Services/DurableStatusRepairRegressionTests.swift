import Foundation
import SwiftData
import Testing
@testable import TabletNotes

/// Regression tests for TAB-97: with the durable processing pipeline enabled,
/// the coordinator skips the legacy recovery sweeps (running both pipelines
/// would double-bill AssemblyAI) — but those sweeps were also the only carrier
/// of the TAB-94 status repair. A sermon whose transcript/summary already
/// exists but whose status string was walked back to "pending"/"processing"
/// (TAB-95) then stays "preparing" forever, locally and on the server, because
/// nothing repairs the status and nothing marks it for push.
///
/// The repair is status-only: no jobs minted, nothing submitted, no network.
@Suite(.serialized)
struct DurableStatusRepairRegressionTests {
    private let isolated = IsolatedRecoveryStore()

    @MainActor
    private func makeModelContext() throws -> ModelContext {
        isolated.defaults.removeObject(forKey: "SermonService.localDataOwnerUserId")
        let schema = Schema([
            Sermon.self,
            Note.self,
            Transcript.self,
            Summary.self,
            ProcessingJob.self,
            TranscriptSegment.self,
            ChatMessage.self,
            User.self,
            UserNotificationSettings.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }

    @MainActor
    private func makePoisonedSermon(
        transcriptionStatus: String,
        summaryStatus: String,
        withTranscript: Bool = true,
        withSummary: Bool = true
    ) -> Sermon {
        let transcript = withTranscript
            ? Transcript(text: String(repeating: "Already transcribed. ", count: 20))
            : nil
        let summary = withSummary
            ? Summary(
                title: "Existing Summary",
                text: "The summary that already exists.",
                type: "Sunday Service",
                status: "complete"
            )
            : nil
        return Sermon(
            title: "Poisoned Sermon",
            audioFileName: "tab97-\(UUID().uuidString).m4a",
            date: Date().addingTimeInterval(-3600),
            serviceType: "Sunday Service",
            transcript: transcript,
            notes: [],
            summary: summary,
            syncStatus: "synced",
            transcriptionStatus: transcriptionStatus,
            summaryStatus: summaryStatus,
            userId: UUID()
        )
    }

    /// The exact incident (owner device, 2026-08-30): durable flag ON, sermon
    /// holds both children, statuses stuck at "processing"/"pending". A
    /// foreground refresh must repair both statuses forward and mark metadata
    /// for push — without minting any job.
    @MainActor
    @Test func durableRefreshRepairsPoisonedStatusesWithoutSpendingWork() async throws {
        let context = try makeModelContext()
        let sermonService = SermonService(modelContext: context, recoveryStore: isolated.store, userDefaults: isolated.defaults)

        let sermon = makePoisonedSermon(transcriptionStatus: "processing", summaryStatus: "pending")
        context.insert(sermon)
        try context.save()

        let coordinator = SermonProcessingCoordinator.shared
        coordinator.resetForTesting()
        defer { coordinator.resetForTesting() }
        coordinator.isDurableProcessingEnabled = { true }
        coordinator.configure(modelContext: context, sermonService: sermonService)

        coordinator.refreshBackgroundProcessing()

        #expect(sermon.transcriptionStatus == "complete")
        #expect(sermon.summaryStatus == "complete")
        #expect(sermon.metadataNeedsSync)

        let jobs = try context.fetch(FetchDescriptor<ProcessingJob>())
        #expect(jobs.isEmpty)

        // The repair must be persisted, not pending autosave: a fresh context
        // sees only saved state.
        let freshContext = ModelContext(context.container)
        let persisted = try freshContext.fetch(FetchDescriptor<Sermon>()).first(where: { $0.id == sermon.id })
        #expect(persisted?.transcriptionStatus == "complete")
        #expect(persisted?.summaryStatus == "complete")
        #expect(persisted?.metadataNeedsSync == true)
    }

    /// A sermon with no children must be left exactly as it is — the repair is
    /// only ever forward, toward a child that already exists. (The durable
    /// dispatch sweep owns genuinely-pending work.)
    @MainActor
    @Test func durableRefreshLeavesGenuinelyPendingSermonsAlone() async throws {
        let context = try makeModelContext()
        let sermonService = SermonService(modelContext: context, recoveryStore: isolated.store, userDefaults: isolated.defaults)

        let sermon = makePoisonedSermon(
            transcriptionStatus: "processing",
            summaryStatus: "pending",
            withTranscript: false,
            withSummary: false
        )
        context.insert(sermon)
        try context.save()

        let coordinator = SermonProcessingCoordinator.shared
        coordinator.resetForTesting()
        defer { coordinator.resetForTesting() }
        coordinator.isDurableProcessingEnabled = { true }
        coordinator.configure(modelContext: context, sermonService: sermonService)

        coordinator.refreshBackgroundProcessing()

        #expect(sermon.transcriptionStatus == "processing")
        #expect(sermon.summaryStatus == "pending")
        #expect(!sermon.metadataNeedsSync)
    }

    // MARK: - Service-level sweeps

    @MainActor
    @Test func transcriptionRepairSweepFixesPoisonedStatusWithoutMintingJobs() async throws {
        let context = try makeModelContext()
        let poisoned = makePoisonedSermon(transcriptionStatus: "processing", summaryStatus: "complete")
        let untranscribed = makePoisonedSermon(
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            withTranscript: false,
            withSummary: false
        )
        context.insert(poisoned)
        context.insert(untranscribed)
        try context.save()

        let retryService = TranscriptionRetryService()
        retryService.setModelContext(context)

        retryService.repairAlreadyTranscribedStatuses()

        #expect(poisoned.transcriptionStatus == "complete")
        #expect(poisoned.metadataNeedsSync)
        #expect(untranscribed.transcriptionStatus == "pending")
        #expect(!untranscribed.metadataNeedsSync)

        let jobs = try context.fetch(FetchDescriptor<ProcessingJob>())
        #expect(jobs.isEmpty)
    }

    @MainActor
    @Test func summaryRepairSweepFixesPoisonedStatusWithoutMintingJobs() async throws {
        let context = try makeModelContext()
        let poisoned = makePoisonedSermon(transcriptionStatus: "complete", summaryStatus: "pending")
        let alreadyComplete = makePoisonedSermon(transcriptionStatus: "complete", summaryStatus: "complete")
        context.insert(poisoned)
        context.insert(alreadyComplete)
        try context.save()

        let retryService = SummaryRetryService()
        retryService.setModelContext(context)

        retryService.repairAlreadySummarizedStatuses()

        #expect(poisoned.summaryStatus == "complete")
        #expect(poisoned.metadataNeedsSync)
        // A sermon whose status is already terminal must not be re-dirtied
        // into an endless push loop.
        #expect(!alreadyComplete.metadataNeedsSync)

        let jobs = try context.fetch(FetchDescriptor<ProcessingJob>())
        #expect(jobs.isEmpty)
    }
}
