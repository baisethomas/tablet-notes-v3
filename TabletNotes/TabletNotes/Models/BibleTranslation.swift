import Foundation
import SwiftData

// MARK: - Bible Translation Model
// Represents a Bible translation/version available in the app

@Model
class BibleTranslation: Identifiable, Codable {
    @Attribute(.unique) var id: String
    var name: String
    var abbreviation: String
    var translationDescription: String?
    var isDefault: Bool
    var dateAdded: Date
    
    init(id: String, name: String, abbreviation: String, translationDescription: String? = nil, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.translationDescription = translationDescription
        self.isDefault = isDefault
        self.dateAdded = Date()
    }
    
    // MARK: - Codable Implementation
    enum CodingKeys: String, CodingKey {
        case id, name, abbreviation, translationDescription, isDefault, dateAdded
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.abbreviation = try container.decode(String.self, forKey: .abbreviation)
        self.translationDescription = try container.decodeIfPresent(String.self, forKey: .translationDescription)
        self.isDefault = try container.decode(Bool.self, forKey: .isDefault)
        self.dateAdded = try container.decode(Date.self, forKey: .dateAdded)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(abbreviation, forKey: .abbreviation)
        try container.encodeIfPresent(translationDescription, forKey: .translationDescription)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(dateAdded, forKey: .dateAdded)
    }
}

// MARK: - Convenience Extensions
extension BibleTranslation {
    /// Common English Bible translations
    static let commonTranslations: [BibleTranslation] = [
        BibleTranslation(id: "06125adad2d5898a-01", name: "King James Version", abbreviation: "KJV", translationDescription: "Classic English translation from 1611", isDefault: true),
        BibleTranslation(id: "90b8dbe0143dd92c-01", name: "New American Standard Bible", abbreviation: "NASB", translationDescription: "Modern, literal English translation"),
        BibleTranslation(id: "478cdd0b0b6f4567-01", name: "New King James Version", abbreviation: "NKJV", translationDescription: "Modern update of the King James Version"),
        BibleTranslation(id: "1ae3825917474b65-01", name: "New Living Translation", abbreviation: "NLT", translationDescription: "Dynamic, thought-for-thought translation")
    ]
    
    /// Default Bible translation
    static var `default`: BibleTranslation {
        return BibleTranslation(
            id: "06125adad2d5898a-01",
            name: "King James Version",
            abbreviation: "KJV",
            translationDescription: "Classic English translation from 1611",
            isDefault: true
        )
    }
}

// MARK: - Hashable and Equatable
extension BibleTranslation: Hashable, Equatable {
    static func == (lhs: BibleTranslation, rhs: BibleTranslation) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}