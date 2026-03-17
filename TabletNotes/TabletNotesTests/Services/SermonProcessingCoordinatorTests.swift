import Foundation
import SwiftData
import Testing
@testable import TabletNotes

@Suite(.serialized)
struct SermonProcessingCoordinatorTests {

    @MainActor
    private func makeModelContext() throws -> ModelContext {
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
    @Test func lifecycleHandlersBootstrapOnceAndRouteRefreshThroughCoordinator() async throws {
        let context = try makeModelContext()
        let sermonService = SermonService(modelContext: context)
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
        let sermonService = SermonService(modelContext: context)
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
        InterruptedRecordingRecoveryStore.clear()

        let audioDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let audioURL = audioDirectory.appendingPathComponent("launch-recovery-\(UUID().uuidString).m4a")
        _ = FileManager.default.createFile(atPath: audioURL.path, contents: Data(repeating: 0x09, count: 4096))

        let noteService = NoteService(sessionId: "launch-recovery-session")
        noteService.addNote(text: "Recovered launch note", timestamp: 3)
        InterruptedRecordingRecoveryStore.save(
            InterruptedRecordingManifest(
                sessionId: "launch-recovery-session",
                serviceType: "Sermon",
                audioFileName: audioURL.lastPathComponent,
                startedAt: Date().addingTimeInterval(-90)
            )
        )

        let context = try makeModelContext()
        let sermonService = SermonService(modelContext: context)
        let coordinator = SermonProcessingCoordinator.shared
        let retryService = TranscriptionRetryService.shared

        defer {
            retryService.transcriptionRunner = nil
            retryService.summaryEnqueuer = nil
            retryService.overrideNetworkAvailability(false)
            coordinator.resetForTesting()
            InterruptedRecordingRecoveryStore.clear()
            try? FileManager.default.removeItem(at: audioURL)
        }

        coordinator.resetForTesting()
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
        retryService.summaryEnqueuer = { _ in }

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
}
