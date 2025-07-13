import Foundation

// MARK: - Bible Translation
struct BibleTranslation: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let abbreviation: String
    let description: String
    let language: String
    
    static let esv = BibleTranslation(
        id: "06125adad2d5898a-01",
        name: "English Standard Version",
        abbreviation: "ESV",
        description: "Literal translation emphasizing word-for-word accuracy",
        language: "English"
    )
    
    static let kjv = BibleTranslation(
        id: "de4e12af7f28f599-02",
        name: "King James Version",
        abbreviation: "KJV",
        description: "Classic English translation from 1611",
        language: "English"
    )
    
    static let niv = BibleTranslation(
        id: "78a9f6124f344018-01",
        name: "New International Version",
        abbreviation: "NIV",
        description: "Balanced approach between word-for-word and thought-for-thought",
        language: "English"
    )
    
    static let nlt = BibleTranslation(
        id: "116f9b6a252c0c0e-01",
        name: "New Living Translation",
        abbreviation: "NLT",
        description: "Thought-for-thought translation for modern readers",
        language: "English"
    )
    
    static let nasb = BibleTranslation(
        id: "f72b840c855f362c-04",
        name: "New American Standard Bible",
        abbreviation: "NASB",
        description: "Literal translation with updated language",
        language: "English"
    )
    
    static let allTranslations: [BibleTranslation] = [
        .esv, .niv, .nlt, .kjv, .nasb
    ]
}

// MARK: - Bible API Configuration
struct BibleAPIConfig {
    static let netlifyBaseURL = "https://comfy-daffodil-7ecc55.netlify.app/.netlify/functions"
    
    // Default Bible version - English Standard Version
    static let defaultBibleId = BibleTranslation.esv.id
    
    // Get user's preferred Bible translation from UserDefaults
    static var preferredBibleTranslation: BibleTranslation {
        let savedId = UserDefaults.standard.string(forKey: "preferredBibleTranslationId") ?? defaultBibleId
        return BibleTranslation.allTranslations.first { $0.id == savedId } ?? BibleTranslation.esv
    }
    
    // Save user's preferred Bible translation to UserDefaults
    static func setPreferredBibleTranslation(_ translation: BibleTranslation) {
        UserDefaults.standard.set(translation.id, forKey: "preferredBibleTranslationId")
    }
    
    // Alternative Bible versions (legacy support)
    struct BibleVersions {
        static let esv = BibleTranslation.esv.id
        static let kjv = BibleTranslation.kjv.id
        static let niv = BibleTranslation.niv.id
        static let nlt = BibleTranslation.nlt.id
        static let nasb = BibleTranslation.nasb.id
    }
}

// MARK: - Bible API Service
class BibleNetlifyAPIService {
    private let netlifyBaseURL = BibleAPIConfig.netlifyBaseURL
    
    func makeRequest(endpoint: String, method: String = "GET") async throws -> [String: Any] {
        guard let url = URL(string: "\(netlifyBaseURL)/bible-api") else {
            throw NSError(domain: "BibleAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authorization header if available
        // This should be set by the app's authentication system
        if let authToken = UserDefaults.standard.string(forKey: "supabase_auth_token") {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        
        let requestBody = [
            "endpoint": endpoint,
            "method": method
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "BibleAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "BibleAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "BibleAPI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"])
        }
        
        guard let apiData = json["data"] as? [String: Any] else {
            throw NSError(domain: "BibleAPI", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing data in response"])
        }
        
        return apiData
    }
}

