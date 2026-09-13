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
    /// - Returns: the service's notes when it has any; otherwise a single
    ///   note rebuilt from the editor text, or nothing when both are empty.
    static func notesForSave(
        serviceNotes: [Note],
        editorText: String,
        fallbackTimestamp: TimeInterval
    ) -> [Note] {
        if !serviceNotes.isEmpty {
            return serviceNotes
        }
        let trimmed = editorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        NotesLog.logger.error("Stop: service returned no notes but the editor holds \(trimmed.count) characters — rebuilding the note from the editor (TAB-113)")
        return [Note(text: trimmed, timestamp: fallbackTimestamp)]
    }
}
