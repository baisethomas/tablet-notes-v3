import Foundation
import SwiftData
import Testing
@testable import TabletNotes

@MainActor
struct SermonServiceDeleteTests {
    final class MockSyncService: SyncServiceProtocol {
        private(set) var deletedRemoteIds: [String] = []
        private(set) var syncAllDataCallCount = 0
        var deleteRemoteSermonError: Error?

        func syncAllData() async {
            syncAllDataCallCount += 1
        }

        func deleteRemoteSermon(remoteId: String) async throws {
            if let deleteRemoteSermonError {
                throw deleteRemoteSermonError
            }
            deletedRemoteIds.append(remoteId)
        }

        func deleteAllCloudData() async {}
    }

    private func makeModelContext() throws -> ModelContext {
        UserDefaults.standard.removeObject(forKey: "SermonService.localDataOwnerUserId")
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

    private func makeSermonService(
        modelContext: ModelContext,
        syncService: (any SyncServiceProtocol)?
    ) -> SermonService {
        let mockAuthService = MockAuthService()
        let currentUser = MockAuthService.createMockUser()
        mockAuthService.setAuthState(.authenticated(currentUser))
        let authManager = AuthenticationManager(authService: mockAuthService)
        return SermonService(
            modelContext: modelContext,
            authManager: authManager,
            syncService: syncService
        )
    }

    private func insertSermon(
        modelContext: ModelContext,
        remoteId: String? = nil
    ) throws -> Sermon {
        let sermon = Sermon(
            title: "Sermon to Delete",
            audioFileName: "delete-me.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: remoteId == nil ? "localOnly" : "synced",
            transcriptionStatus: "complete",
            summaryStatus: "complete",
            remoteId: remoteId,
            updatedAt: Date()
        )
        modelContext.insert(sermon)
        try modelContext.save()
        return sermon
    }

    @Test func deleteSermonWithRemoteIdDeletesCloudCopyThenLocalRow() async throws {
        let modelContext = try makeModelContext()
        let syncService = MockSyncService()
        let sermonService = makeSermonService(modelContext: modelContext, syncService: syncService)
        let sermon = try insertSermon(modelContext: modelContext, remoteId: "remote-123")

        try await sermonService.deleteSermon(sermon)

        #expect(syncService.deletedRemoteIds == ["remote-123"])
        let remaining = try modelContext.fetch(FetchDescriptor<Sermon>())
        #expect(remaining.isEmpty)
    }

    @Test func deleteSermonKeepsLocalRowWhenCloudDeleteFails() async throws {
        let modelContext = try makeModelContext()
        let syncService = MockSyncService()
        syncService.deleteRemoteSermonError = SyncError.networkError
        let sermonService = makeSermonService(modelContext: modelContext, syncService: syncService)
        let sermon = try insertSermon(modelContext: modelContext, remoteId: "remote-123")

        await #expect(throws: SermonDeleteError.self) {
            try await sermonService.deleteSermon(sermon)
        }

        #expect(syncService.deletedRemoteIds.isEmpty)
        let remaining = try modelContext.fetch(FetchDescriptor<Sermon>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.remoteId == "remote-123")
    }

    @Test func deleteSermonWithoutRemoteIdSkipsCloudDelete() async throws {
        let modelContext = try makeModelContext()
        let syncService = MockSyncService()
        let sermonService = makeSermonService(modelContext: modelContext, syncService: syncService)
        let sermon = try insertSermon(modelContext: modelContext, remoteId: nil)

        try await sermonService.deleteSermon(sermon)

        #expect(syncService.deletedRemoteIds.isEmpty)
        let remaining = try modelContext.fetch(FetchDescriptor<Sermon>())
        #expect(remaining.isEmpty)
    }

    @Test func deleteSermonWithoutSyncServiceStillDeletesLocally() async throws {
        let modelContext = try makeModelContext()
        let sermonService = makeSermonService(modelContext: modelContext, syncService: nil)
        let sermon = try insertSermon(modelContext: modelContext, remoteId: "remote-123")

        try await sermonService.deleteSermon(sermon)

        let remaining = try modelContext.fetch(FetchDescriptor<Sermon>())
        #expect(remaining.isEmpty)
    }
}
