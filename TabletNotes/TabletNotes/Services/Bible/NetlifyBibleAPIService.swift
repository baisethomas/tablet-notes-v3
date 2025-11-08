import Foundation
import Combine
import Supabase

// MARK: - Netlify Bible API Service
// This service calls the Netlify Bible API backend instead of directly calling Bible API
class NetlifyBibleAPIService: ObservableObject {
    @Published var availableBibles: [Bible] = []
    @Published var isLoading = false
    
    private let session = URLSession.shared
    // API base URL (loaded from Config.plist)
    private var apiBaseUrl: String {
        return "\(AppConfig.netlifyAPIBaseURL)/api"
    }
    private let supabase: SupabaseClient
    
    init(supabase: SupabaseClient = SupabaseService.shared.client) {
        self.supabase = supabase
        Task {
            try? await loadAvailableBibles()
        }
    }
    
    // MARK: - Public Methods
    
    func loadAvailableBibles() async throws {
        guard let url = URL(string: "\(apiBaseUrl)/bible-api?endpoint=bibles") else {
            throw BibleAPIError.invalidRequest
        }
        
        do {
            // Get authentication token
            let session = try await supabase.auth.session
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await self.session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                throw BibleAPIError.apiError("Failed to load Bible translations")
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let wrappedData = json?["data"] as? [String: Any],
                  let apiData = wrappedData["data"] as? [[String: Any]] else {
                throw BibleAPIError.apiError("Invalid response format")
            }
            
            let biblesData = try JSONSerialization.data(withJSONObject: apiData)
            let bibles = try JSONDecoder().decode([Bible].self, from: biblesData)
            
            await MainActor.run {
                self.availableBibles = bibles
                self.isLoading = false
            }
            
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
            throw BibleAPIError.networkError(error)
        }
    }
    
    func fetchVerse(reference: String, bibleId: String = ApiBibleConfig.defaultBibleId) async throws -> BibleVerse {
        // Use a known working Bible ID or try to get one from available bibles
        let workingBibleId = getWorkingBibleId(bibleId)
        
        // Try different endpoint formats to debug the 404 issue
        // First try: chapters endpoint to get chapter content, then parse verse
        let chapterInfo = parseReferenceForChapter(reference)
        let endpoint = "bibles/\(workingBibleId)/chapters/\(chapterInfo.chapterId)"
        
        guard let url = URL(string: "\(apiBaseUrl)/bible-api?endpoint=\(endpoint)") else {
            throw BibleAPIError.invalidRequest
        }
        
        do {
            // Get authentication token
            let session = try await supabase.auth.session
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await self.session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                throw BibleAPIError.apiError("Failed to fetch verse")
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let wrappedData = json?["data"] as? [String: Any],
                  let chapterData = wrappedData["data"] as? [String: Any] else {
                throw BibleAPIError.apiError("Invalid response format")
            }
            
            // Extract the specific verse from chapter content
            let chapterInfo = parseReferenceForChapter(reference)
            let verseContent = extractVerseFromChapter(chapterData, verseNumber: chapterInfo.verseNumber)
            
            // Create BibleVerse object
            let bookId = String(chapterInfo.chapterId.prefix(3)) // Extract book abbreviation from chapter ID
            return BibleVerse(
                id: chapterInfo.chapterId + ".\(chapterInfo.verseNumber)",
                orgId: workingBibleId,
                bookId: bookId,
                chapterId: chapterInfo.chapterId,
                content: verseContent,
                reference: reference,
                verseCount: 1,
                copyright: chapterData["copyright"] as? String
            )
            
        } catch {
            throw BibleAPIError.networkError(error)
        }
    }
    
    func fetchPassage(reference: String, bibleId: String = ApiBibleConfig.defaultBibleId) async throws -> BiblePassage {
        // Use a known working Bible ID or try to get one from available bibles
        let workingBibleId = getWorkingBibleId(bibleId)
        
        // Try to convert reference to passage ID format (e.g., "JHN.3.16-JHN.3.17")
        let passageId = convertReferenceToPassageId(reference)
        let endpoint = "bibles/\(workingBibleId)/passages/\(passageId)"
        
        guard let url = URL(string: "\(apiBaseUrl)/bible-api?endpoint=\(endpoint)") else {
            throw BibleAPIError.invalidRequest
        }
        
        do {
            // Get authentication token
            let session = try await supabase.auth.session
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await self.session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                throw BibleAPIError.apiError("Failed to fetch passage")
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let wrappedData = json?["data"] as? [String: Any],
                  let passageData = wrappedData["data"] as? [String: Any] else {
                throw BibleAPIError.apiError("Invalid response format")
            }
            
            let content = passageData["content"] as? String ?? ""
            let verseCount = passageData["verseCount"] as? Int ?? 1
            let copyright = passageData["copyright"] as? String
            
            return BiblePassage(
                id: UUID().uuidString,
                orgId: bibleId,
                content: content,
                reference: reference,
                verseCount: verseCount,
                copyright: copyright
            )
            
        } catch {
            throw BibleAPIError.networkError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func convertReferenceToVerseId(_ reference: String) -> String {
        // Convert reference like "John 3:16" to Bible API verse ID format like "JHN.3.16"
        let components = reference.components(separatedBy: " ")
        guard components.count >= 2 else { return reference }
        
        let bookName = components[0]
        let chapterVerse = components[1].replacingOccurrences(of: ":", with: ".")
        
        // Map book names to Bible API abbreviations
        let bookAbbrev = mapBookNameToAbbreviation(bookName)
        return "\(bookAbbrev).\(chapterVerse)"
    }
    
    private func convertReferenceToPassageId(_ reference: String) -> String {
        // Convert reference like "John 3:16-17" to Bible API passage ID format
        if reference.contains("-") {
            let parts = reference.components(separatedBy: "-")
            if parts.count == 2 {
                let startPart = parts[0].trimmingCharacters(in: .whitespaces)
                let endPart = parts[1].trimmingCharacters(in: .whitespaces)
                
                // Handle ranges like "John 3:16-17" where end doesn't include book/chapter
                let startVerseId = convertReferenceToVerseId(startPart)
                let endVerseId: String
                
                if endPart.contains(" ") {
                    // Full reference like "John 3:16-John 3:17"
                    endVerseId = convertReferenceToVerseId(endPart)
                } else {
                    // Just verse number like "John 3:16-17"
                    let startComponents = startPart.components(separatedBy: " ")
                    if startComponents.count >= 2 {
                        let bookName = startComponents[0]
                        let chapter = startComponents[1].components(separatedBy: ":")[0]
                        let endReference = "\(bookName) \(chapter):\(endPart)"
                        endVerseId = convertReferenceToVerseId(endReference)
                    } else {
                        endVerseId = convertReferenceToVerseId(endPart)
                    }
                }
                
                return "\(startVerseId)-\(endVerseId)"
            }
        }
        // If no range, treat as single verse
        return convertReferenceToVerseId(reference)
    }
    
    private func mapBookNameToAbbreviation(_ bookName: String) -> String {
        let bookMappings: [String: String] = [
            "genesis": "GEN", "gen": "GEN",
            "exodus": "EXO", "exo": "EXO", "ex": "EXO",
            "leviticus": "LEV", "lev": "LEV",
            "numbers": "NUM", "num": "NUM",
            "deuteronomy": "DEU", "deut": "DEU", "deu": "DEU",
            "joshua": "JOS", "josh": "JOS", "jos": "JOS",
            "judges": "JDG", "judg": "JDG", "jdg": "JDG",
            "ruth": "RUT", "rut": "RUT",
            "1samuel": "1SA", "1sam": "1SA", "1sa": "1SA",
            "2samuel": "2SA", "2sam": "2SA", "2sa": "2SA",
            "1kings": "1KI", "1ki": "1KI",
            "2kings": "2KI", "2ki": "2KI",
            "1chronicles": "1CH", "1chr": "1CH", "1ch": "1CH",
            "2chronicles": "2CH", "2chr": "2CH", "2ch": "2CH",
            "ezra": "EZR", "ezr": "EZR",
            "nehemiah": "NEH", "neh": "NEH",
            "esther": "EST", "est": "EST",
            "job": "JOB",
            "psalm": "PSA", "psalms": "PSA", "psa": "PSA", "ps": "PSA",
            "proverbs": "PRO", "prov": "PRO", "pro": "PRO",
            "ecclesiastes": "ECC", "eccl": "ECC", "ecc": "ECC",
            "songofsolomon": "SNG", "song": "SNG", "sng": "SNG",
            "isaiah": "ISA", "isa": "ISA",
            "jeremiah": "JER", "jer": "JER",
            "lamentations": "LAM", "lam": "LAM",
            "ezekiel": "EZK", "ezek": "EZK", "ezk": "EZK",
            "daniel": "DAN", "dan": "DAN",
            "hosea": "HOS", "hos": "HOS",
            "joel": "JOL",
            "amos": "AMO", "amo": "AMO",
            "obadiah": "OBA", "obad": "OBA", "oba": "OBA",
            "jonah": "JON", "jon": "JON",
            "micah": "MIC", "mic": "MIC",
            "nahum": "NAM", "nah": "NAM", "nam": "NAM",
            "habakkuk": "HAB", "hab": "HAB",
            "zephaniah": "ZEP", "zeph": "ZEP", "zep": "ZEP",
            "haggai": "HAG", "hag": "HAG",
            "zechariah": "ZEC", "zech": "ZEC", "zec": "ZEC",
            "malachi": "MAL", "mal": "MAL",
            "matthew": "MAT", "matt": "MAT", "mat": "MAT",
            "mark": "MRK", "mk": "MRK", "mrk": "MRK",
            "luke": "LUK", "lk": "LUK", "luk": "LUK",
            "john": "JHN", "jn": "JHN", "jhn": "JHN",
            "acts": "ACT", "act": "ACT",
            "romans": "ROM", "rom": "ROM",
            "1corinthians": "1CO", "1cor": "1CO", "1co": "1CO",
            "2corinthians": "2CO", "2cor": "2CO", "2co": "2CO",
            "galatians": "GAL", "gal": "GAL",
            "ephesians": "EPH", "eph": "EPH",
            "philippians": "PHP", "phil": "PHP", "php": "PHP",
            "colossians": "COL", "col": "COL",
            "1thessalonians": "1TH", "1thess": "1TH", "1th": "1TH",
            "2thessalonians": "2TH", "2thess": "2TH", "2th": "2TH",
            "1timothy": "1TI", "1tim": "1TI", "1ti": "1TI",
            "2timothy": "2TI", "2tim": "2TI", "2ti": "2TI",
            "titus": "TIT", "tit": "TIT",
            "philemon": "PHM", "phlm": "PHM", "phm": "PHM",
            "hebrews": "HEB", "heb": "HEB",
            "james": "JAS", "jas": "JAS",
            "1peter": "1PE", "1pet": "1PE", "1pe": "1PE",
            "2peter": "2PE", "2pet": "2PE", "2pe": "2PE",
            "1john": "1JN", "1jn": "1JN",
            "2john": "2JN", "2jn": "2JN",
            "3john": "3JN", "3jn": "3JN",
            "jude": "JUD", "jud": "JUD",
            "revelation": "REV", "rev": "REV"
        ]
        
        let normalizedName = bookName.lowercased().replacingOccurrences(of: " ", with: "")
        return bookMappings[normalizedName] ?? bookName.uppercased()
    }
    
    private func getWorkingBibleId(_ preferredId: String) -> String {
        // If we have available bibles, use the first English one
        if let firstEnglishBible = availableBibles.first(where: { $0.language.name.lowercased().contains("english") }) {
            return firstEnglishBible.id
        }
        
        // If we have any bibles available, use the first one
        if let firstBible = availableBibles.first {
            return firstBible.id
        }
        
        // Known working Bible IDs based on the original BibleAPIService
        let knownWorkingIds = [
            "685d1470fe4d5c3b-01", // American Standard Version
            "bba9f40183526463-01", // Berean Standard Bible
            "65eec8e0b60e656b-01", // Free Bible Version
            "55212e3cf5d04d49-01"  // Cambridge Paragraph Bible of the KJV
        ]
        
        // Try the preferred ID first if it's in our known working list
        if knownWorkingIds.contains(preferredId) {
            return preferredId
        }
        
        // Otherwise use the first known working ID
        return knownWorkingIds[0]
    }
    
    private func parseReferenceForChapter(_ reference: String) -> (chapterId: String, verseNumber: Int) {
        let components = reference.components(separatedBy: " ")
        guard components.count >= 2 else {
            return (chapterId: reference, verseNumber: 1)
        }
        
        let bookName = components[0]
        let chapterVerse = components[1]
        let bookAbbrev = mapBookNameToAbbreviation(bookName)
        
        if let colonIndex = chapterVerse.firstIndex(of: ":") {
            let chapter = String(chapterVerse[..<colonIndex])
            let verse = String(chapterVerse[chapterVerse.index(after: colonIndex)...])
            return (chapterId: "\(bookAbbrev).\(chapter)", verseNumber: Int(verse) ?? 1)
        } else {
            // Just chapter number, return verse 1
            return (chapterId: "\(bookAbbrev).\(chapterVerse)", verseNumber: 1)
        }
    }
    
    private func extractVerseFromChapter(_ chapterData: [String: Any], verseNumber: Int) -> String {
        // Try to extract verse content from chapter data
        // This will depend on the actual structure of the Bible API response
        
        if let content = chapterData["content"] as? String {
            // If content is HTML/text with verse markers, try to parse
            // For now, return the whole content as fallback
            return content
        }
        
        // Try to find verses array
        if let verses = chapterData["verses"] as? [[String: Any]] {
            // Look for specific verse number
            for verse in verses {
                if let verseNum = verse["number"] as? Int, verseNum == verseNumber,
                   let verseContent = verse["content"] as? String {
                    return verseContent
                }
            }
        }
        
        return "Verse content not available"
    }
}