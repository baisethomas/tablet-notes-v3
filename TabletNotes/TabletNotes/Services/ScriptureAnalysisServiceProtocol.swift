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
    
    // Parse a reference string into a ScriptureReference
    public static func parse(_ referenceString: String) -> ScriptureReference? {
        // Remove extra whitespace and normalize
        let trimmed = referenceString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Pattern to match references like "John 3:16" or "John 3:16-18"
        let pattern = #"^(\d*\s*[A-Za-z\s]+)\s+(\d+):(\d+)(?:-(\d+))?$"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range) else {
            return nil
        }
        
        // Extract book name
        let bookRange = Range(match.range(at: 1), in: trimmed)
        let book = bookRange.map { String(trimmed[$0]) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // Extract chapter
        let chapterRange = Range(match.range(at: 2), in: trimmed)
        let chapterString = chapterRange.map { String(trimmed[$0]) } ?? ""
        guard let chapter = Int(chapterString) else { return nil }
        
        // Extract start verse
        let verseStartRange = Range(match.range(at: 3), in: trimmed)
        let verseStartString = verseStartRange.map { String(trimmed[$0]) } ?? ""
        guard let verseStart = Int(verseStartString) else { return nil }
        
        // Extract end verse (optional)
        var verseEnd: Int? = nil
        if match.range(at: 4).location != NSNotFound {
            let verseEndRange = Range(match.range(at: 4), in: trimmed)
            let verseEndString = verseEndRange.map { String(trimmed[$0]) } ?? ""
            verseEnd = Int(verseEndString)
        }
        
        return ScriptureReference(
            book: book,
            chapter: chapter,
            verseStart: verseStart,
            verseEnd: verseEnd,
            raw: referenceString
        )
    }
}

public protocol ScriptureAnalysisServiceProtocol {
    /// Analyzes the input text and returns an array of detected scripture references.
    func analyzeScriptureReferences(in text: String) -> [ScriptureReference]
} 