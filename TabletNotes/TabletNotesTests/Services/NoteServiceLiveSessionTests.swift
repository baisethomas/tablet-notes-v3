import Foundation
import Testing
@testable import TabletNotes

// TAB-113: whatever calls `clearSession()` on the session of the recording in
// progress, the service itself must refuse. Before this, a cleared live
// session retired silently: the editor kept showing the note while every
// subsequent write was dropped, and the stop saved zero notes.
struct NoteServiceLiveSessionTests {

    private func uniqueSessionId() -> String {
        "tab113-test-\(UUID().uuidString)"
    }

    @MainActor
    @Test func clearingTheLiveRecordingSessionIsRefusedAndNotesSurvive() throws {
        let live = uniqueSessionId()
        let previous = NoteService.liveRecordingSessionProvider
        NoteService.liveRecordingSessionProvider = { live }
        defer {
            NoteService.liveRecordingSessionProvider = previous
            NoteService.shared(for: live).clearSession()
        }

        let service = NoteService.shared(for: live)
        service.stagePrimaryNoteText("Always let Faith speak first", timestamp: 300)

        service.clearSession()

        #expect(service.currentNotes.count == 1)
        // Not retired: later keystrokes are still accepted.
        #expect(service.stagePrimaryNoteText("Always let Faith speak first. Unbelief delays.", timestamp: 300))
        #expect(service.currentNotes.first?.text == "Always let Faith speak first. Unbelief delays.")
        // Still the registered instance for the session, not evicted.
        #expect(NoteService.shared(for: live) === service)
    }

    @MainActor
    @Test func clearingASessionThatIsNotLiveStillClears() throws {
        let live = uniqueSessionId()
        let finished = uniqueSessionId()
        let previous = NoteService.liveRecordingSessionProvider
        NoteService.liveRecordingSessionProvider = { live }
        defer { NoteService.liveRecordingSessionProvider = previous }

        let service = NoteService.shared(for: finished)
        service.stagePrimaryNoteText("done recording", timestamp: 10)

        service.clearSession()

        #expect(service.currentNotes.isEmpty)
        #expect(!service.stagePrimaryNoteText("late write", timestamp: 11))
    }

    @MainActor
    @Test func onceTheRecordingStopsTheSessionCanBeCleared() throws {
        let id = uniqueSessionId()
        let previous = NoteService.liveRecordingSessionProvider
        NoteService.liveRecordingSessionProvider = { id }
        defer { NoteService.liveRecordingSessionProvider = previous }

        let service = NoteService.shared(for: id)
        service.stagePrimaryNoteText("mid-sermon", timestamp: 100)
        service.clearSession()
        #expect(service.currentNotes.count == 1)

        NoteService.liveRecordingSessionProvider = { nil }
        service.clearSession()
        #expect(service.currentNotes.isEmpty)
    }
}
