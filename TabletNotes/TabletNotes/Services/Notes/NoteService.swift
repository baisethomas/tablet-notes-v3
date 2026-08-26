import Foundation
import Combine
import SwiftData
import SwiftUI

@MainActor
class NoteService: NoteServiceProtocol, ObservableObject {
    @Published private var notes: [Note] = []
    var notesPublisher: AnyPublisher<[Note], Never> { $notes.eraseToAnyPublisher() }
    var currentNotes: [Note] { notes }
    let sessionId: String
    
    private let userDefaults = UserDefaults.standard
    private let notesKey = "recordingSessionNotes"
    /// One serial queue for ALL instances (TAB-96 round 4): teardown drains
    /// every pending note write in the process, not just this instance's, so
    /// the FIFO ordering guarantee holds even when tests or previews hold
    /// sibling instances of one session.
    private static let persistenceQueue = DispatchQueue(label: "com.tabletnotes.notes.persistence", qos: .utility)
    private var persistenceQueue: DispatchQueue { Self.persistenceQueue }
    /// True once this instance has performed any real mutation. Gates the
    /// empty-array persistence write (TAB-96): only an instance that
    /// deliberately emptied its notes may overwrite a non-empty store.
    private var hasMutatedNotes = false

    private struct PersistedNote: Codable, Sendable {
        let id: UUID
        let text: String
        let timestamp: TimeInterval
        let remoteId: String?
        let updatedAt: Date?
        let needsSync: Bool

        enum CodingKeys: String, CodingKey {
            case id, text, timestamp, remoteId, updatedAt, needsSync
        }

        init(note: Note) {
            id = note.id
            text = note.text
            timestamp = note.timestamp
            remoteId = note.remoteId
            updatedAt = note.updatedAt
            needsSync = note.needsSync
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            text = try container.decode(String.self, forKey: .text)
            timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
            remoteId = try container.decodeIfPresent(String.self, forKey: .remoteId)
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            needsSync = try container.decodeIfPresent(Bool.self, forKey: .needsSync) ?? false
        }

        func makeNote() -> Note {
            Note(
                id: id,
                text: text,
                timestamp: timestamp,
                remoteId: remoteId,
                updatedAt: updatedAt,
                needsSync: needsSync
            )
        }
    }
    
    /// Production code must obtain instances via `NoteService.shared(for:)` —
    /// two live instances on one session id race over the same UserDefaults
    /// key, which is the defect TAB-96 fixed. The initializer stays callable
    /// for tests (which construct competing instances deliberately to prove
    /// the guards) and previews.
    init(sessionId: String = UUID().uuidString) {
        self.sessionId = sessionId
        loadNotesFromPersistence()
    }

    // MARK: - One instance per session (TAB-96)

    /// Every call site used to allocate `NoteService(sessionId:)` inline —
    /// MainAppView did it on every render — so a fleet of instances shared
    /// one UserDefaults key and raced each other (a stale empty one could
    /// clobber the persisted note, and the view then created a duplicate).
    /// The registry hands back the same instance for a session; a session
    /// ends via `clearSession()`, which evicts it. MainActor-isolated with
    /// the class, so no lock is needed and a service can never be created
    /// off the main actor. Growth is bounded by recording sessions per
    /// process launch (one live at a time; an abandoned session holds one
    /// small note array until its id is cleared or the process ends).
    private static var sharedInstances: [String: NoteService] = [:]

    static func shared(for sessionId: String) -> NoteService {
        if let existing = sharedInstances[sessionId] {
            return existing
        }
        let service = NoteService(sessionId: sessionId)
        sharedInstances[sessionId] = service
        return service
    }

    private static func evictShared(sessionId: String) {
        sharedInstances.removeValue(forKey: sessionId)
    }

    /// The recording screen's single-note save: update the primary note in
    /// place — keeping its creation timestamp — or create it when non-blank
    /// text first arrives. The decision reads this service's own state, never
    /// a view-local replica delivered asynchronously, so a repeated save can
    /// not mint a second row (TAB-96).
    ///
    /// The creation timestamp is deliberately immutable: it marks where in
    /// the recording the user STARTED the note, and later saves (including
    /// the post-stop flush) must not move that marker. A genuine timestamp 0
    /// means the user typed at second zero.
    func upsertPrimaryNote(text: String, timestamp: TimeInterval) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = notes.first {
            updateNote(id: existing.id, newText: trimmed.isEmpty ? " " : trimmed)
            return
        }
        guard !trimmed.isEmpty else { return }
        addNote(text: trimmed, timestamp: timestamp)
    }
    
    private func loadNotesFromPersistence() {
        let key = "\(notesKey)_\(sessionId)"
        if let data = userDefaults.data(forKey: key),
           let decodedNotes = try? JSONDecoder().decode([PersistedNote].self, from: data) {
            notes = decodedNotes.map { $0.makeNote() }
        }
    }
    
    private func saveNotesToPersistence(synchronously: Bool = false) {
        // An instance that never mutated anything has nothing to persist:
        // its array is at best identical to the store and at worst a stale
        // copy of it — writing either back can only erase newer data (an
        // empty stale write is how Sunday's duplicate note was born, TAB-96;
        // round 4 generalized the guard to stale NON-empty writes too).
        guard hasMutatedNotes else { return }

        let key = "\(notesKey)_\(sessionId)"
        let snapshots = notes.map(PersistedNote.init)

        // UserDefaults is documented thread-safe; resolving .standard inside
        // the @Sendable closure avoids capturing the non-Sendable property.
        let write: @Sendable () -> Void = {
            if let data = try? JSONEncoder().encode(snapshots) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }

        if synchronously {
            persistenceQueue.sync(execute: write)
        } else {
            persistenceQueue.async(execute: write)
        }
    }

    /// Blocks until the current in-memory notes are written to UserDefaults.
    /// Use before leaving the recording screen or stopping from the mini-player
    /// so a fresh NoteService(sessionId:) sees the latest text.
    func flushPersistedNotes() {
        saveNotesToPersistence(synchronously: true)
    }

    func addNote(text: String, timestamp: TimeInterval) {
        hasMutatedNotes = true
        let note = Note(text: text, timestamp: timestamp)
        notes.append(note)
        saveNotesToPersistence()
        print("[NoteService] Added note id=\(note.id), characters=\(text.count), timestamp=\(timestamp), total=\(notes.count)")
    }

    func updateNote(id: UUID, newText: String) {
        if let idx = notes.firstIndex(where: { $0.id == id }) {
            hasMutatedNotes = true
            notes[idx].text = newText
            notes = notes
            saveNotesToPersistence()
            print("[NoteService] Updated note id=\(id), characters=\(newText.count), total=\(notes.count)")
        } else {
            print("[NoteService] WARNING: Could not find note with id: \(id) to update")
        }
    }

    func deleteNote(id: UUID) {
        // Only an applied deletion counts as a mutation — a miss on a stale
        // instance must not license it to overwrite the store (TAB-96).
        guard notes.contains(where: { $0.id == id }) else { return }
        hasMutatedNotes = true
        notes.removeAll { $0.id == id }
        saveNotesToPersistence()
    }
    
    func clearSession() {
        let key = "\(notesKey)_\(sessionId)"
        print("[NoteService] Clearing session with key: \(key). Had \(notes.count) notes before clearing")
        notes.removeAll()
        // Synchronous on the serial persistence queue: FIFO drains any queued
        // write first (no resurrection), and the removal completes before the
        // eviction below — so a same-session `shared(for:)` reacquired right
        // after this call can never load the just-cleared notes (round 3).
        // Bounded cost: at most one pending single-note encode sits ahead.
        persistenceQueue.sync {
            UserDefaults.standard.removeObject(forKey: key)
        }
        Self.evictShared(sessionId: sessionId)
        print("[NoteService] Session cleared. Notes count now: \(notes.count)")
    }
}
