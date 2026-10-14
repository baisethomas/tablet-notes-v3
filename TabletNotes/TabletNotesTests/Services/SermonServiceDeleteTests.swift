import Foundation
import SwiftData
import Testing
@testable import TabletNotes

@MainActor
struct SermonServiceDeleteTests {
    /// A fresh suite instance per test means a fresh recovery store per test;
    /// these suites used to contend on one global manifest key.
    private let isolated = IsolatedRecoveryStore()

    final class MockSyncService: SyncServiceProtocol {
        private(set) var deletedRemoteIds: [String] = []
        private(set) var syncAllDataCallCount = 0
        var deleteRemoteSermonError: Error?

        var syncSucceeds = true

        func syncAllData() async {
            syncAllDataCallCount += 1
        }

        func syncAllDataReportingSuccess() async -> Bool {
            syncAllDataCallCount += 1
            return syncSucceeds
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
            syncService: syncService,
            recoveryStore: isolated.store,
            userDefaults: isolated.defaults
        )
    }

    // MARK: - Scripture reminder cancels (TAB-119)

    /// The list's swipe and context menu archive through the toggle, not
    /// `archiveSermon`, so the cancel has to live on this path.
    @Test func archivingThroughTheToggleCancelsThatSermonsReminders() async throws {
        let modelContext = try makeModelContext()
        let service = makeSermonService(modelContext: modelContext, syncService: nil)
        let reminders = MockScriptureReminderScheduling()
        service.setScriptureReminderScheduler(reminders)
        let sermon = try insertSermon(modelContext: modelContext)

        service.toggleSermonArchiveStatus(sermon)
        for _ in 0..<20 where reminders.cancelledSermonIds.isEmpty {
            await Task.yield()
        }
        #expect(reminders.cancelledSermonIds == [sermon.id])

        // Unarchiving is not a cancel.
        service.toggleSermonArchiveStatus(sermon)
        for _ in 0..<5 { await Task.yield() }
        #expect(reminders.cancelledSermonIds == [sermon.id])
    }

    @Test func deletingCancelsThatSermonsReminders() async throws {
        let modelContext = try makeModelContext()
        let service = makeSermonService(modelContext: modelContext, syncService: nil)
        let reminders = MockScriptureReminderScheduling()
        service.setScriptureReminderScheduler(reminders)
        let sermon = try insertSermon(modelContext: modelContext)

        try await service.deleteSermon(sermon)

        #expect(reminders.cancelledSermonIds == [sermon.id])
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

    @Test func deleteSyncedSermonWithoutSyncServiceFailsClosed() async throws {
        let modelContext = try makeModelContext()
        let sermonService = makeSermonService(modelContext: modelContext, syncService: nil)
        let sermon = try insertSermon(modelContext: modelContext, remoteId: "remote-123")

        await #expect(throws: SermonDeleteError.self) {
            try await sermonService.deleteSermon(sermon)
        }

        let remaining = try modelContext.fetch(FetchDescriptor<Sermon>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.remoteId == "remote-123")
    }

    @Test func deleteLocalOnlySermonWithoutSyncServiceStillDeletes() async throws {
        let modelContext = try makeModelContext()
        let sermonService = makeSermonService(modelContext: modelContext, syncService: nil)
        let sermon = try insertSermon(modelContext: modelContext, remoteId: nil)

        try await sermonService.deleteSermon(sermon)

        let remaining = try modelContext.fetch(FetchDescriptor<Sermon>())
        #expect(remaining.isEmpty)
    }
}
