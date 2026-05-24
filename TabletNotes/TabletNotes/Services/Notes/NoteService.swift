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
    
    private func loadNotesFromPersistence() {
        let key = "\(notesKey)_\(sessionId)"
        if let data = userDefaults.data(forKey: key),
           let decodedNotes = try? JSONDecoder().decode([PersistedNote].self, from: data) {
            notes = decodedNotes.map { $0.makeNote() }
        }
    }
    
    private func saveNotesToPersistence() {
        let key = "\(notesKey)_\(sessionId)"
        let snapshots = notes.map(PersistedNote.init)

        persistenceQueue.async { [userDefaults] in
            if let data = try? JSONEncoder().encode(snapshots) {
                userDefaults.set(data, forKey: key)
            }
        }
    }

    func addNote(text: String, timestamp: TimeInterval) {
        let note = Note(text: text, timestamp: timestamp)
        notes.append(note)
        saveNotesToPersistence()
        print("[NoteService] Added note id=\(note.id), characters=\(text.count), timestamp=\(timestamp), total=\(notes.count)")
    }

    func updateNote(id: UUID, newText: String) {
        if let idx = notes.firstIndex(where: { $0.id == id }) {
            notes[idx].text = newText
            notes = notes
            saveNotesToPersistence()
            print("[NoteService] Updated note id=\(id), characters=\(newText.count), total=\(notes.count)")
        } else {
            print("[NoteService] WARNING: Could not find note with id: \(id) to update")
        }
    }

    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        saveNotesToPersistence()
    }
    
    func clearSession() {
        let key = "\(notesKey)_\(sessionId)"
        print("[NoteService] Clearing session with key: \(key). Had \(notes.count) notes before clearing")
        notes.removeAll()
        persistenceQueue.async { [userDefaults] in
            userDefaults.removeObject(forKey: key)
        }
        print("[NoteService] Session cleared. Notes count now: \(notes.count)")
    }
}
