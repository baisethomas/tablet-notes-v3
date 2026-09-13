import Foundation
import Testing
@testable import TabletNotes

// TAB-113: a real-length sermon's note, visible in the editor the whole time,
// reached the save as an empty list because the note service had been retired
// underneath the recording screen and silently refused every write. The stop
// path must never drop text the user can see: when the service comes back
// empty while the editor has text, the editor text IS the note.
struct RecordingNoteCaptureTests {

    @Test func serviceNotesPassThroughWhenTheyMatchTheEditor() {
        let fromService = [Note(text: "Faith speaks first", timestamp: 812)]
        let notes = RecordingNoteCapture.notesForSave(
            serviceNotes: fromService,
            editorText: "Faith speaks first",
            fallbackTimestamp: 2000
        )
        #expect(notes.count == 1)
        #expect(notes.first?.timestamp == 812)
        #expect(notes.first === fromService.first)
    }

    /// Round 3 (Ternary): a service holding an OLDER draft is not authoritative
    /// over what the user can see. The primary note takes the editor's text,
    /// keeping its identity and its original start timestamp.
    @Test func staleServiceDraftIsReplacedByTheVisibleEditorText() {
        let primary = Note(text: "first draft", timestamp: 812)
        let second = Note(text: "a separate note", timestamp: 1500)
        let notes = RecordingNoteCapture.notesForSave(
            serviceNotes: [primary, second],
            editorText: "first draft with later edits\n\n📖 Exodus 33:13",
            fallbackTimestamp: 2000
        )
        #expect(notes.count == 2)
        #expect(notes.first === primary)
        #expect(notes.first?.text == "first draft with later edits\n\n📖 Exodus 33:13")
        #expect(notes.first?.timestamp == 812)
        #expect(notes.last === second)
        #expect(notes.last?.text == "a separate note")
    }

    /// An empty editor never erases a note the service still holds: the
    /// editor going blank is a legitimate "delete", which the service records
    /// as a single space, and a stale-empty editor must not win over content.
    @Test func blankEditorLeavesServiceNotesUntouched() {
        let primary = Note(text: "kept", timestamp: 10)
        let notes = RecordingNoteCapture.notesForSave(
            serviceNotes: [primary],
            editorText: "   ",
            fallbackTimestamp: 99
        )
        #expect(notes.count == 1)
        #expect(notes.first?.text == "kept")
    }

    /// The 9/13 case: retired service → no notes; editor still shows the text.
    @Test func emptyServiceWithVisibleTextBuildsTheNoteFromTheEditor() {
        let text = "Prophetic words always require a response\n\n📖 Exodus 33:13\n\n13 Now therefore, I pray thee…"
        let notes = RecordingNoteCapture.notesForSave(
            serviceNotes: [],
            editorText: text,
            fallbackTimestamp: 1530
        )
        #expect(notes.count == 1)
        #expect(notes.first?.text == text)
        #expect(notes.first?.timestamp == 1530)
    }

    @Test func emptyServiceAndBlankEditorSavesNothing() {
        #expect(RecordingNoteCapture.notesForSave(serviceNotes: [], editorText: "", fallbackTimestamp: 10).isEmpty)
        #expect(RecordingNoteCapture.notesForSave(serviceNotes: [], editorText: "  \n\t ", fallbackTimestamp: 10).isEmpty)
    }

    @Test func fallbackNoteIsTrimmedButOtherwiseVerbatim() {
        let notes = RecordingNoteCapture.notesForSave(
            serviceNotes: [],
            editorText: "\n  keep the inner   spacing  \n",
            fallbackTimestamp: 5
        )
        #expect(notes.first?.text == "keep the inner   spacing")
    }
}
