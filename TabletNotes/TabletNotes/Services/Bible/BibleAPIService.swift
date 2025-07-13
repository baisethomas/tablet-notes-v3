import Foundation
import Combine

// MARK: - Bible API Models
struct BibleAPIResponse<T: Codable>: Codable {
    let data: T
}

struct BibleVerse: Codable, Identifiable {
    let id: String
    let orgId: String
    let bookId: String
    let chapterId: String
    let content: String
    let reference: String
    let verseCount: Int?
    let copyright: String?
}

struct BiblePassage: Codable {
    let id: String
    let orgId: String
    let content: String
    let reference: String
    let verseCount: Int?
    let copyright: String?
}

struct BibleBook: Codable, Identifiable {
    let id: String
    let bibleId: String
    let abbreviation: String
    let name: String
    let nameLong: String
}

struct Bible: Codable, Identifiable {
    let id: String
    let dblId: String
    let abbreviation: String
    let abbreviationLocal: String
    let name: String
    let nameLocal: String
    let description: String?
    let relatedDbl: String?
    let language: BibleLanguage
    let countries: [BibleCountry]
    let type: String
    let updatedAt: String
    let audioBibles: [AudioBible]?
}

struct BibleLanguage: Codable {
    let id: String
    let name: String
    let nameLocal: String
    let script: String
    let scriptDirection: String
}

struct BibleCountry: Codable {
    let id: String
    let name: String
    let nameLocal: String
}

struct AudioBible: Codable {
    let id: String
    let name: String
    let nameLocal: String
    let description: String?
    let language: BibleLanguage?
}

// MARK: - Bible API Service
class BibleAPIService: ObservableObject {
    private let netlifyAPIService = BibleNetlifyAPIService()
    private var defaultBibleId: String {
        return BibleAPIConfig.preferredBibleTranslation.id
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    @Published var availableBibles: [Bible] = []
    @Published var isLoading = false
    @Published var error: String?
    
    init() {
        loadAvailableBibles()
    }
    
    // MARK: - Private Methods
    
    private func loadAvailableBibles() {
        Task {
            do {
                let response = try await netlifyAPIService.makeRequest(endpoint: "bibles")
                let jsonData = try JSONSerialization.data(withJSONObject: response)
                let bibleResponse = try JSONDecoder().decode(BibleAPIResponse<[Bible]>.self, from: jsonData)
                
                await MainActor.run {
                    self.availableBibles = bibleResponse.data
                    print("[BibleAPIService] Loaded \(bibleResponse.data.count) Bibles")
                    let englishBibles = bibleResponse.data.filter { $0.language.name.lowercased().contains("english") }
                    print("[BibleAPIService] English Bibles available:")
                    for bible in englishBibles {
                        print("  - \(bible.abbreviation): \(bible.name) (ID: \(bible.id))")
                    }
                }
            } catch {
                await MainActor.run {
                    print("[BibleAPIService] Failed to load bibles: \(error)")
                    self.error = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Fetch a specific verse or range of verses
    func fetchVerse(reference: ScriptureReference, bibleId: String? = nil) async throws -> BibleVerse {
        let useBibleId = bibleId ?? defaultBibleId
        let verseReference = formatReferenceForAPI(reference)
        let endpoint = "bibles/\(useBibleId)/verses/\(verseReference)"
        
        do {
            let response = try await netlifyAPIService.makeRequest(endpoint: endpoint)
            let jsonData = try JSONSerialization.data(withJSONObject: response)
            let bibleResponse = try JSONDecoder().decode(BibleAPIResponse<BibleVerse>.self, from: jsonData)
            return bibleResponse.data
        } catch {
            print("[BibleAPIService] Error fetching verse: \(error)")
            throw BibleAPIError.networkError(error)
        }
    }
    
    /// Fetch a passage (multiple verses)
    func fetchPassage(reference: ScriptureReference, bibleId: String? = nil) async throws -> BiblePassage {
        let useBibleId = bibleId ?? defaultBibleId
        let passageReference = formatReferenceForAPI(reference)
        let endpoint = "bibles/\(useBibleId)/passages/\(passageReference)"
        
        do {
            let response = try await netlifyAPIService.makeRequest(endpoint: endpoint)
            let jsonData = try JSONSerialization.data(withJSONObject: response)
            let bibleResponse = try JSONDecoder().decode(BibleAPIResponse<BiblePassage>.self, from: jsonData)
            return bibleResponse.data
        } catch {
            print("[BibleAPIService] Error fetching passage: \(error)")
            throw BibleAPIError.networkError(error)
        }
    }
    
    /// Search for verses containing specific text
    func searchVerses(query: String, bibleId: String? = nil, limit: Int = 10) async throws -> [BibleVerse] {
        let useBibleId = bibleId ?? defaultBibleId
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let endpoint = "bibles/\(useBibleId)/search?query=\(encodedQuery)&limit=\(limit)"
        
        do {
            let response = try await netlifyAPIService.makeRequest(endpoint: endpoint)
            let jsonData = try JSONSerialization.data(withJSONObject: response)
            let bibleResponse = try JSONDecoder().decode(BibleAPIResponse<[BibleVerse]>.self, from: jsonData)
            return bibleResponse.data
        } catch {
            print("[BibleAPIService] Error searching verses: \(error)")
            throw BibleAPIError.networkError(error)
        }
    }
    
    /// Get list of books for a specific Bible
    func fetchBooks(bibleId: String? = nil) async throws -> [BibleBook] {
        let useBibleId = bibleId ?? defaultBibleId
        let endpoint = "bibles/\(useBibleId)/books"
        
        do {
            let response = try await netlifyAPIService.makeRequest(endpoint: endpoint)
            let jsonData = try JSONSerialization.data(withJSONObject: response)
            let bibleResponse = try JSONDecoder().decode(BibleAPIResponse<[BibleBook]>.self, from: jsonData)
            return bibleResponse.data
        } catch {
            print("[BibleAPIService] Error fetching books: \(error)")
            throw BibleAPIError.networkError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatReferenceForAPI(_ reference: ScriptureReference) -> String {
        // Convert book name to Bible API format
        let bookAbbreviation = convertBookNameToAbbreviation(reference.book)
        
        if let verseEnd = reference.verseEnd {
            // Range of verses: e.g., "JHN.3.16-JHN.3.18"
            return "\(bookAbbreviation).\(reference.chapter).\(reference.verseStart)-\(bookAbbreviation).\(reference.chapter).\(verseEnd)"
        } else {
            // Single verse: e.g., "JHN.3.16"
            return "\(bookAbbreviation).\(reference.chapter).\(reference.verseStart)"
        }
    }
    
    private func convertBookNameToAbbreviation(_ bookName: String) -> String {
        let bookMapping: [String: String] = [
            // Old Testament
            "Genesis": "GEN", "Exodus": "EXO", "Leviticus": "LEV", "Numbers": "NUM", "Deuteronomy": "DEU",
            "Joshua": "JOS", "Judges": "JDG", "Ruth": "RUT", "1 Samuel": "1SA", "2 Samuel": "2SA",
            "1 Kings": "1KI", "2 Kings": "2KI", "1 Chronicles": "1CH", "2 Chronicles": "2CH",
            "Ezra": "EZR", "Nehemiah": "NEH", "Esther": "EST", "Job": "JOB", "Psalms": "PSA",
            "Proverbs": "PRO", "Ecclesiastes": "ECC", "Song of Solomon": "SNG", "Isaiah": "ISA",
            "Jeremiah": "JER", "Lamentations": "LAM", "Ezekiel": "EZK", "Daniel": "DAN",
            "Hosea": "HOS", "Joel": "JOL", "Amos": "AMO", "Obadiah": "OBA", "Jonah": "JON",
            "Micah": "MIC", "Nahum": "NAM", "Habakkuk": "HAB", "Zephaniah": "ZEP", "Haggai": "HAG",
            "Zechariah": "ZEC", "Malachi": "MAL",
            
            // New Testament
            "Matthew": "MAT", "Mark": "MRK", "Luke": "LUK", "John": "JHN", "Acts": "ACT",
            "Romans": "ROM", "1 Corinthians": "1CO", "2 Corinthians": "2CO", "Galatians": "GAL",
            "Ephesians": "EPH", "Philippians": "PHP", "Colossians": "COL", "1 Thessalonians": "1TH",
            "2 Thessalonians": "2TH", "1 Timothy": "1TI", "2 Timothy": "2TI", "Titus": "TIT",
            "Philemon": "PHM", "Hebrews": "HEB", "James": "JAS", "1 Peter": "1PE", "2 Peter": "2PE",
            "1 John": "1JN", "2 John": "2JN", "3 John": "3JN", "Jude": "JUD", "Revelation": "REV"
        ]
        
        // Try exact match first
        if let abbreviation = bookMapping[bookName] {
            return abbreviation
        }
        
        // Try partial matches for common variations
        for (fullName, abbreviation) in bookMapping {
            if fullName.lowercased().contains(bookName.lowercased()) || 
               bookName.lowercased().contains(fullName.lowercased()) {
                return abbreviation
            }
        }
        
        // Fallback: try to extract first 3 letters as uppercase
        let cleanName = bookName.replacingOccurrences(of: "\\d+\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanName.count >= 3 {
            return String(cleanName.prefix(3)).uppercased()
        }
        
        return bookName.uppercased()
    }
}

// MARK: - Errors
enum BibleAPIError: LocalizedError {
    case invalidRequest
    case networkError(Error)
    case decodingError(Error)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid API request"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}