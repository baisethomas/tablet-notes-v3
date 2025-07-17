import Foundation

// MARK: - Bible Translation
struct BibleTranslation: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let abbreviation: String
    let description: String
    let language: String
    
    static let kjv = BibleTranslation(
        id: "06125adad2d5898a-01",
        name: "King James Version",
        abbreviation: "KJV",
        description: "Classic English translation from 1611",
        language: "English"
    )
    static let nasb = BibleTranslation(
        id: "bba9f40183526463-01",
        name: "New American Standard Bible",
        abbreviation: "NASB",
        description: "Literal translation with updated language",
        language: "English"
    )
    static let nkjv = BibleTranslation(
        id: "65eec8e0b60e656b-01",
        name: "New King James Version",
        abbreviation: "NKJV",
        description: "Modern update of the classic KJV",
        language: "English"
    )
    static let nlt = BibleTranslation(
        id: "fae2bcaf7bfea3b1-01",
        name: "New Living Translation",
        abbreviation: "NLT",
        description: "Thought-for-thought translation for modern readers",
        language: "English"
    )
    static let gnt = BibleTranslation(
        id: "85eae2b6f4d35b2c-01",
        name: "Good News Translation",
        abbreviation: "GNT",
        description: "Simple, readable English translation",
        language: "English"
    )
    static let cev = BibleTranslation(
        id: "e442e6e6b1d04c96-01",
        name: "Contemporary English Version",
        abbreviation: "CEV",
        description: "Clear and simple English translation",
        language: "English"
    )
    static let web = BibleTranslation(
        id: "9879dbb7cfe39e4d-01",
        name: "World English Bible",
        abbreviation: "WEB",
        description: "Public domain modern English translation",
        language: "English"
    )
    static let allTranslations: [BibleTranslation] = [
        .kjv, .nasb, .nkjv, .nlt, .gnt, .cev, .web
    ]
}

// MARK: - Bible API Configuration
struct BibleAPIConfig {
    static let netlifyBaseURL = "https://comfy-daffodil-7ecc55.netlify.app/.netlify/functions"
    // Default Bible version - King James Version
    static let defaultBibleId = BibleTranslation.kjv.id
    // Get user's preferred Bible translation from UserDefaults
    static var preferredBibleTranslation: BibleTranslation {
        let savedId = UserDefaults.standard.string(forKey: "preferredBibleTranslationId") ?? defaultBibleId
        return BibleTranslation.allTranslations.first { $0.id == savedId } ?? BibleTranslation.kjv
    }
    static func setPreferredBibleTranslation(_ translation: BibleTranslation) {
        UserDefaults.standard.set(translation.id, forKey: "preferredBibleTranslationId")
    }
    struct BibleVersions {
        static let kjv = BibleTranslation.kjv.id
        static let nasb = BibleTranslation.nasb.id
        static let nkjv = BibleTranslation.nkjv.id
        static let nlt = BibleTranslation.nlt.id
        static let gnt = BibleTranslation.gnt.id
        static let cev = BibleTranslation.cev.id
        static let web = BibleTranslation.web.id
    }
}

