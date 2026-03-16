import Foundation
import SwiftData
import Testing
@testable import TabletNotes

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
}
