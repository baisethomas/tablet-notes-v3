import Foundation
import Testing
@testable import TabletNotes

/// Regression tests for TAB-109: a note written during a recording vanished
/// after leaving to Home and returning via the mini-player. The recording
/// screen's text now mirrors into the session's NoteService on every
/// keystroke, and a save completion can only ever end the session it saved —
/// never the session of a newer recording that is still live.
struct RecordingNoteSessionTests {

    private func uniqueSessionId() -> String {
        "tab109-test-\(UUID().uuidString)"
    }

    // MARK: - Keystroke staging (RecordingView → NoteService)

    /// Every keystroke reaches the service immediately, before any debounce
    /// or persistence runs — so the service, which outlives the screen, holds
    /// the latest text the moment the user leaves.
    @MainActor
    @Test func stagedTextIsVisibleToTheServiceBeforeItIsPersisted() throws {
        let sessionId = uniqueSessionId()
        let service = NoteService(sessionId: sessionId)
        defer { service.clearSession() }

        #expect(service.stagePrimaryNoteText("Grace is", timestamp: 12))
        #expect(service.currentNotes.count == 1)
        #expect(service.currentNotes.first?.text == "Grace is")
        #expect(service.currentNotes.first?.timestamp == 12)

        #expect(service.stagePrimaryNoteText("Grace is sufficient", timestamp: 15))
        #expect(service.currentNotes.count == 1)
        #expect(service.currentNotes.first?.text == "Grace is sufficient")
        // The creation timestamp marks where the note STARTED; later text keeps it.
        #expect(service.currentNotes.first?.timestamp == 12)

        // Not persisted yet: a fresh instance sees an empty store...
        #expect(NoteService(sessionId: sessionId).currentNotes.isEmpty)
        // ...until the debounced/disappear flush runs.
        service.flushPersistedNotes()
        #expect(NoteService(sessionId: sessionId).currentNotes.first?.text == "Grace is sufficient")
    }

    @MainActor
    @Test func stagingUnchangedOrBlankTextIsANoOp() throws {
        let sessionId = uniqueSessionId()
        let service = NoteService(sessionId: sessionId)
        defer { service.clearSession() }

        #expect(!service.stagePrimaryNoteText("   ", timestamp: 3))
        #expect(service.currentNotes.isEmpty)

        #expect(service.stagePrimaryNoteText("abc", timestamp: 3))
        #expect(!service.stagePrimaryNoteText("abc", timestamp: 9))
        #expect(service.currentNotes.count == 1)
    }

    @MainActor
    @Test func stagingIntoARetiredSessionIsRefused() throws {
        let sessionId = uniqueSessionId()
        let service = NoteService(sessionId: sessionId)
        service.clearSession()

        #expect(!service.stagePrimaryNoteText("too late", timestamp: 1))
        #expect(service.currentNotes.isEmpty)
    }

    // MARK: - Session lifecycle (MainAppView → RecordingNoteSession)

    /// The exact TAB-109 hazard: recording A's save completes AFTER recording
    /// B has started and the user is writing B's note. Ending A must clear A
    /// only — B's notes and B's session id stay intact.
    @MainActor
    @Test func finishingASupersededSessionLeavesTheLiveRecordingUntouched() throws {
        let session = RecordingNoteSession(sessionId: uniqueSessionId())
        let a = session.begin()
        NoteService.shared(for: a).stagePrimaryNoteText("note for A", timestamp: 5)

        let b = session.begin()
        defer { NoteService.shared(for: b).clearSession() }
        #expect(b != a)
        NoteService.shared(for: b).stagePrimaryNoteText("note for B, still typing", timestamp: 40)

        let outcome = session.finish(a, isRecordingLive: true)

        #expect(outcome == .clearedStale)
        #expect(session.sessionId == b)
        #expect(NoteService.shared(for: a).currentNotes.isEmpty)
        #expect(NoteService.shared(for: b).currentNotes.first?.text == "note for B, still typing")
    }

    /// Belt and braces: nothing may clear the session of the recording that
    /// is live right now, whatever handler asks.
    @MainActor
    @Test func finishingTheLiveSessionWhileRecordingIsRefused() throws {
        let session = RecordingNoteSession(sessionId: uniqueSessionId())
        let live = session.begin()
        defer { NoteService.shared(for: live).clearSession() }
        NoteService.shared(for: live).stagePrimaryNoteText("mid-sermon thought", timestamp: 300)

        let outcome = session.finish(live, isRecordingLive: true)

        #expect(outcome == .refusedLiveRecording)
        #expect(session.sessionId == live)
        #expect(NoteService.shared(for: live).currentNotes.first?.text == "mid-sermon thought")
    }

    /// The normal path: the recording stopped, its sermon saved — the session
    /// is cleared and a fresh id is minted so the next recording starts empty.
    @MainActor
    @Test func finishingTheCurrentSessionAfterStopClearsAndRotates() throws {
        let session = RecordingNoteSession(sessionId: uniqueSessionId())
        let finished = session.begin()
        NoteService.shared(for: finished).stagePrimaryNoteText("done", timestamp: 90)

        let outcome = session.finish(finished, isRecordingLive: false)

        #expect(outcome == .clearedAndRotated)
        #expect(session.sessionId != finished)
        #expect(NoteService.shared(for: finished).currentNotes.isEmpty)
        #expect(session.noteService.currentNotes.isEmpty)
        #expect(session.noteService.sessionId == session.sessionId)
    }

    /// Starting a recording always mints a new session, so a recording whose
    /// save failed (session kept for retry) can't leak its notes into the next
    /// recording, and the retry can't later clear the next recording's notes.
    @MainActor
    @Test func beginningARecordingNeverReusesAPendingSession() throws {
        let session = RecordingNoteSession(sessionId: uniqueSessionId())
        let failedSave = session.begin()
        defer { NoteService.shared(for: failedSave).clearSession() }
        NoteService.shared(for: failedSave).stagePrimaryNoteText("notes of the failed save", timestamp: 20)

        let next = session.begin()
        defer { NoteService.shared(for: next).clearSession() }

        #expect(next != failedSave)
        #expect(session.noteService.currentNotes.isEmpty)
        #expect(NoteService.shared(for: failedSave).currentNotes.first?.text == "notes of the failed save")
    }
}
