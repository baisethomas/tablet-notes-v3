import Foundation

public struct ScriptureReference: Identifiable, Equatable {
    public let id = UUID()
    public let book: String
    public let chapter: Int
    public let verseStart: Int
    public let verseEnd: Int?
    public let raw: String
}

public protocol ScriptureAnalysisServiceProtocol {
    /// Analyzes the input text and returns an array of detected scripture references.
    func analyzeScriptureReferences(in text: String) -> [ScriptureReference]
} 