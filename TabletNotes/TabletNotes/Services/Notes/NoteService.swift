import Foundation
import Combine
import SwiftData
import SwiftUI

class NoteService: NoteServiceProtocol, ObservableObject {
    @Published private var notes: [Note] = []
    var notesPublisher: AnyPublisher<[Note], Never> { $notes.eraseToAnyPublisher() }
    var currentNotes: [Note] { notes }
    let sessionId: String
    
    private let userDefaults = UserDefaults.standard
    private let notesKey = "recordingSessionNotes"
    private let persistenceQueue = DispatchQueue(label: "com.tabletnotes.notes.persistence", qos: .utility)
    /// True once this instance has performed any real mutation. Gates the
    /// empty-array persistence write (TAB-96): only an instance that
    /// deliberately emptied its notes may overwrite a non-empty store.
    private var hasMutatedNotes = false

    private struct PersistedNote: Codable {
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
    /// ends via `clearSession()`, which evicts it.
    private static let sharedLock = NSLock()
    private static var sharedInstances: [String: NoteService] = [:]

    static func shared(for sessionId: String) -> NoteService {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        if let existing = sharedInstances[sessionId] {
            return existing
        }
        let service = NoteService(sessionId: sessionId)
        sharedInstances[sessionId] = service
        return service
    }

    private static func evictShared(sessionId: String) {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        sharedInstances.removeValue(forKey: sessionId)
    }

    /// The recording screen's single-note save: update the primary note in
    /// place — keeping its creation timestamp — or create it when non-blank
    /// text first arrives. The decision reads this service's own state, never
    /// a view-local replica delivered asynchronously, so a repeated save can
    /// not mint a second row (TAB-96).
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
        let key = "\(notesKey)_\(sessionId)"
        let snapshots = notes.map(PersistedNote.init)
        let deliberatelyEmptied = hasMutatedNotes

        let write = { [userDefaults] in
            // An instance that never mutated anything must not erase a
            // sibling's persisted work with its empty array — that wipe is
            // how Sunday's duplicate note was born (TAB-96). A deliberate
            // deletion sets hasMutatedNotes and still persists the empty.
            if snapshots.isEmpty, !deliberatelyEmptied, userDefaults.data(forKey: key) != nil {
                print("[NoteService] Skipping empty flush over a non-empty store for session key \(key)")
                return
            }
            if let data = try? JSONEncoder().encode(snapshots) {
                userDefaults.set(data, forKey: key)
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
        hasMutatedNotes = true
        notes.removeAll { $0.id == id }
        saveNotesToPersistence()
    }
    
    func clearSession() {
        let key = "\(notesKey)_\(sessionId)"
        print("[NoteService] Clearing session with key: \(key). Had \(notes.count) notes before clearing")
        notes.removeAll()
        persistenceQueue.sync { [userDefaults] in
            userDefaults.removeObject(forKey: key)
        }
        Self.evictShared(sessionId: sessionId)
        print("[NoteService] Session cleared. Notes count now: \(notes.count)")
    }
}
