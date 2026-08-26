import Foundation
import Testing
@testable import TabletNotes

/// Regression tests for TAB-96: Sunday's sermon uploaded with two identical
/// notes (timestamps 3405 and 0). Root cause was a family of defects around
/// NoteService: a fresh instance was allocated on every MainAppView render,
/// all sharing one UserDefaults key; a stale empty instance could clobber the
/// persisted array; the view decided create-vs-update from an async replica;
/// and the post-stop save ran after the recording duration was zeroed.
struct NoteServiceRegressionTests {

    private func uniqueSessionId() -> String {
        "tab96-test-\(UUID().uuidString)"
    }

    /// The clobber at the heart of the duplicate: an instance that never held
    /// notes flushes an empty array over a sibling's persisted note, so every
    /// later instance loads empty and the final save creates a second note.
    /// An empty flush from an instance that never mutated anything must not
    /// erase a non-empty store.
    @MainActor
    @Test func staleEmptyInstanceFlushMustNotClobberPersistedNotes() throws {
        let sessionId = uniqueSessionId()
        let writer = NoteService(sessionId: sessionId)
        let staleEmpty = NoteService(sessionId: sessionId) // created while store empty
        defer { writer.clearSession() }

        writer.addNote(text: "D.O.G = devoted of God", timestamp: 3405)
        writer.flushPersistedNotes()

        // The stale instance never held a note; its flush must be a no-op.
        staleEmpty.flushPersistedNotes()

        let reloaded = NoteService(sessionId: sessionId)
        #expect(reloaded.currentNotes.count == 1)
        #expect(reloaded.currentNotes.first?.text == "D.O.G = devoted of God")
        #expect(reloaded.currentNotes.first?.timestamp == 3405)
    }

    /// Review round 4: the stale-write protection covers NON-empty arrays
    /// too. A sibling that loaded an older snapshot and never mutated it must
    /// not write that stale copy back over newer data.
    @MainActor
    @Test func staleNonEmptyInstanceFlushMustNotOverwriteNewerStore() throws {
        let sessionId = uniqueSessionId()
        let writer = NoteService(sessionId: sessionId)
        defer { writer.clearSession() }

        writer.addNote(text: "v1", timestamp: 100)
        writer.flushPersistedNotes()

        let staleReader = NoteService(sessionId: sessionId) // loads "v1", never mutates
        if let note = writer.currentNotes.first {
            writer.updateNote(id: note.id, newText: "v2 — newer")
        }
        writer.flushPersistedNotes()

        staleReader.flushPersistedNotes() // must not write "v1" back

        let reloaded = NoteService(sessionId: sessionId)
        #expect(reloaded.currentNotes.first?.text == "v2 — newer")
    }

    /// Deliberate emptying still persists: deleting the last note is a real
    /// mutation and the empty array must overwrite the store.
    @MainActor
    @Test func deletingLastNoteStillPersistsEmptyStore() throws {
        let sessionId = uniqueSessionId()
        let service = NoteService(sessionId: sessionId)
        defer { service.clearSession() }

        service.addNote(text: "Temporary", timestamp: 10)
        service.flushPersistedNotes()
        if let note = service.currentNotes.first {
            service.deleteNote(id: note.id)
        }
        service.flushPersistedNotes()

        let reloaded = NoteService(sessionId: sessionId)
        #expect(reloaded.currentNotes.isEmpty)
    }

    /// One NoteService per recording session: every call site that used to
    /// allocate `NoteService(sessionId:)` inline gets the same instance back,
    /// so there is no fleet of siblings racing over one UserDefaults key.
    @MainActor
    @Test func sharedFactoryReturnsOneInstancePerSession() throws {
        let sessionId = uniqueSessionId()
        let first = NoteService.shared(for: sessionId)
        defer { first.clearSession() }

        let second = NoteService.shared(for: sessionId)
        #expect(first === second)

        let otherSession = NoteService.shared(for: uniqueSessionId())
        #expect(first !== otherSession)
        otherSession.clearSession()
    }

    /// clearSession retires the shared instance: the next recording session
    /// starts from a fresh service, not a cached one holding old notes.
    @MainActor
    @Test func clearSessionEvictsSharedInstance() throws {
        let sessionId = uniqueSessionId()
        let first = NoteService.shared(for: sessionId)
        first.addNote(text: "Old session note", timestamp: 5)
        first.clearSession()

        // No flush in between: teardown must be complete when clearSession
        // returns (review round 3) — an immediate same-session reacquisition
        // gets a fresh, empty service.
        let second = NoteService.shared(for: sessionId)
        defer { second.clearSession() }
        #expect(first !== second)
        #expect(second.currentNotes.isEmpty)
    }

    /// Review round 3: teardown and reacquisition are one ordered lifecycle.
    /// A write races clearSession (queued just before it); the immediate
    /// reacquisition must still see an empty store — the just-cleared notes
    /// can neither survive nor resurrect.
    @MainActor
    @Test func immediateReacquisitionAfterClearSessionSeesEmptyStore() throws {
        let sessionId = uniqueSessionId()
        let first = NoteService.shared(for: sessionId)
        first.addNote(text: "About to be cleared", timestamp: 42) // enqueues an async write
        first.clearSession()

        let second = NoteService.shared(for: sessionId)
        defer { second.clearSession() }
        #expect(second.currentNotes.isEmpty)

        // And nothing resurrects afterwards: a later fresh load stays empty.
        second.flushPersistedNotes()
        let third = NoteService(sessionId: sessionId)
        #expect(third.currentNotes.isEmpty)
    }

    /// Review round 5: holders of an evicted instance (the recording view, a
    /// delayed save task) may still call into it after clearSession. A
    /// retired instance accepts no mutations and writes nothing — a cleared
    /// session can never be repopulated.
    @MainActor
    @Test func retiredInstanceCannotRepopulateClearedSession() throws {
        let sessionId = uniqueSessionId()
        let old = NoteService.shared(for: sessionId)
        old.upsertPrimaryNote(text: "Live note", timestamp: 10)
        old.clearSession()

        // A stale view/task fires a save against the retained old instance.
        old.upsertPrimaryNote(text: "Zombie write", timestamp: 20)
        old.flushPersistedNotes()

        let fresh = NoteService.shared(for: sessionId)
        defer { fresh.clearSession() }
        #expect(old.currentNotes.isEmpty)
        #expect(fresh.currentNotes.isEmpty)
        #expect(fresh !== old)
    }

    /// The single-note UI's save decision lives in the service now, not in a
    /// view-local replica: repeated saves update the one note in place —
    /// keeping its original timestamp — and never mint a second row.
    @MainActor
    @Test func upsertPrimaryNoteNeverCreatesASecondNote() throws {
        let sessionId = uniqueSessionId()
        let service = NoteService(sessionId: sessionId)
        defer { service.clearSession() }

        service.upsertPrimaryNote(text: "First draft", timestamp: 120)
        service.upsertPrimaryNote(text: "Longer final text", timestamp: 3405)
        // The post-stop flush arrives after the duration was reset to 0 —
        // the exact write that used to create the timestamp-0 duplicate.
        service.upsertPrimaryNote(text: "Longer final text", timestamp: 0)

        #expect(service.currentNotes.count == 1)
        #expect(service.currentNotes.first?.text == "Longer final text")
        #expect(service.currentNotes.first?.timestamp == 120) // creation timestamp kept
    }

    /// Blank text creates nothing (matches the old view behavior: creation
    /// only ever happened for non-empty text); once a note exists, a blank
    /// save keeps the note with placeholder text rather than deleting it.
    @MainActor
    @Test func upsertPrimaryNoteIgnoresBlankTextWhenNoNoteExists() throws {
        let sessionId = uniqueSessionId()
        let service = NoteService(sessionId: sessionId)
        defer { service.clearSession() }

        service.upsertPrimaryNote(text: "   ", timestamp: 10)
        #expect(service.currentNotes.isEmpty)

        service.upsertPrimaryNote(text: "Real note", timestamp: 20)
        service.upsertPrimaryNote(text: "", timestamp: 30)
        #expect(service.currentNotes.count == 1)
        #expect(service.currentNotes.first?.text == " ")
    }

    /// Cross-instance continuation stays intact: a fresh instance for the
    /// same session (e.g. stop-from-mini-player) loads the persisted note and
    /// updates it rather than duplicating it.
    @MainActor
    @Test func freshInstanceUpsertsPersistedNoteInsteadOfDuplicating() throws {
        let sessionId = uniqueSessionId()
        let first = NoteService(sessionId: sessionId)
        first.upsertPrimaryNote(text: "Typed during recording", timestamp: 900)
        first.flushPersistedNotes()

        let second = NoteService(sessionId: sessionId)
        defer { second.clearSession() }
        second.upsertPrimaryNote(text: "Typed during recording, extended", timestamp: 0)

        #expect(second.currentNotes.count == 1)
        #expect(second.currentNotes.first?.text == "Typed during recording, extended")
        #expect(second.currentNotes.first?.timestamp == 900)
    }
}
