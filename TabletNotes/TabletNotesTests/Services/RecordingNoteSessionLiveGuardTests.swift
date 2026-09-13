import Foundation
import Testing
@testable import TabletNotes

// TAB-113 round 2 (Ternary): NoteService.clearSession() refuses to retire the
// live recording's session, but RecordingNoteSession.finish used to treat the
// clear as fire-and-forget and rotate to a fresh id anyway. The notes would
// stay in the old service while noteSession.sessionId pointed at an empty one
// — orphaning the live recording's notes, which is the very loss being fixed.
// finish must honour the service's answer.
struct RecordingNoteSessionLiveGuardTests {

    @MainActor
    @Test func finishDoesNotRotateWhenTheServiceRefusesToClearTheLiveSession() throws {
        let session = RecordingNoteSession()
        let live = session.begin()
        let previous = NoteService.liveRecordingSessionProvider
        NoteService.liveRecordingSessionProvider = { live }
        defer {
            NoteService.liveRecordingSessionProvider = previous
            NoteService.shared(for: live).clearSession()
        }
        NoteService.shared(for: live).stagePrimaryNoteText("still recording", timestamp: 120)

        // A stale caller claims the recording stopped; the recording service
        // (via the provider) says otherwise.
        let outcome = session.finish(live, isRecordingLive: false)

        #expect(outcome == .refusedLiveRecording)
        #expect(session.sessionId == live)
        #expect(NoteService.shared(for: live).currentNotes.first?.text == "still recording")
    }

    @MainActor
    @Test func finishOfASupersededIdThatIsStillTheLiveRecordingIsRefused() throws {
        let session = RecordingNoteSession()
        let live = session.begin()
        let newer = session.begin() // view-level id moved on; the audio didn't
        let previous = NoteService.liveRecordingSessionProvider
        NoteService.liveRecordingSessionProvider = { live }
        defer {
            NoteService.liveRecordingSessionProvider = previous
            NoteService.shared(for: live).clearSession()
            NoteService.shared(for: newer).clearSession()
        }
        NoteService.shared(for: live).stagePrimaryNoteText("bound to the audio", timestamp: 40)

        let outcome = session.finish(live, isRecordingLive: false)

        #expect(outcome == .refusedLiveRecording)
        #expect(session.sessionId == newer)
        #expect(NoteService.shared(for: live).currentNotes.count == 1)
    }

    @MainActor
    @Test func finishClearsAndRotatesOnceTheRecordingIsNoLongerLive() throws {
        let session = RecordingNoteSession()
        let id = session.begin()
        let previous = NoteService.liveRecordingSessionProvider
        NoteService.liveRecordingSessionProvider = { nil }
        defer { NoteService.liveRecordingSessionProvider = previous }
        NoteService.shared(for: id).stagePrimaryNoteText("done", timestamp: 5)

        let outcome = session.finish(id, isRecordingLive: false)

        #expect(outcome == .clearedAndRotated)
        #expect(session.sessionId != id)
        #expect(NoteService.shared(for: id).currentNotes.isEmpty)
    }
}
