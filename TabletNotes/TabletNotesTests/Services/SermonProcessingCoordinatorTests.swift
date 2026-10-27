import Foundation
import SwiftData
import Testing
@testable import TabletNotes

@Suite(.serialized)
struct SermonProcessingCoordinatorTests {
    /// A fresh suite instance per test means a fresh recovery store per test;
    /// these suites used to contend on one global manifest key.
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

    // MARK: - Durable sweep (TAB-123)

    @MainActor
    private func seedSermon(
        _ context: ModelContext,
        status: String,
        remoteId: String? = "remote",
        date: Date = Date()
    ) throws -> Sermon {
        let sermon = Sermon(
            title: "Seed \(status)",
            audioFileName: "seed-\(UUID().uuidString).m4a",
            date: date,
            serviceType: "Sunday",
            transcriptionStatus: status,
            remoteId: remoteId
        )
        context.insert(sermon)
        try context.save()
        return sermon
    }

    @MainActor
    private func configuredCoordinator(
        _ context: ModelContext,
        dispatcher: any ProcessingJobDispatching
    ) -> SermonProcessingCoordinator {
        let coordinator = SermonProcessingCoordinator.shared
        coordinator.resetForTesting()
        coordinator.processingDispatcher = dispatcher
        coordinator.isDurableProcessingEnabled = { true }
        coordinator.syncRunner = {}
        coordinator.configure(
            modelContext: context,
            sermonService: SermonService(modelContext: context, recoveryStore: isolated.store, userDefaults: isolated.defaults)
        )
        return coordinator
    }

    private func job(_ sermonId: UUID, _ status: RemoteProcessingJob.Status, exhausted: Bool = false) -> RemoteProcessingJob {
        var job = RemoteProcessingJob(id: "job", sermonLocalId: sermonId, kind: .transcription, status: status, lastError: nil)
        job.exhausted = exhausted
        return job
    }

    @MainActor
    @Test func sweepDispatchesProcessingAndPreparingSermonsWithARemoteId() async throws {
        let context = try makeModelContext()
        let processing = try seedSermon(context, status: "processing")
        let preparing = try seedSermon(context, status: "preparing")
        _ = try seedSermon(context, status: "processing", remoteId: nil)
        _ = try seedSermon(context, status: "complete")

        let spy = DurableProcessingWiringTests.SpyDispatcher()
        let coordinator = configuredCoordinator(context, dispatcher: spy)
        defer { coordinator.resetForTesting() }

        await coordinator.dispatchPendingDurableJobs()

        #expect(Set(spy.dispatched.map(\.0)) == [processing.id, preparing.id])
        #expect(spy.dispatched.count == 2)
        #expect(spy.dispatched.allSatisfy { $0.1 == false })
    }

    @MainActor
    @Test func sweepDispatchesNewestSermonFirst() async throws {
        let context = try makeModelContext()
        let old = try seedSermon(context, status: "processing", date: Date().addingTimeInterval(-86_400))
        let new = try seedSermon(context, status: "processing", date: Date())

        let spy = DurableProcessingWiringTests.SpyDispatcher()
        let coordinator = configuredCoordinator(context, dispatcher: spy)
        defer { coordinator.resetForTesting() }

        await coordinator.dispatchPendingDurableJobs()

        #expect(spy.dispatched.map(\.0) == [new.id, old.id])
    }

    @MainActor
    @Test func sweepLeavesAProcessingSermonWhoseLegacyJobIsRunning() async throws {
        let context = try makeModelContext()
        let sermon = try seedSermon(context, status: "processing")
        context.insert(ProcessingJob(sermonId: sermon.id, kind: .transcription, status: .running))
        try context.save()

        let spy = DurableProcessingWiringTests.SpyDispatcher()
        let coordinator = configuredCoordinator(context, dispatcher: spy)
        defer { coordinator.resetForTesting() }

        await coordinator.dispatchPendingDurableJobs()

        #expect(spy.dispatched.isEmpty)
    }

    @MainActor
    @Test func sweepDoesNotReAskAJobTheServerConfirmedLive() async throws {
        let context = try makeModelContext()
        let sermon = try seedSermon(context, status: "processing")
        let mock = DurableProcessingWiringTests.MockJobRequester(result: .success(job(sermon.id, .submitted)))
        let coordinator = configuredCoordinator(context, dispatcher: ProcessingJobDispatcher(client: mock))
        defer { coordinator.resetForTesting() }

        await coordinator.dispatchPendingDurableJobs()
        await coordinator.dispatchPendingDurableJobs()
        await coordinator.dispatchPendingDurableJobs()

        // First sweep is the repair request for an orphan; the rest are skipped.
        #expect(mock.requested.count == 1)
    }

    @MainActor
    @Test func sweepDoesNotReAskAnExhaustedJob() async throws {
        let context = try makeModelContext()
        let sermon = try seedSermon(context, status: "processing")
        let mock = DurableProcessingWiringTests.MockJobRequester(result: .success(job(sermon.id, .dead, exhausted: true)))
        let coordinator = configuredCoordinator(context, dispatcher: ProcessingJobDispatcher(client: mock))
        defer { coordinator.resetForTesting() }

        await coordinator.dispatchPendingDurableJobs()
        await coordinator.dispatchPendingDurableJobs()

        #expect(mock.requested.count == 1)
    }

    @MainActor
    @Test func sweepKeepsAskingWhileTheRequestFails() async throws {
        let context = try makeModelContext()
        _ = try seedSermon(context, status: "processing")
        let mock = DurableProcessingWiringTests.MockJobRequester(result: .failure(ProcessingJobClientError.offline))
        let coordinator = configuredCoordinator(context, dispatcher: ProcessingJobDispatcher(client: mock))
        defer { coordinator.resetForTesting() }

        await coordinator.dispatchPendingDurableJobs()
        await coordinator.dispatchPendingDurableJobs()

        #expect(mock.requested.count == 2)
    }

    @MainActor
    @Test func lifecycleHandlersBootstrapOnceAndRouteRefreshThroughCoordinator() async throws {
        let context = try makeModelContext()
        let sermonService = SermonService(modelContext: context, recoveryStore: isolated.store, userDefaults: isolated.defaults)
        let coordinator = SermonProcessingCoordinator.shared

        defer {
            coordinator.resetForTesting()
        }

        var bootstrapCount = 0
        var refreshCount = 0
        var syncCount = 0

        coordinator.resetForTesting()
        coordinator.backgroundBootstrapper = {
            bootstrapCount += 1
        }
        coordinator.backgroundRefresher = {
            refreshCount += 1
        }
        coordinator.syncRunner = {
            syncCount += 1
        }
        coordinator.configure(modelContext: context, sermonService: sermonService)

        await coordinator.handleAppLaunch(syncDelayNanoseconds: 0)
        await coordinator.handleAppDidBecomeActive()
        await coordinator.handleAuthStateChange(userId: UUID())
        await coordinator.handleAuthStateChange(userId: nil)

        #expect(bootstrapCount == 1)
        #expect(refreshCount == 2)
        #expect(syncCount == 3)
    }

    @MainActor
    @Test func syncPendingChangesSkipsRefreshButStillBootstrapsAndSyncs() async throws {
        let context = try makeModelContext()
        let sermonService = SermonService(modelContext: context, recoveryStore: isolated.store, userDefaults: isolated.defaults)
        let coordinator = SermonProcessingCoordinator.shared

        defer {
            coordinator.resetForTesting()
        }

        var bootstrapCount = 0
        var refreshCount = 0
        var syncCount = 0

        coordinator.resetForTesting()
        coordinator.backgroundBootstrapper = {
            bootstrapCount += 1
        }
        coordinator.backgroundRefresher = {
            refreshCount += 1
        }
        coordinator.syncRunner = {
            syncCount += 1
        }
        coordinator.configure(modelContext: context, sermonService: sermonService)

        await coordinator.syncPendingChanges()
        await coordinator.syncPendingChanges()

        #expect(bootstrapCount == 1)
        #expect(refreshCount == 0)
        #expect(syncCount == 2)
    }

    @MainActor
    @Test func handleAppLaunchImmediatelyProcessesRecoveredInterruptedRecordings() async throws {
        isolated.store.clear()

        let audioDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let audioURL = audioDirectory.appendingPathComponent("launch-recovery-\(UUID().uuidString).m4a")
        _ = FileManager.default.createFile(atPath: audioURL.path, contents: Data(repeating: 0x09, count: 4096))

        let noteService = NoteService(sessionId: "launch-recovery-session")
        noteService.addNote(text: "Recovered launch note", timestamp: 3)

        let mockAuthService = MockAuthService()
        let currentUser = MockAuthService.createMockUser()
        mockAuthService.setAuthState(.authenticated(currentUser))
        let authManager = AuthenticationManager(authService: mockAuthService)

        isolated.store.save(
            InterruptedRecordingManifest(
                sessionId: "launch-recovery-session",
                serviceType: "Sermon",
                audioFileName: audioURL.lastPathComponent,
                startedAt: Date().addingTimeInterval(-90),
                userId: currentUser.id
            )
        )

        let context = try makeModelContext()
        let sermonService = SermonService(modelContext: context, authManager: authManager, recoveryStore: isolated.store, userDefaults: isolated.defaults)
        let coordinator = SermonProcessingCoordinator.shared
        let retryService = TranscriptionRetryService.shared

        defer {
            retryService.transcriptionRunner = nil
            retryService.summaryEnqueuer = nil
            retryService.overrideNetworkAvailability(false)
            coordinator.resetForTesting()
            isolated.store.clear()
            try? FileManager.default.removeItem(at: audioURL)
        }

        coordinator.resetForTesting()
        // This test pins LEGACY-path behavior, which still exists behind the
        // flag as the rollback story. Since TAB-103 the shipped default is
        // durable-ON, so the path under test is selected explicitly.
        coordinator.isDurableProcessingEnabled = { false }
        coordinator.syncRunner = {}
        coordinator.configure(modelContext: context, sermonService: sermonService)

        var runnerCallCount = 0
        retryService.transcriptionRunner = { _, completion in
            runnerCallCount += 1
            completion(.success((
                "Recovered on launch",
                [TranscriptSegment(text: "Recovered on launch", startTime: 0, endTime: 2)]
            )))
        }
        retryService.summaryEnqueuer = { _, _ in }

        await coordinator.handleAppLaunch(syncDelayNanoseconds: 0)

        var recoveredSermon: Sermon?
        for _ in 0..<20 {
            let sermons = try context.fetch(FetchDescriptor<Sermon>())
            #expect(sermons.count == 1)

            if let sermon = sermons.first,
               sermon.transcriptionStatus == "complete",
               sermon.transcript?.text == "Recovered on launch" {
                recoveredSermon = sermon
                break
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(runnerCallCount == 1)
        #expect(recoveredSermon?.transcriptionStatus == "complete")
        #expect(recoveredSermon?.transcript?.text == "Recovered on launch")
    }

    @MainActor
    @Test func completedRecordingStartsTranscriptionEvenWhenReachabilityStateIsStale() async throws {
        let context = try makeModelContext()
        let mockAuthService = MockAuthService()
        mockAuthService.setAuthState(.authenticated(
            MockAuthService.createMockUser(email: "coordinator@test.com")
        ))
        let authManager = AuthenticationManager(authService: mockAuthService)
        for _ in 0..<20 where authManager.currentUser == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let sermonService = SermonService(modelContext: context, authManager: authManager, recoveryStore: isolated.store, userDefaults: isolated.defaults)
        let coordinator = SermonProcessingCoordinator.shared
        let retryService = TranscriptionRetryService.shared

        let audioDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let audioURL = audioDirectory.appendingPathComponent("completed-recording-\(UUID().uuidString).m4a")
        _ = FileManager.default.createFile(atPath: audioURL.path, contents: Data(repeating: 0x0A, count: 4096))

        defer {
            retryService.transcriptionRunner = nil
            retryService.summaryEnqueuer = nil
            retryService.overrideNetworkAvailability(false)
            coordinator.resetForTesting()
            try? FileManager.default.removeItem(at: audioURL)
        }

        coordinator.resetForTesting()
        // This test pins LEGACY-path behavior, which still exists behind the
        // flag as the rollback story. Since TAB-103 the shipped default is
        // durable-ON, so the path under test is selected explicitly.
        coordinator.isDurableProcessingEnabled = { false }
        coordinator.syncRunner = {}
        coordinator.configure(modelContext: context, sermonService: sermonService)

        var runnerCallCount = 0
        retryService.overrideNetworkAvailability(false)
        retryService.transcriptionRunner = { _, completion in
            runnerCallCount += 1
            completion(.success((
                "Auto-started transcript",
                [TranscriptSegment(text: "Auto-started transcript", startTime: 0, endTime: 2)]
            )))
        }
        retryService.summaryEnqueuer = { _, _ in }

        let saveResult = await withCheckedContinuation { continuation in
            coordinator.handleCompletedRecording(
                audioURL: audioURL,
                title: "Completed Recording",
                date: Date(),
                serviceType: "Sermon",
                notes: []
            ) { result in
                continuation.resume(returning: result)
            }
        }
        guard case .success(let savedId) = saveResult else {
            Issue.record("Expected completed recording save to succeed, got \(saveResult)")
            return
        }

        var savedSermon: Sermon?
        for _ in 0..<40 {
            let sermons = try context.fetch(FetchDescriptor<Sermon>())
            if let sermon = sermons.first(where: { $0.id == savedId }),
               sermon.transcriptionStatus == "complete",
               sermon.transcript?.text == "Auto-started transcript" {
                savedSermon = sermon
                break
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(runnerCallCount == 1)
        #expect(savedSermon?.transcriptionStatus == "complete")
        #expect(savedSermon?.transcript?.text == "Auto-started transcript")
    }
}
