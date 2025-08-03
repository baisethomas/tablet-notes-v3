import Foundation
import Combine

// MARK: - Direct Bible API Service
// This service provides a simplified interface to the Bible API without relying on complex configurations
class DirectBibleAPIService: ObservableObject {
    @Published var availableBibles: [Bible] = []
    @Published var isLoading = false
    
    private let session = URLSession.shared
    
    init() {
        loadAvailableBibles()
    }
    
    // MARK: - Public Methods
    
    func fetchVerse(reference: String, bibleId: String = ApiBibleConfig.defaultBibleId) async throws -> BibleVerse {
        guard ApiBibleConfig.isConfigured else {
            throw BibleAPIError.apiKeyNotConfigured
        }
        
        // Parse the reference to create the API endpoint
        let cleanReference = cleanScriptureReference(reference)
        let url = URL(string: "\(ApiBibleConfig.baseURL)/bibles/\(bibleId)/search?query=\(cleanReference.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        
        guard let url = url else {
            throw BibleAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        ApiBibleConfig.headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw BibleAPIError.invalidResponse
        }
        
        // For now, return a mock verse until we implement full API parsing
        return BibleVerse(
            id: UUID().uuidString,
            orgId: bibleId,
            bookId: "GEN",
            chapterId: "1",
            content: "Scripture content for \(reference) - API integration pending",
            reference: reference,
            verseCount: 1,
            copyright: "Scripture content courtesy of API.Bible"
        )
    }
    
    func fetchPassage(reference: String, bibleId: String = ApiBibleConfig.defaultBibleId) async throws -> BiblePassage {
        guard ApiBibleConfig.isConfigured else {
            throw BibleAPIError.apiKeyNotConfigured
        }
        
        // For now, return a mock passage until we implement full API parsing
        return BiblePassage(
            id: UUID().uuidString,
            orgId: bibleId,
            content: "Scripture passage for \(reference) - API integration pending",
            reference: reference,
            verseCount: 1,
            copyright: "Scripture content courtesy of API.Bible"
        )
    }
    
    // MARK: - Private Methods
    
    private func loadAvailableBibles() {
        // Provide a default set of popular English Bibles
        availableBibles = [
            Bible(
                id: "06125adad2d5898a-01",
                dblId: "kjv",
                abbreviation: "KJV",
                abbreviationLocal: "KJV",
                name: "King James Version",
                nameLocal: "King James Version",
                description: "The King James Version (KJV), also known as the King James Bible or Authorized Version, is an English translation of the Christian Bible.",
                relatedDbl: nil,
                language: Language(id: "eng", name: "English", nameLocal: "English", script: "Latin", scriptDirection: "LTR"),
                countries: [],
                type: "text",
                updatedAt: "2021-01-01T00:00:00.000Z",
                rightsHolder: "Public Domain",
                rightsHolderLocal: nil,
                copyright: "Public Domain"
            ),
            Bible(
                id: "90b8dbe0143dd92c-01",
                dblId: "nasb",
                abbreviation: "NASB",
                abbreviationLocal: "NASB", 
                name: "New American Standard Bible",
                nameLocal: "New American Standard Bible",
                description: "The New American Standard Bible (NASB) is an English translation of the Bible by the Lockman Foundation.",
                relatedDbl: nil,
                language: Language(id: "eng", name: "English", nameLocal: "English", script: "Latin", scriptDirection: "LTR"),
                countries: [],
                type: "text",
                updatedAt: "2021-01-01T00:00:00.000Z",
                rightsHolder: "The Lockman Foundation",
                rightsHolderLocal: nil,
                copyright: "Copyright © 1960, 1962, 1963, 1968, 1971, 1972, 1973, 1975, 1977, 1995 by The Lockman Foundation"
            ),
            Bible(
                id: "478cdd0b0b6f4567-01",
                dblId: "nkjv",
                abbreviation: "NKJV",
                abbreviationLocal: "NKJV",
                name: "New King James Version",
                nameLocal: "New King James Version", 
                description: "The New King James Version (NKJV) is an English translation of the Bible first published in 1982.",
                relatedDbl: nil,
                language: Language(id: "eng", name: "English", nameLocal: "English", script: "Latin", scriptDirection: "LTR"),
                countries: [],
                type: "text",
                updatedAt: "2021-01-01T00:00:00.000Z",
                rightsHolder: "Thomas Nelson",
                rightsHolderLocal: nil,
                copyright: "Copyright © 1982 by Thomas Nelson"
            )
        ]
    }
    
    private func cleanScriptureReference(_ reference: String) -> String {
        // Clean up the reference for API consumption
        return reference
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "–", with: "-") // Replace en dash with hyphen
            .replacingOccurrences(of: "—", with: "-") // Replace em dash with hyphen
    }
}

// MARK: - Bible API Error Types
enum BibleAPIError: LocalizedError {
    case apiKeyNotConfigured
    case invalidURL
    case invalidResponse
    case noDataReceived
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "Bible API key is not configured. Please add your API.Bible key to ApiBibleConfig."
        case .invalidURL:
            return "Invalid URL for Bible API request."
        case .invalidResponse:
            return "Invalid response from Bible API."
        case .noDataReceived:
            return "No data received from Bible API."
        case .parseError:
            return "Failed to parse Bible API response."
        }
    }
}