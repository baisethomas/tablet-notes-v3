import Foundation
import SwiftData
import Testing
@testable import TabletNotes

// TAB-114: foregrounding the app mid-recording re-ran MainAppView.init, which
// built a throwaway SermonService whose interrupted-recording scan loaded the
// LIVE recording's manifest, deleted it, and cleared the live note session
// (the TAB-113 trigger, caught on device 2026-09-13 17:27:51). A manifest
// whose session is the recording in progress is not an interrupted recording
// and the scan must leave both the manifest and the session alone.
struct SermonServiceLiveRecoveryTests {

    private let isolated = IsolatedRecoveryStore()

    private func makeModelContext() throws -> ModelContext {
        isolated.defaults.removeObject(forKey: "SermonService.localDataOwnerUserId")
        let schema = Schema([
            Sermon.self, Note.self, Transcript.self, Summary.self,
            ProcessingJob.self, TranscriptSegment.self, ChatMessage.self,
            User.self, UserNotificationSettings.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @MainActor
    private func makeAuthManager() -> (AuthenticationManager, User) {
        let mock = MockAuthService()
        let user = MockAuthService.createMockUser()
        mock.setAuthState(.authenticated(user))
        return (AuthenticationManager(authService: mock), user)
    }

    @MainActor
    @Test func recoveryScanLeavesTheLiveRecordingsManifestAndNotesAlone() throws {
        let modelContext = try makeModelContext()
        let (authManager, user) = makeAuthManager()
        let live = "tab114-live-\(UUID().uuidString)"
        let previous = NoteService.liveRecordingSessionProvider
        NoteService.liveRecordingSessionProvider = { live }
        defer {
            NoteService.liveRecordingSessionProvider = previous
            NoteService.shared(for: live).clearSession()
        }
        NoteService.shared(for: live).stagePrimaryNoteText("mid-sermon note", timestamp: 600)
        let manifest = InterruptedRecordingManifest(
            sessionId: live,
            serviceType: "Sermon",
            audioFileName: "sermon_\(UUID().uuidString).m4a",
            startedAt: Date().addingTimeInterval(-600),
            userId: user.id
        )
        isolated.store.save(manifest)

        // The throwaway instance TAB-114 describes: init runs fetchSermons →
        // recoverInterruptedRecordingIfNeeded on a fresh guard.
        let service = SermonService(
            modelContext: modelContext,
            authManager: authManager,
            recoveryStore: isolated.store,
            userDefaults: isolated.defaults
        )

        #expect(isolated.store.load() == manifest, "live manifest must survive the scan")
        #expect(NoteService.shared(for: live).currentNotes.first?.text == "mid-sermon note")
        #expect(NoteService.shared(for: live).stagePrimaryNoteText("mid-sermon note, continued", timestamp: 601))
        #expect(!service.sermons.contains { $0.audioFileName == manifest.audioFileName }, "no phantom recovered sermon")
    }

    /// A manifest that is NOT the live recording is still recovered as before
    /// (here: audio missing → manifest discarded), so the guard is narrow.
    @MainActor
    @Test func recoveryScanStillHandlesAGenuinelyInterruptedManifest() throws {
        let modelContext = try makeModelContext()
        let (authManager, user) = makeAuthManager()
        let previous = NoteService.liveRecordingSessionProvider
        NoteService.liveRecordingSessionProvider = { nil }
        defer { NoteService.liveRecordingSessionProvider = previous }
        isolated.store.save(InterruptedRecordingManifest(
            sessionId: "tab114-interrupted-\(UUID().uuidString)",
            serviceType: "Sermon",
            audioFileName: "sermon_\(UUID().uuidString).m4a",
            startedAt: Date().addingTimeInterval(-3600),
            userId: user.id
        ))

        _ = SermonService(
            modelContext: modelContext,
            authManager: authManager,
            recoveryStore: isolated.store,
            userDefaults: isolated.defaults
        )

        #expect(isolated.store.load() == nil, "a stale manifest with no audio is discarded, as before")
    }
}
