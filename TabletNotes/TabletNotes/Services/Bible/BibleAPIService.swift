import Foundation
import Combine

// Import ScriptureReference from ScriptureAnalysisServiceProtocol file
// Since they're in the same module, no explicit import needed, but ensuring visibility

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
                    // Fallback to default bibles when API fails
                    self.availableBibles = getDefaultBibles()
                    print("[BibleAPIService] Using fallback Bible translations")
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Fetch a specific verse or range of verses
    func fetchVerse(reference: String, bibleId: String? = nil) async throws -> BibleVerse {
        let useBibleId = bibleId ?? defaultBibleId
        let verseReference = formatReferenceForAPI(reference)
        let endpoint = "bibles/\(useBibleId)/verses/\(verseReference)"
        
        print("[BibleAPIService] Fetching verse: \(verseReference) from Bible: \(useBibleId)")
        
        do {
            let response = try await netlifyAPIService.makeRequest(endpoint: endpoint)
            let jsonData = try JSONSerialization.data(withJSONObject: response)
            let bibleResponse = try JSONDecoder().decode(BibleAPIResponse<BibleVerse>.self, from: jsonData)
            return bibleResponse.data
        } catch {
            print("[BibleAPIService] Error fetching verse: \(error)")
            
            // Handle verse not found errors gracefully
            if let nsError = error as NSError?, nsError.code == 404 {
                throw BibleAPIError.apiError("Verse not found in selected translation")
            }
            
            // Return placeholder on any error to prevent app crashes
            let placeholderVerse = BibleVerse(
                id: "\(useBibleId):\(verseReference)",
                orgId: useBibleId,
                bookId: "UNK",
                chapterId: "1",
                content: "This verse is currently unavailable. Please check your internet connection or try again later.",
                reference: reference,
                verseCount: 1,
                copyright: nil
            )
            return placeholderVerse
        }
    }
    
    /// Fetch a passage (multiple verses)
    func fetchPassage(reference: String, bibleId: String? = nil) async throws -> BiblePassage {
        let useBibleId = bibleId ?? defaultBibleId
        let passageReference = formatReferenceForAPI(reference)
        let endpoint = "bibles/\(useBibleId)/passages/\(passageReference)"
        
        print("[BibleAPIService] Fetching passage: \(passageReference) from Bible: \(useBibleId)")
        
        do {
            let response = try await netlifyAPIService.makeRequest(endpoint: endpoint)
            let jsonData = try JSONSerialization.data(withJSONObject: response)
            let bibleResponse = try JSONDecoder().decode(BibleAPIResponse<BiblePassage>.self, from: jsonData)
            return bibleResponse.data
        } catch {
            print("[BibleAPIService] Error fetching passage: \(error)")
            
            // Handle passage not found errors gracefully
            if let nsError = error as NSError?, nsError.code == 404 {
                throw BibleAPIError.apiError("Passage not found in selected translation")
            }
            
            // Return placeholder on any error to prevent app crashes
            let placeholderPassage = BiblePassage(
                id: "\(useBibleId):\(passageReference)",
                orgId: useBibleId,
                content: "This passage is currently unavailable. Please check your internet connection or try again later.",
                reference: reference,
                verseCount: 1,
                copyright: nil
            )
            return placeholderPassage
        }
    }
    
    /// Search for verses containing specific text
    func searchVerses(query: String, bibleId: String? = nil, limit: Int = 10) async throws -> [BibleVerse] {
        let useBibleId = bibleId ?? defaultBibleId
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let endpoint = "bibles/\(useBibleId)/search?query=\(encodedQuery)&limit=\(limit)"
        
        print("[BibleAPIService] Searching for verses with query: \(query) in Bible: \(useBibleId)")
        
        do {
            let response = try await netlifyAPIService.makeRequest(endpoint: endpoint)
            let jsonData = try JSONSerialization.data(withJSONObject: response)
            let bibleResponse = try JSONDecoder().decode(BibleAPIResponse<[BibleVerse]>.self, from: jsonData)
            return bibleResponse.data
        } catch {
            print("[BibleAPIService] Error searching verses: \(error)")
            // Return empty array on error to prevent app crashes
            return []
        }
    }
    
    /// Get list of books for a specific Bible
    func fetchBooks(bibleId: String? = nil) async throws -> [BibleBook] {
        let useBibleId = bibleId ?? defaultBibleId
        let endpoint = "bibles/\(useBibleId)/books"
        
        print("[BibleAPIService] Fetching books for Bible: \(useBibleId)")
        
        do {
            let response = try await netlifyAPIService.makeRequest(endpoint: endpoint)
            let jsonData = try JSONSerialization.data(withJSONObject: response)
            let bibleResponse = try JSONDecoder().decode(BibleAPIResponse<[BibleBook]>.self, from: jsonData)
            return bibleResponse.data
        } catch {
            print("[BibleAPIService] Error fetching books: \(error)")
            // Return standard Bible books as fallback
            return getStandardBibleBooks()
        }
    }
    
    // MARK: - Helper Methods
    
    private func getDefaultBibles() -> [Bible] {
        // Provide fallback Bible translations when API fails
        return [
            Bible(
                id: "de4e12af7f28f599-02",
                dblId: "de4e12af7f28f599",
                abbreviation: "ESV",
                abbreviationLocal: "ESV",
                name: "English Standard Version",
                nameLocal: "English Standard Version",
                description: "The English Standard Version (ESV) is an English translation of the Bible.",
                relatedDbl: nil,
                language: BibleLanguage(
                    id: "eng",
                    name: "English",
                    nameLocal: "English",
                    script: "Latn",
                    scriptDirection: "LTR"
                ),
                countries: [
                    BibleCountry(id: "US", name: "United States", nameLocal: "United States")
                ],
                type: "text",
                updatedAt: "2021-11-01T00:00:00.000Z",
                audioBibles: nil
            ),
            Bible(
                id: "06125adad2d5898a-01",
                dblId: "06125adad2d5898a",
                abbreviation: "NIV",
                abbreviationLocal: "NIV",
                name: "New International Version",
                nameLocal: "New International Version",
                description: "The New International Version (NIV) is an English translation of the Bible.",
                relatedDbl: nil,
                language: BibleLanguage(
                    id: "eng",
                    name: "English",
                    nameLocal: "English",
                    script: "Latn",
                    scriptDirection: "LTR"
                ),
                countries: [
                    BibleCountry(id: "US", name: "United States", nameLocal: "United States")
                ],
                type: "text",
                updatedAt: "2021-11-01T00:00:00.000Z",
                audioBibles: nil
            )
        ]
    }
    
    private func getStandardBibleBooks() -> [BibleBook] {
        // Return standard 66 Bible books
        return [
            // Old Testament
            BibleBook(id: "GEN", bibleId: defaultBibleId, abbreviation: "Gen", name: "Genesis", nameLong: "Genesis"),
            BibleBook(id: "EXO", bibleId: defaultBibleId, abbreviation: "Exo", name: "Exodus", nameLong: "Exodus"),
            BibleBook(id: "LEV", bibleId: defaultBibleId, abbreviation: "Lev", name: "Leviticus", nameLong: "Leviticus"),
            BibleBook(id: "NUM", bibleId: defaultBibleId, abbreviation: "Num", name: "Numbers", nameLong: "Numbers"),
            BibleBook(id: "DEU", bibleId: defaultBibleId, abbreviation: "Deu", name: "Deuteronomy", nameLong: "Deuteronomy"),
            BibleBook(id: "JOS", bibleId: defaultBibleId, abbreviation: "Jos", name: "Joshua", nameLong: "Joshua"),
            BibleBook(id: "JDG", bibleId: defaultBibleId, abbreviation: "Jdg", name: "Judges", nameLong: "Judges"),
            BibleBook(id: "RUT", bibleId: defaultBibleId, abbreviation: "Rut", name: "Ruth", nameLong: "Ruth"),
            BibleBook(id: "1SA", bibleId: defaultBibleId, abbreviation: "1Sa", name: "1 Samuel", nameLong: "1 Samuel"),
            BibleBook(id: "2SA", bibleId: defaultBibleId, abbreviation: "2Sa", name: "2 Samuel", nameLong: "2 Samuel"),
            BibleBook(id: "1KI", bibleId: defaultBibleId, abbreviation: "1Ki", name: "1 Kings", nameLong: "1 Kings"),
            BibleBook(id: "2KI", bibleId: defaultBibleId, abbreviation: "2Ki", name: "2 Kings", nameLong: "2 Kings"),
            BibleBook(id: "1CH", bibleId: defaultBibleId, abbreviation: "1Ch", name: "1 Chronicles", nameLong: "1 Chronicles"),
            BibleBook(id: "2CH", bibleId: defaultBibleId, abbreviation: "2Ch", name: "2 Chronicles", nameLong: "2 Chronicles"),
            BibleBook(id: "EZR", bibleId: defaultBibleId, abbreviation: "Ezr", name: "Ezra", nameLong: "Ezra"),
            BibleBook(id: "NEH", bibleId: defaultBibleId, abbreviation: "Neh", name: "Nehemiah", nameLong: "Nehemiah"),
            BibleBook(id: "EST", bibleId: defaultBibleId, abbreviation: "Est", name: "Esther", nameLong: "Esther"),
            BibleBook(id: "JOB", bibleId: defaultBibleId, abbreviation: "Job", name: "Job", nameLong: "Job"),
            BibleBook(id: "PSA", bibleId: defaultBibleId, abbreviation: "Psa", name: "Psalms", nameLong: "Psalms"),
            BibleBook(id: "PRO", bibleId: defaultBibleId, abbreviation: "Pro", name: "Proverbs", nameLong: "Proverbs"),
            BibleBook(id: "ECC", bibleId: defaultBibleId, abbreviation: "Ecc", name: "Ecclesiastes", nameLong: "Ecclesiastes"),
            BibleBook(id: "SNG", bibleId: defaultBibleId, abbreviation: "Sng", name: "Song of Songs", nameLong: "Song of Songs"),
            BibleBook(id: "ISA", bibleId: defaultBibleId, abbreviation: "Isa", name: "Isaiah", nameLong: "Isaiah"),
            BibleBook(id: "JER", bibleId: defaultBibleId, abbreviation: "Jer", name: "Jeremiah", nameLong: "Jeremiah"),
            BibleBook(id: "LAM", bibleId: defaultBibleId, abbreviation: "Lam", name: "Lamentations", nameLong: "Lamentations"),
            BibleBook(id: "EZK", bibleId: defaultBibleId, abbreviation: "Ezk", name: "Ezekiel", nameLong: "Ezekiel"),
            BibleBook(id: "DAN", bibleId: defaultBibleId, abbreviation: "Dan", name: "Daniel", nameLong: "Daniel"),
            BibleBook(id: "HOS", bibleId: defaultBibleId, abbreviation: "Hos", name: "Hosea", nameLong: "Hosea"),
            BibleBook(id: "JOL", bibleId: defaultBibleId, abbreviation: "Jol", name: "Joel", nameLong: "Joel"),
            BibleBook(id: "AMO", bibleId: defaultBibleId, abbreviation: "Amo", name: "Amos", nameLong: "Amos"),
            BibleBook(id: "OBA", bibleId: defaultBibleId, abbreviation: "Oba", name: "Obadiah", nameLong: "Obadiah"),
            BibleBook(id: "JON", bibleId: defaultBibleId, abbreviation: "Jon", name: "Jonah", nameLong: "Jonah"),
            BibleBook(id: "MIC", bibleId: defaultBibleId, abbreviation: "Mic", name: "Micah", nameLong: "Micah"),
            BibleBook(id: "NAM", bibleId: defaultBibleId, abbreviation: "Nam", name: "Nahum", nameLong: "Nahum"),
            BibleBook(id: "HAB", bibleId: defaultBibleId, abbreviation: "Hab", name: "Habakkuk", nameLong: "Habakkuk"),
            BibleBook(id: "ZEP", bibleId: defaultBibleId, abbreviation: "Zep", name: "Zephaniah", nameLong: "Zephaniah"),
            BibleBook(id: "HAG", bibleId: defaultBibleId, abbreviation: "Hag", name: "Haggai", nameLong: "Haggai"),
            BibleBook(id: "ZEC", bibleId: defaultBibleId, abbreviation: "Zec", name: "Zechariah", nameLong: "Zechariah"),
            BibleBook(id: "MAL", bibleId: defaultBibleId, abbreviation: "Mal", name: "Malachi", nameLong: "Malachi"),
            
            // New Testament
            BibleBook(id: "MAT", bibleId: defaultBibleId, abbreviation: "Mat", name: "Matthew", nameLong: "Matthew"),
            BibleBook(id: "MRK", bibleId: defaultBibleId, abbreviation: "Mrk", name: "Mark", nameLong: "Mark"),
            BibleBook(id: "LUK", bibleId: defaultBibleId, abbreviation: "Luk", name: "Luke", nameLong: "Luke"),
            BibleBook(id: "JHN", bibleId: defaultBibleId, abbreviation: "Jhn", name: "John", nameLong: "John"),
            BibleBook(id: "ACT", bibleId: defaultBibleId, abbreviation: "Act", name: "Acts", nameLong: "Acts"),
            BibleBook(id: "ROM", bibleId: defaultBibleId, abbreviation: "Rom", name: "Romans", nameLong: "Romans"),
            BibleBook(id: "1CO", bibleId: defaultBibleId, abbreviation: "1Co", name: "1 Corinthians", nameLong: "1 Corinthians"),
            BibleBook(id: "2CO", bibleId: defaultBibleId, abbreviation: "2Co", name: "2 Corinthians", nameLong: "2 Corinthians"),
            BibleBook(id: "GAL", bibleId: defaultBibleId, abbreviation: "Gal", name: "Galatians", nameLong: "Galatians"),
            BibleBook(id: "EPH", bibleId: defaultBibleId, abbreviation: "Eph", name: "Ephesians", nameLong: "Ephesians"),
            BibleBook(id: "PHP", bibleId: defaultBibleId, abbreviation: "Php", name: "Philippians", nameLong: "Philippians"),
            BibleBook(id: "COL", bibleId: defaultBibleId, abbreviation: "Col", name: "Colossians", nameLong: "Colossians"),
            BibleBook(id: "1TH", bibleId: defaultBibleId, abbreviation: "1Th", name: "1 Thessalonians", nameLong: "1 Thessalonians"),
            BibleBook(id: "2TH", bibleId: defaultBibleId, abbreviation: "2Th", name: "2 Thessalonians", nameLong: "2 Thessalonians"),
            BibleBook(id: "1TI", bibleId: defaultBibleId, abbreviation: "1Ti", name: "1 Timothy", nameLong: "1 Timothy"),
            BibleBook(id: "2TI", bibleId: defaultBibleId, abbreviation: "2Ti", name: "2 Timothy", nameLong: "2 Timothy"),
            BibleBook(id: "TIT", bibleId: defaultBibleId, abbreviation: "Tit", name: "Titus", nameLong: "Titus"),
            BibleBook(id: "PHM", bibleId: defaultBibleId, abbreviation: "Phm", name: "Philemon", nameLong: "Philemon"),
            BibleBook(id: "HEB", bibleId: defaultBibleId, abbreviation: "Heb", name: "Hebrews", nameLong: "Hebrews"),
            BibleBook(id: "JAS", bibleId: defaultBibleId, abbreviation: "Jas", name: "James", nameLong: "James"),
            BibleBook(id: "1PE", bibleId: defaultBibleId, abbreviation: "1Pe", name: "1 Peter", nameLong: "1 Peter"),
            BibleBook(id: "2PE", bibleId: defaultBibleId, abbreviation: "2Pe", name: "2 Peter", nameLong: "2 Peter"),
            BibleBook(id: "1JN", bibleId: defaultBibleId, abbreviation: "1Jn", name: "1 John", nameLong: "1 John"),
            BibleBook(id: "2JN", bibleId: defaultBibleId, abbreviation: "2Jn", name: "2 John", nameLong: "2 John"),
            BibleBook(id: "3JN", bibleId: defaultBibleId, abbreviation: "3Jn", name: "3 John", nameLong: "3 John"),
            BibleBook(id: "JUD", bibleId: defaultBibleId, abbreviation: "Jud", name: "Jude", nameLong: "Jude"),
            BibleBook(id: "REV", bibleId: defaultBibleId, abbreviation: "Rev", name: "Revelation", nameLong: "Revelation")
        ]
    }
    
    private func formatReferenceForAPI(_ reference: String) -> String {
        // Parse the reference string (e.g., "John 3:16" or "John 3:16-18") 
        // and convert to Bible API format (e.g., "JHN.3.16" or "JHN.3.16-JHN.3.18")
        
        let components = reference.components(separatedBy: " ")
        guard components.count >= 2 else { return reference }
        
        let book = components.dropLast().joined(separator: " ")
        let chapterVerse = components.last ?? ""
        
        let chapterVerseComponents = chapterVerse.components(separatedBy: ":")
        guard chapterVerseComponents.count == 2 else { return reference }
        
        let chapter = chapterVerseComponents[0]
        let verseRange = chapterVerseComponents[1]
        
        let bookAbbreviation = convertBookNameToAbbreviation(book)
        
        if verseRange.contains("-") {
            // Range of verses: e.g., "16-18"
            let verseComponents = verseRange.components(separatedBy: "-")
            guard verseComponents.count == 2 else { return reference }
            let startVerse = verseComponents[0]
            let endVerse = verseComponents[1]
            return "\(bookAbbreviation).\(chapter).\(startVerse)-\(bookAbbreviation).\(chapter).\(endVerse)"
        } else {
            // Single verse: e.g., "16"
            return "\(bookAbbreviation).\(chapter).\(verseRange)"
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