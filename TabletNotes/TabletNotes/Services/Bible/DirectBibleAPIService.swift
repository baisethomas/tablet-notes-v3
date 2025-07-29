import Foundation
import Combine

// MARK: - Direct API.Bible Service
// This service connects directly to API.Bible without using Netlify Functions
@MainActor
class DirectBibleAPIService: ObservableObject, BibleAPIServiceProtocol {
    private var cancellables = Set<AnyCancellable>()
    
    @Published var availableBibles: [Bible] = []
    @Published var isLoading = false
    @Published var error: String?
    
    init() {
        loadAvailableBibles()
    }
    
    // MARK: - Private Methods
    
    private func makeRequest(endpoint: String) async throws -> Data {
        guard ApiBibleConfig.isConfigured else {
            throw BibleAPIError.invalidRequest
        }
        
        guard let url = URL(string: "\(ApiBibleConfig.baseURL)/\(endpoint)") else {
            throw BibleAPIError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add API.Bible headers
        for (key, value) in ApiBibleConfig.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        print("[DirectBibleAPIService] Making request to: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BibleAPIError.networkError(NSError(domain: "InvalidResponse", code: 0))
        }
        
        print("[DirectBibleAPIService] Response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[DirectBibleAPIService] API Error: \(errorMessage)")
            throw BibleAPIError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        return data
    }
    
    private func loadAvailableBibles() {
        Task {
            isLoading = true
            error = nil
            
            do {
                let data = try await makeRequest(endpoint: "bibles")
                let response = try JSONDecoder().decode(BibleAPIResponse<[Bible]>.self, from: data)
                
                // Filter to English Bibles only as requested
                let englishBibles = response.data.filter { bible in
                    bible.language.name.lowercased().contains("english")
                }.sorted { first, second in
                    // Prioritize common translations
                    let priority = ["KJV", "ESV", "NIV", "NLT", "NASB", "NKJV"]
                    let firstPriority = priority.firstIndex { first.abbreviation.contains($0) } ?? Int.max
                    let secondPriority = priority.firstIndex { second.abbreviation.contains($0) } ?? Int.max
                    return firstPriority < secondPriority
                }
                
                availableBibles = englishBibles
                print("[DirectBibleAPIService] Loaded \(englishBibles.count) English Bibles")
                
                // Log first few for debugging
                for bible in englishBibles.prefix(5) {
                    print("  - \(bible.abbreviation): \(bible.name) (ID: \(bible.id))")
                }
                
            } catch {
                print("[DirectBibleAPIService] Failed to load bibles: \(error)")
                self.error = error.localizedDescription
                
                // Use fallback bibles from configuration
                availableBibles = createFallbackBibles()
            }
            
            isLoading = false
        }
    }
    
    private func createFallbackBibles() -> [Bible] {
        // Create fallback Bible objects using the popular English Bible IDs
        return ApiBibleConfig.popularEnglishBibles.compactMap { bibleId in
            // Map known Bible IDs to their info
            let bibleInfo = getBibleInfo(for: bibleId)
            return Bible(
                id: bibleId,
                dblId: bibleId.replacingOccurrences(of: "-01", with: ""),
                abbreviation: bibleInfo.abbreviation,
                abbreviationLocal: bibleInfo.abbreviation,
                name: bibleInfo.name,
                nameLocal: bibleInfo.name,
                description: bibleInfo.description,
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
                updatedAt: "2023-01-01T00:00:00.000Z",
                audioBibles: nil
            )
        }
    }
    
    private func getBibleInfo(for bibleId: String) -> (abbreviation: String, name: String, description: String) {
        switch bibleId {
        case "06125adad2d5898a-01":
            return ("KJV", "King James Version", "The King James Version, published in 1611")
        case "90b8dbe0143dd92c-01":
            return ("NASB", "New American Standard Bible", "A modern, literal English translation")
        case "478cdd0b0b6f4567-01":
            return ("NKJV", "New King James Version", "A modern update of the King James Version")
        case "1ae3825917474b65-01":
            return ("NLT", "New Living Translation", "A dynamic, thought-for-thought translation")
        case "06d1bf24f83a1db4-01":
            return ("GNT", "Good News Translation", "A clear, simple English translation")
        case "ba11b4db61dd9f2b-01":
            return ("CEV", "Contemporary English Version", "A clear and natural English translation")
        case "9879dbb7cfe39e4d-01":
            return ("WEB", "World English Bible", "A public domain modern English translation")
        default:
            return ("UNK", "Unknown Translation", "Bible translation")
        }
    }
    
    // MARK: - BibleAPIServiceProtocol Implementation
    
    func fetchVerse(reference: String, bibleId: String) async throws -> BibleVerse {
        let formattedReference = formatReferenceForAPI(reference)
        let endpoint = "bibles/\(bibleId)/verses/\(formattedReference)"
        
        print("[DirectBibleAPIService] Fetching verse: \(formattedReference) from Bible: \(bibleId)")
        
        do {
            let data = try await makeRequest(endpoint: endpoint)
            let response = try JSONDecoder().decode(BibleAPIResponse<BibleVerse>.self, from: data)
            return response.data
        } catch {
            print("[DirectBibleAPIService] Error fetching verse: \(error)")
            
            // Create a fallback verse to prevent UI crashes
            let fallbackVerse = BibleVerse(
                id: "\(bibleId):\(formattedReference)",
                orgId: bibleId,
                bookId: "UNK",
                chapterId: "1",
                content: "This verse is currently unavailable. Please check your internet connection or try again later.",
                reference: reference,
                verseCount: 1,
                copyright: nil
            )
            return fallbackVerse
        }
    }
    
    func fetchPassage(reference: String, bibleId: String) async throws -> BiblePassage {
        let formattedReference = formatReferenceForAPI(reference)
        let endpoint = "bibles/\(bibleId)/passages/\(formattedReference)"
        
        print("[DirectBibleAPIService] Fetching passage: \(formattedReference) from Bible: \(bibleId)")
        
        do {
            let data = try await makeRequest(endpoint: endpoint)
            let response = try JSONDecoder().decode(BibleAPIResponse<BiblePassage>.self, from: data)
            return response.data
        } catch {
            print("[DirectBibleAPIService] Error fetching passage: \(error)")
            
            // Create a fallback passage to prevent UI crashes
            let fallbackPassage = BiblePassage(
                id: "\(bibleId):\(formattedReference)",
                orgId: bibleId,
                content: "This passage is currently unavailable. Please check your internet connection or try again later.",
                reference: reference,
                verseCount: 1,
                copyright: nil
            )
            return fallbackPassage
        }
    }
    
    func searchVerses(query: String, bibleId: String, limit: Int = 10) async throws -> [BibleVerse] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let endpoint = "bibles/\(bibleId)/search?query=\(encodedQuery)&limit=\(limit)"
        
        print("[DirectBibleAPIService] Searching for: \(query) in Bible: \(bibleId)")
        
        do {
            let data = try await makeRequest(endpoint: endpoint)
            
            // API.Bible search returns a different structure
            struct SearchResponse: Codable {
                let verses: [BibleVerse]
            }
            
            let response = try JSONDecoder().decode(BibleAPIResponse<SearchResponse>.self, from: data)
            return response.data.verses
        } catch {
            print("[DirectBibleAPIService] Error searching verses: \(error)")
            return [] // Return empty array instead of throwing to prevent UI crashes
        }
    }
    
    func fetchBooks(bibleId: String) async throws -> [BibleBook] {
        let endpoint = "bibles/\(bibleId)/books"
        
        print("[DirectBibleAPIService] Fetching books for Bible: \(bibleId)")
        
        do {
            let data = try await makeRequest(endpoint: endpoint)
            let response = try JSONDecoder().decode(BibleAPIResponse<[BibleBook]>.self, from: data)
            return response.data
        } catch {
            print("[DirectBibleAPIService] Error fetching books: \(error)")
            throw error
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatReferenceForAPI(_ reference: String) -> String {
        // Parse the reference string (e.g., "John 3:16" or "John 3:16-18")
        // and convert to API.Bible format (e.g., "JHN.3.16" or "JHN.3.16-JHN.3.18")
        
        print("[DirectBibleAPIService] Formatting reference: '\(reference)'")
        
        let components = reference.components(separatedBy: " ")
        guard components.count >= 2 else {
            print("[DirectBibleAPIService] Invalid reference format, returning as-is: \(reference)")
            return reference
        }
        
        let book = components.dropLast().joined(separator: " ")
        let chapterVerse = components.last ?? ""
        
        let chapterVerseComponents = chapterVerse.components(separatedBy: ":")
        guard chapterVerseComponents.count == 2 else {
            print("[DirectBibleAPIService] Invalid chapter:verse format, returning as-is: \(reference)")
            return reference
        }
        
        let chapter = chapterVerseComponents[0]
        let verseRange = chapterVerseComponents[1]
        
        let bookAbbreviation = convertBookNameToAbbreviation(book)
        print("[DirectBibleAPIService] Converted '\(book)' to '\(bookAbbreviation)'")
        
        if verseRange.contains("-") {
            // Range of verses: e.g., "16-18"
            let verseComponents = verseRange.components(separatedBy: "-")
            guard verseComponents.count == 2 else { return reference }
            let startVerse = verseComponents[0]
            let endVerse = verseComponents[1]
            return "\(bookAbbreviation).\(chapter).\(startVerse)-\(bookAbbreviation).\(chapter).\(endVerse)"
        } else {
            let formattedReference = "\(bookAbbreviation).\(chapter).\(verseRange)"
            print("[DirectBibleAPIService] Final formatted reference: '\(formattedReference)'")
            return formattedReference
        }
    }
    
    private func convertBookNameToAbbreviation(_ bookName: String) -> String {
        // API.Bible standard book abbreviations
        let bookMapping: [String: String] = [
            // Old Testament
            "Genesis": "GEN", "Exodus": "EXO", "Leviticus": "LEV", "Numbers": "NUM", "Deuteronomy": "DEU",
            "Joshua": "JOS", "Judges": "JDG", "Ruth": "RUT", "1 Samuel": "1SA", "2 Samuel": "2SA",
            "1 Kings": "1KI", "2 Kings": "2KI", "1 Chronicles": "1CH", "2 Chronicles": "2CH",
            "Ezra": "EZR", "Nehemiah": "NEH", "Esther": "EST", "Job": "JOB", "Psalms": "PSA",
            "Proverbs": "PRO", "Ecclesiastes": "ECC", "Song of Solomon": "SNG", "Song of Songs": "SNG", "Isaiah": "ISA",
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