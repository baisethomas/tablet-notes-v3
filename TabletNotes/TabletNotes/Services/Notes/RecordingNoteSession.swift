import Foundation
import Observation

/// Owns the note-session id for the recording in progress and the rule for
/// ending one (TAB-109).
///
/// A recording's notes live in `NoteService.shared(for: sessionId)`. Before
/// this type, MainAppView kept the id in a bare `@State` string and every
/// save-completion handler read *whatever id was current when it fired* and
/// cleared that session. That is correct only while completions arrive in
/// order; a late completion (a retried save, a slow save, an auto-stop
/// racing a manual stop) would clear — and re-key — the session of a newer
/// recording, erasing notes the user was still writing. Here the id to finish
/// is captured when the save starts, and finishing is refused outright for
/// the session that is still recording.
@MainActor
@Observable
final class RecordingNoteSession {
    enum FinishOutcome: Equatable {
        /// The finished session was the current one and the recording had
        /// stopped: its notes were cleared and a fresh id was minted.
        case clearedAndRotated
        /// The finished session had already been superseded by a newer
        /// recording: only the old session was cleared; the live one is untouched.
        case clearedStale
        /// The finished session is the one still recording. Nothing was cleared.
        case refusedLiveRecording
    }

    private(set) var sessionId: String

    init(sessionId: String = UUID().uuidString) {
        self.sessionId = sessionId
    }

    /// The note service for the recording in progress.
    var noteService: NoteService {
        NoteService.shared(for: sessionId)
    }

    /// Mints a fresh session for a recording that is about to start, so a
    /// new recording can never inherit (or later be cleared as) the notes of
    /// a previous one whose save is still pending or failed.
    @discardableResult
    func begin() -> String {
        let previous = sessionId
        sessionId = UUID().uuidString
        print("[RecordingNoteSession] Began session \(sessionId) (previous \(previous))")
        return sessionId
    }

    /// Ends `finishedSessionId` after its recording was durably saved.
    ///
    /// - Parameter isRecordingLive: whether a recording is in progress right
    ///   now. If it is and `finishedSessionId` is the current session, the
    ///   caller is trying to clear the notes of the recording the user is in
    ///   the middle of — refused.
    @discardableResult
    func finish(_ finishedSessionId: String, isRecordingLive: Bool) -> FinishOutcome {
        if finishedSessionId != sessionId {
            NoteService.shared(for: finishedSessionId).clearSession()
            print("[RecordingNoteSession] Cleared superseded session \(finishedSessionId); live session \(sessionId) untouched")
            return .clearedStale
        }
        if isRecordingLive {
            print("[RecordingNoteSession] REFUSED to clear session \(sessionId): its recording is still live")
            return .refusedLiveRecording
        }
        NoteService.shared(for: sessionId).clearSession()
        let previous = sessionId
        sessionId = UUID().uuidString
        print("[RecordingNoteSession] Finished session \(previous); next session \(sessionId)")
        return .clearedAndRotated
    }
}
