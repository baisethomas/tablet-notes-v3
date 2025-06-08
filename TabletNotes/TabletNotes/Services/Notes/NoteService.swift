import Foundation
import Combine
import SwiftData
import SwiftUI

class NoteService: NoteServiceProtocol, ObservableObject {
    @Published private var notes: [Note] = []
    var notesPublisher: AnyPublisher<[Note], Never> { $notes.eraseToAnyPublisher() }
    var currentNotes: [Note] { notes }

    func addNote(text: String, timestamp: TimeInterval) {
        let note = Note(text: text, timestamp: timestamp)
        notes.append(note)
    }

    func updateNote(id: UUID, newText: String) {
        if let idx = notes.firstIndex(where: { $0.id == id }) {
            notes[idx].text = newText
        }
    }

    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
    }
}
