import Foundation
import SwiftData

// MARK: - Bible Translation Model
@Model
class BibleTranslation {
    @Attribute(.unique) var id: String
    var name: String
    var abbreviation: String
    var translationDescription: String?
    var language: String
    var isDefault: Bool
    var createdAt: Date
    
    init(id: String, name: String, abbreviation: String, translationDescription: String? = nil, language: String = "English", isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.translationDescription = translationDescription
        self.language = language
        self.isDefault = isDefault
        self.createdAt = Date()
    }
}

// MARK: - Convenience Extensions
extension BibleTranslation {
    static var defaultTranslations: [BibleTranslation] {
        return [
            BibleTranslation(
                id: "06125adad2d5898a-01",
                name: "King James Version",
                abbreviation: "KJV",
                translationDescription: "The King James Version (KJV), also known as the Authorized Version, is a classic English translation completed in 1611.",
                isDefault: true
            ),
            BibleTranslation(
                id: "90b8dbe0143dd92c-01",
                name: "New American Standard Bible",
                abbreviation: "NASB",
                translationDescription: "The NASB is known for its accuracy to the original Hebrew and Greek texts."
            ),
            BibleTranslation(
                id: "478cdd0b0b6f4567-01",
                name: "New King James Version",
                abbreviation: "NKJV",
                translationDescription: "The NKJV updates the language of the King James Version while maintaining its literary style."
            ),
            BibleTranslation(
                id: "1ae3825917474b65-01",
                name: "New Living Translation",
                abbreviation: "NLT",
                translationDescription: "The NLT provides an easy-to-understand, contemporary English translation."
            )
        ]
    }
}

// MARK: - Identifiable Conformance
extension BibleTranslation: Identifiable {
    // SwiftData @Model already provides id, but we ensure Identifiable conformance
}

// MARK: - Hashable Conformance  
extension BibleTranslation: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: BibleTranslation, rhs: BibleTranslation) -> Bool {
        return lhs.id == rhs.id
    }
}