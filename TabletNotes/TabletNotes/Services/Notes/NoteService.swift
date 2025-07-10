import Foundation
import Combine
import SwiftData
import SwiftUI

class NoteService: NoteServiceProtocol, ObservableObject {
    @Published private var notes: [Note] = []
    var notesPublisher: AnyPublisher<[Note], Never> { $notes.eraseToAnyPublisher() }
    var currentNotes: [Note] { notes }
    
    private let userDefaults = UserDefaults.standard
    private let notesKey = "recordingSessionNotes"
    private let sessionId: String
    
    init(sessionId: String = UUID().uuidString) {
        self.sessionId = sessionId
        loadNotesFromPersistence()
    }
    
    private func loadNotesFromPersistence() {
        let key = "\(notesKey)_\(sessionId)"
        if let data = userDefaults.data(forKey: key),
           let decodedNotes = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decodedNotes
        }
    }
    
    private func saveNotesToPersistence() {
        let key = "\(notesKey)_\(sessionId)"
        if let data = try? JSONEncoder().encode(notes) {
            userDefaults.set(data, forKey: key)
        }
    }

    func addNote(text: String, timestamp: TimeInterval) {
        let note = Note(text: text, timestamp: timestamp)
        notes.append(note)
        saveNotesToPersistence()
    }

    func updateNote(id: UUID, newText: String) {
        if let idx = notes.firstIndex(where: { $0.id == id }) {
            notes[idx].text = newText
            saveNotesToPersistence()
        }
    }

    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        saveNotesToPersistence()
    }
    
    func clearSession() {
        let key = "\(notesKey)_\(sessionId)"
        userDefaults.removeObject(forKey: key)
        notes.removeAll()
    }
}
