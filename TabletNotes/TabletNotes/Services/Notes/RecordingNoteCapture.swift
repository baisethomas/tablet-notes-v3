import Foundation

/// Decides which notes a stopped recording is saved with (TAB-113).
///
/// The recording screen holds the note text in its own `@State` and mirrors
/// it into the session's `NoteService`. Those two can disagree: a retired
/// session refuses writes silently, so the editor can show a full note while
/// the service holds none — which is exactly how the 9/6 and 9/13 sermons
/// were saved with zero notes. The rule here is that text the user can see
/// at the moment they stop is never dropped.
enum RecordingNoteCapture {
    /// - Parameters:
    ///   - serviceNotes: what the session's `NoteService` currently holds.
    ///   - editorText: the recording screen's live text.
    ///   - fallbackTimestamp: recording offset to stamp a rebuilt note with
    ///     when the service lost the original (the note's first keystroke if
    ///     known, else the stop time).
    /// - Returns: the service's notes with the primary note's text reconciled
    ///   to the editor (the editor is what the user sees, so it wins; the
    ///   note keeps its identity and start timestamp); a single note rebuilt
    ///   from the editor when the service has none; the service's notes
    ///   untouched when the editor is blank; nothing when both are empty.
    static func notesForSave(
        serviceNotes: [Note],
        editorText: String,
        fallbackTimestamp: TimeInterval
    ) -> [Note] {
        let trimmed = editorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let primary = serviceNotes.first else {
            guard !trimmed.isEmpty else { return [] }
            NotesLog.logger.error("Stop: service returned no notes but the editor holds \(trimmed.count) characters — rebuilding the note from the editor (TAB-113)")
            return [Note(text: trimmed, timestamp: fallbackTimestamp)]
        }
        // A blank editor is either a deliberate delete (already staged as a
        // single space) or a stale view; neither may erase held content.
        guard !trimmed.isEmpty, primary.text != trimmed else { return serviceNotes }
        // Round 3: a service holding an older draft (e.g. retired after the
        // first save, refusing later keystrokes) is not authoritative over
        // the text on screen.
        NotesLog.logger.error("Stop: service primary note (\(primary.text.count) chars) is behind the editor (\(trimmed.count) chars) — saving the editor text (TAB-113)")
        primary.text = trimmed
        return serviceNotes
    }
}
