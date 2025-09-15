import Foundation
import Combine

class BibleAPIService: ObservableObject, BibleAPIServiceProtocol {
    @Published var availableBibles: [Bible] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadAvailableBibles()
    }
    
    // MARK: - BibleAPIServiceProtocol Implementation
    
    func fetchVerse(reference: String, bibleId: String) async throws -> BibleVerse {
        print("[BibleAPIService] fetchVerse called with reference: '\(reference)', bibleId: '\(bibleId)'")
        let verseId = formatReferenceForAPI(reference)
        print("[BibleAPIService] Using verse ID: '\(verseId)' with Bible: '\(bibleId)'")
        let url = URL(string: "\(ApiBibleConfig.baseURL)/bibles/\(bibleId)/verses/\(verseId)")!
        
        var request = URLRequest(url: url)
        ApiBibleConfig.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BibleAPIError.networkError(URLError(.badServerResponse))
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw BibleAPIError.apiError("Invalid API key. Please check your API.Bible configuration.")
            } else if httpResponse.statusCode == 404 {
                throw BibleAPIError.apiError("Verse not found in selected translation.")
            }
            throw BibleAPIError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        let apiResponse = try JSONDecoder().decode(BibleAPIResponse<BibleVerse>.self, from: data)
        return apiResponse.data
    }
    
    func fetchPassage(reference: String, bibleId: String) async throws -> BiblePassage {
        let passageId = formatReferenceForAPI(reference)
        let url = URL(string: "\(ApiBibleConfig.baseURL)/bibles/\(bibleId)/passages/\(passageId)")!
        
        var request = URLRequest(url: url)
        ApiBibleConfig.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BibleAPIError.networkError(URLError(.badServerResponse))
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw BibleAPIError.apiError("Invalid API key. Please check your API.Bible configuration.")
            } else if httpResponse.statusCode == 404 {
                throw BibleAPIError.apiError("Passage not found in selected translation.")
            }
            throw BibleAPIError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        let apiResponse = try JSONDecoder().decode(BibleAPIResponse<BiblePassage>.self, from: data)
        return apiResponse.data
    }
    
    func searchVerses(query: String, bibleId: String, limit: Int = 10) async throws -> [BibleVerse] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "\(ApiBibleConfig.baseURL)/bibles/\(bibleId)/search?query=\(encodedQuery)&limit=\(limit)")!
        
        var request = URLRequest(url: url)
        ApiBibleConfig.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BibleAPIError.networkError(URLError(.badServerResponse))
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw BibleAPIError.apiError("Invalid API key. Please check your API.Bible configuration.")
            }
            throw BibleAPIError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        let searchResponse = try JSONDecoder().decode(BibleAPIResponse<BibleSearchResult>.self, from: data)
        return searchResponse.data.verses
    }
    
    func fetchBooks(bibleId: String) async throws -> [BibleBook] {
        let url = URL(string: "\(ApiBibleConfig.baseURL)/bibles/\(bibleId)/books")!
        
        var request = URLRequest(url: url)
        ApiBibleConfig.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BibleAPIError.networkError(URLError(.badServerResponse))
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw BibleAPIError.apiError("Invalid API key. Please check your API.Bible configuration.")
            }
            throw BibleAPIError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        let apiResponse = try JSONDecoder().decode(BibleAPIResponse<[BibleBook]>.self, from: data)
        return apiResponse.data
    }
    
    // MARK: - Private Methods
    
    private func loadAvailableBibles() {
        guard ApiBibleConfig.isConfigured else {
            DispatchQueue.main.async {
                self.error = "API key not configured. Please add your API.Bible key to ApiBibleConfig."
                self.availableBibles = []
            }
            return
        }
        
        isLoading = true
        
        Task {
            do {
                let url = URL(string: "\(ApiBibleConfig.baseURL)/bibles")!
                var request = URLRequest(url: url)
                ApiBibleConfig.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw BibleAPIError.networkError(URLError(.badServerResponse))
                }
                
                guard httpResponse.statusCode == 200 else {
                    if httpResponse.statusCode == 401 {
                        throw BibleAPIError.apiError("Invalid API key. Please check your API.Bible configuration.")
                    }
                    throw BibleAPIError.apiError("HTTP \(httpResponse.statusCode)")
                }
                
                let apiResponse = try JSONDecoder().decode(BibleAPIResponse<[Bible]>.self, from: data)
                
                await MainActor.run {
                    let filteredBibles = apiResponse.data.filter { bible in
                        bible.language.name.lowercased().contains("english")
                    }.sorted { first, second in
                        // Prioritize common translations
                        let priority = ["KJV", "ESV", "NIV", "NLT", "NASB", "ASV"]
                        let firstPriority = priority.firstIndex { first.abbreviation.contains($0) } ?? Int.max
                        let secondPriority = priority.firstIndex { second.abbreviation.contains($0) } ?? Int.max
                        return firstPriority < secondPriority
                    }
                    self.availableBibles = filteredBibles
                    self.isLoading = false
                    self.error = nil
                    print("[BibleAPIService] Successfully loaded \(filteredBibles.count) English Bibles from API")
                    print("[BibleAPIService] First few Bible IDs: \(filteredBibles.prefix(3).map { "\($0.abbreviation): \($0.id)" })")
                }
            } catch {
                print("[BibleAPIService] Failed to load bibles: \(error)")
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                    // Use fallback Bible list for popular translations
                    self.availableBibles = getFallbackBibles()
                    print("[BibleAPIService] Using fallback Bibles: \(self.availableBibles.prefix(3).map { $0.id })")
                }
            }
        }
    }
    
    private func formatReferenceForAPI(_ reference: String) -> String {
        // API.Bible uses standard format: BOOK.CHAPTER.VERSE
        // Convert "John 3:16" to "JHN.3.16"

        print("[BibleAPIService] Formatting reference: '\(reference)'")

        // Handle different input formats
        let normalizedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)

        // Split by space to separate book name from chapter:verse
        let components = normalizedReference.components(separatedBy: " ")
        guard components.count >= 2 else {
            print("[BibleAPIService] Invalid reference format: \(reference)")
            return reference
        }

        // Everything except the last component is the book name
        let book = components.dropLast().joined(separator: " ")
        let chapterVerse = components.last ?? ""

        print("[BibleAPIService] Parsed book: '\(book)', chapterVerse: '\(chapterVerse)'")

        // Split chapter:verse
        let chapterVerseComponents = chapterVerse.components(separatedBy: ":")
        guard chapterVerseComponents.count == 2 else {
            print("[BibleAPIService] Invalid chapter:verse format: \(chapterVerse)")
            return reference
        }

        let chapter = chapterVerseComponents[0]
        let verseRange = chapterVerseComponents[1]

        let bookAbbreviation = convertBookNameToAPIBibleFormat(book)

        print("[BibleAPIService] Book abbreviation: '\(bookAbbreviation)', chapter: '\(chapter)', verse: '\(verseRange)'")

        // Handle verse ranges like "16-18"
        if verseRange.contains("-") {
            let verseComponents = verseRange.components(separatedBy: "-")
            guard verseComponents.count == 2 else {
                let result = "\(bookAbbreviation).\(chapter).\(verseRange)"
                print("[BibleAPIService] Formatted result (range): \(result)")
                return result
            }
            let result = "\(bookAbbreviation).\(chapter).\(verseComponents[0])-\(bookAbbreviation).\(chapter).\(verseComponents[1])"
            print("[BibleAPIService] Formatted result (range): \(result)")
            return result
        }

        let result = "\(bookAbbreviation).\(chapter).\(verseRange)"
        print("[BibleAPIService] Formatted result: \(result)")
        return result
    }
    
    private func convertBookNameToAPIBibleFormat(_ bookName: String) -> String {
        // API.Bible standard 3-letter book codes
        let bookMapping: [String: String] = [
            // Old Testament
            "Genesis": "GEN", "Exodus": "EXO", "Leviticus": "LEV", "Numbers": "NUM", "Deuteronomy": "DEU",
            "Joshua": "JOS", "Judges": "JDG", "Ruth": "RUT", "1 Samuel": "1SA", "2 Samuel": "2SA",
            "1 Kings": "1KI", "2 Kings": "2KI", "1 Chronicles": "1CH", "2 Chronicles": "2CH",
            "Ezra": "EZR", "Nehemiah": "NEH", "Esther": "EST", "Job": "JOB", "Psalms": "PSA",
            "Proverbs": "PRO", "Ecclesiastes": "ECC", "Song of Songs": "SNG", "Song of Solomon": "SNG", 
            "Isaiah": "ISA", "Jeremiah": "JER", "Lamentations": "LAM", "Ezekiel": "EZK", "Daniel": "DAN",
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
        
        // Fallback: use first 3 letters uppercase
        return String(bookName.prefix(3)).uppercased()
    }
    
    private func getFallbackBibles() -> [Bible] {
        // Provide popular English Bibles as fallback when API fails
        return ApiBibleConfig.popularEnglishBibles.enumerated().map { index, bibleId in
            let names = ["King James Version", "New American Standard Bible", "New King James Version", 
                        "New Living Translation", "Good News Translation", "Contemporary English Version", "World English Bible"]
            let abbreviations = ["KJV", "NASB", "NKJV", "NLT", "GNT", "CEV", "WEB"]
            
            return Bible(
                id: bibleId,
                dblId: bibleId.replacingOccurrences(of: "-01", with: ""),
                abbreviation: abbreviations[safe: index] ?? "UNK",
                abbreviationLocal: abbreviations[safe: index] ?? "UNK",
                name: names[safe: index] ?? "Unknown Bible",
                nameLocal: names[safe: index] ?? "Unknown Bible",
                description: "Popular English Bible translation",
                relatedDbl: nil,
                language: BibleLanguage(
                    id: "eng",
                    name: "English",
                    nameLocal: "English",
                    script: "Latn",
                    scriptDirection: "LTR"
                ),
                countries: [BibleCountry(id: "US", name: "United States", nameLocal: "United States")],
                type: "text",
                updatedAt: "2024-01-01T00:00:00.000Z",
                audioBibles: nil
            )
        }
    }
}

// MARK: - Array Extension for Safe Access
extension Array {
    subscript(safe index: Int) -> Element? {
        return index >= 0 && index < count ? self[index] : nil
    }
}