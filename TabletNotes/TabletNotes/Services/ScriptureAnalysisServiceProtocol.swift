import Foundation

public struct ScriptureReference: Identifiable, Equatable, Hashable {
    public let id = UUID()
    public let book: String
    public let chapter: Int
    public let verseStart: Int
    public let verseEnd: Int?
    public let raw: String
    
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