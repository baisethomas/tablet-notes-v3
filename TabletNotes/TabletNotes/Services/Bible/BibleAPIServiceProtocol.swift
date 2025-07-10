import Foundation
import Combine

protocol BibleAPIServiceProtocol {
    var availableBibles: [Bible] { get }
    var isLoading: Bool { get }
    var error: String? { get }
    
    func fetchVerse(reference: ScriptureReference, bibleId: String) async throws -> BibleVerse
    func fetchPassage(reference: ScriptureReference, bibleId: String) async throws -> BiblePassage
    func searchVerses(query: String, bibleId: String, limit: Int) async throws -> [BibleVerse]
    func fetchBooks(bibleId: String) async throws -> [BibleBook]
}