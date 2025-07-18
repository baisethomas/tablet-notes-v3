import Foundation
import Combine

protocol NoteServiceProtocol {
    var notesPublisher: AnyPublisher<[Note], Never> { get }
    func addNote(text: String, timestamp: TimeInterval)
    func updateNote(id: UUID, newText: String)
    func deleteNote(id: UUID)
    func clearSession()
} 
