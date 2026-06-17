import Foundation
import Combine
import Supabase

class BibleAPIService: ObservableObject, BibleAPIServiceProtocol {
    @Published var availableBibles: [Bible] = []
    @Published var isLoading = false
    @Published var error: String?

    private let session = URLSession.shared
    private let apiBaseUrl = "https://comfy-daffodil-7ecc55.netlify.app/api"
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseService.shared.client) {
        self.supabase = supabase
        loadAvailableBibles()
    }

    // MARK: - Backend proxy transport
    // All Bible calls go through the Netlify bible-api proxy, which holds the
    // API.Bible key server-side. The client no longer ships the key (TAB-48).

    private func getAuthToken() async throws -> String {
        do {
            return try await supabase.auth.session.accessToken
        } catch {
            do {
                return try await supabase.auth.refreshSession().accessToken
            } catch {
                throw BibleAPIError.networkError(error)
            }
        }
    }

    /// Performs a GET against the bible-api proxy and decodes the inner
    /// api.bible payload. `endpoint` is a relative api.bible path (query values
    /// already percent-encoded); it is encoded again here so '/', '?', '&', '='
    /// ride as the `endpoint` query value rather than altering the proxy URL.
    private func proxyGet<T: Decodable>(_ endpoint: String, as type: T.Type) async throws -> T {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = endpoint.addingPercentEncoding(withAllowedCharacters: allowed) ?? endpoint
        guard let url = URL(string: "\(apiBaseUrl)/bible-api?endpoint=\(encoded)") else {
            throw BibleAPIError.invalidRequest
        }

        let token = try await getAuthToken()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BibleAPIError.networkError(URLError(.badServerResponse))
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw BibleAPIError.apiError("Please sign in to use Bible lookups.")
            }
            throw BibleAPIError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Proxy envelope: { data: { data: <api.bible {data, meta}>, ... } }.
        // On a Bible-side 4xx the proxy returns 200 with { data: { data: null, error } }.
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseData = root["data"] as? [String: Any] else {
            throw BibleAPIError.apiError("Invalid response format")
        }
        if let apiError = responseData["error"] as? String {
            throw BibleAPIError.apiError(apiError)
        }
        guard let apiBible = responseData["data"], !(apiBible is NSNull) else {
            throw BibleAPIError.apiError("No data returned")
        }

        let apiBibleData = try JSONSerialization.data(withJSONObject: apiBible)
        return try JSONDecoder().decode(type, from: apiBibleData)
    }

    // MARK: - BibleAPIServiceProtocol Implementation

    func fetchVerse(reference: String, bibleId: String) async throws -> BibleVerse {
        let verseId = formatReferenceForAPI(reference)
        let response = try await proxyGet("bibles/\(bibleId)/verses/\(verseId)", as: BibleAPIResponse<BibleVerse>.self)
        return response.data
    }

    func fetchPassage(reference: String, bibleId: String) async throws -> BiblePassage {
        let passageId = formatReferenceForAPI(reference)
        let response = try await proxyGet("bibles/\(bibleId)/passages/\(passageId)", as: BibleAPIResponse<BiblePassage>.self)
        return response.data
    }

    func searchVerses(query: String, bibleId: String, limit: Int = 10) async throws -> [BibleVerse] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        let response = try await proxyGet("bibles/\(bibleId)/search?query=\(encodedQuery)&limit=\(limit)", as: BibleAPIResponse<BibleSearchResult>.self)
        return response.data.verses
    }

    func fetchBooks(bibleId: String) async throws -> [BibleBook] {
        let response = try await proxyGet("bibles/\(bibleId)/books", as: BibleAPIResponse<[BibleBook]>.self)
        return response.data
    }

    // MARK: - Private Methods

    private func loadAvailableBibles() {
        isLoading = true

        Task {
            do {
                let response = try await proxyGet("bibles", as: BibleAPIResponse<[Bible]>.self)

                await MainActor.run {
                    let filteredBibles = response.data.filter { bible in
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
                    print("[BibleAPIService] Loaded \(filteredBibles.count) English Bibles via proxy")
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