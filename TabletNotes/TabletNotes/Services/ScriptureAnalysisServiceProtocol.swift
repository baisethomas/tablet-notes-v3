import Foundation

public struct ScriptureReference: Identifiable, Equatable, Hashable {
    public let book: String
    public let chapter: Int
    public let verseStart: Int
    public let verseEnd: Int?
    public let raw: String
    
    // Use a computed ID based on the content for proper deduplication
    public var id: String {
        return displayText
    }
    
    // Additional properties for UI and API integration
    public var displayText: String {
        if let verseEnd = verseEnd {
            return "\(book) \(chapter):\(verseStart)-\(verseEnd)"
        } else {
            return "\(book) \(chapter):\(verseStart)"
        }
    }
    
    public var isRange: Bool {
        return verseEnd != nil && verseEnd! > verseStart
    }
    
    // Custom equality based on content, not raw text
    public static func == (lhs: ScriptureReference, rhs: ScriptureReference) -> Bool {
        return lhs.book == rhs.book &&
               lhs.chapter == rhs.chapter &&
               lhs.verseStart == rhs.verseStart &&
               lhs.verseEnd == rhs.verseEnd
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(book)
        hasher.combine(chapter)
        hasher.combine(verseStart)
        hasher.combine(verseEnd)
    }
}

public protocol ScriptureAnalysisServiceProtocol {
    /// Analyzes the input text and returns an array of detected scripture references.
    func analyzeScriptureReferences(in text: String) -> [ScriptureReference]
} 