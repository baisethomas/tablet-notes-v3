import Foundation
import Combine

@MainActor
protocol NoteServiceProtocol {
    var notesPublisher: AnyPublisher<[Note], Never> { get }
    func addNote(text: String, timestamp: TimeInterval)
    func upsertPrimaryNote(text: String, timestamp: TimeInterval)
    func updateNote(id: UUID, newText: String)
    func deleteNote(id: UUID)
    /// `false` when refused because the session is the live recording (TAB-113).
    @discardableResult
    func clearSession() -> Bool
} 
