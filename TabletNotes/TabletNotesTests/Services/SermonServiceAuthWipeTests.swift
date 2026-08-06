import Foundation
import SwiftData
import Testing
@testable import TabletNotes

/// Regression tests for TAB-65: an authenticated → unauthenticated transition
/// must never wipe local data unless (1) the user explicitly signed out AND
/// (2) nothing on-device is the only copy (no pending sync work, no
/// interrupted-recording manifest, no cloud-less sermon).
@MainActor
struct SermonServiceAuthWipeTests {
    private func makeModelContext() throws -> ModelContext {
        UserDefaults.standard.removeObject(forKey: "SermonService.localDataOwnerUserId")
        UserDefaults.standard.removeObject(forKey: "active_recording_manifest")
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

    private func makeAuthedService(
        modelContext: ModelContext
    ) -> (SermonService, AuthenticationManager, MockAuthService) {
        let mockAuthService = MockAuthService()
        let currentUser = MockAuthService.createMockUser()
        mockAuthService.setAuthState(.authenticated(currentUser))
        let authManager = AuthenticationManager(authService: mockAuthService)
        let service = SermonService(
            modelContext: modelContext,
            authManager: authManager,
            syncService: nil
        )
        return (service, authManager, mockAuthService)
    }

    @discardableResult
    private func insertSermon(
        modelContext: ModelContext,
        remoteId: String?,
        pendingSync: Bool = false
    ) throws -> Sermon {
        let sermon = Sermon(
            title: "Sunday Message",
            audioFileName: "auth-wipe-test.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: remoteId == nil ? "localOnly" : "synced",
            transcriptionStatus: "complete",
            summaryStatus: "complete",
            remoteId: remoteId,
            updatedAt: Date()
        )
        if pendingSync {
            sermon.markPendingSync(metadata: true)
        }
        modelContext.insert(sermon)
        try modelContext.save()
        return sermon
    }

    /// Lets the Combine sink + inner Task in setupAuthStateObserver run.
    private func settle() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    private func sermonCount(_ modelContext: ModelContext) throws -> Int {
        try modelContext.fetch(FetchDescriptor<Sermon>()).count
    }

    @Test func sessionExpiryDoesNotWipeLocalData() async throws {
        let modelContext = try makeModelContext()
        let (_, _, mockAuthService) = makeAuthedService(modelContext: modelContext)
        try insertSermon(modelContext: modelContext, remoteId: "remote-1")
        await settle()

        // A failed token refresh / Supabase outage lands here WITHOUT the user
        // ever tapping sign out. Before TAB-65 this path deleted every sermon
        // and every audio file on the device.
        mockAuthService.setAuthState(.unauthenticated)
        await settle()

        #expect(try sermonCount(modelContext) == 1)
    }

    @Test func userSignOutWithUnsyncedSermonPreservesData() async throws {
        let modelContext = try makeModelContext()
        let (_, authManager, _) = makeAuthedService(modelContext: modelContext)
        try insertSermon(modelContext: modelContext, remoteId: nil)
        await settle()

        // Free-tier users cannot sync: every sermon is localOnly, and a
        // sign-out wipe would be unrecoverable. The wipe must refuse.
        try await authManager.signOut()
        await settle()

        #expect(try sermonCount(modelContext) == 1)
    }

    @Test func userSignOutWithPendingSyncWorkPreservesData() async throws {
        let modelContext = try makeModelContext()
        let (_, authManager, _) = makeAuthedService(modelContext: modelContext)
        try insertSermon(modelContext: modelContext, remoteId: "remote-1", pendingSync: true)
        await settle()

        try await authManager.signOut()
        await settle()

        #expect(try sermonCount(modelContext) == 1)
    }

    @Test func userSignOutWithInterruptedRecordingPreservesData() async throws {
        let modelContext = try makeModelContext()
        let (_, authManager, _) = makeAuthedService(modelContext: modelContext)
        try insertSermon(modelContext: modelContext, remoteId: "remote-1")
        InterruptedRecordingRecoveryStore.save(
            InterruptedRecordingManifest(
                sessionId: UUID().uuidString,
                serviceType: "Sunday Service",
                audioFileName: "in-flight.m4a",
                startedAt: Date(),
                userId: nil
            )
        )
        defer { InterruptedRecordingRecoveryStore.clear() }
        await settle()

        // An in-flight/unrecovered recording is the only copy of that audio;
        // even an explicit sign-out must not destroy it.
        try await authManager.signOut()
        await settle()

        #expect(try sermonCount(modelContext) == 1)
    }

    @Test func userSignOutWithEverythingSyncedWipesData() async throws {
        let modelContext = try makeModelContext()
        let (_, authManager, _) = makeAuthedService(modelContext: modelContext)
        try insertSermon(modelContext: modelContext, remoteId: "remote-1")
        await settle()

        // The one case where the wipe SHOULD run: explicit sign-out and every
        // sermon confirmed in the cloud.
        try await authManager.signOut()
        await settle()

        #expect(try sermonCount(modelContext) == 0)
    }
}
