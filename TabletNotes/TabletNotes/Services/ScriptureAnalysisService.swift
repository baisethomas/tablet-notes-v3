import Foundation
// If needed, import the module where ScriptureAnalysisServiceProtocol and ScriptureReference are defined
// import TabletNotes

// Import the protocol and struct from the protocol file
// If in the same module, this is sufficient. If not, ensure access control is public.

class ScriptureAnalysisService: ObservableObject, ScriptureAnalysisServiceProtocol {
    // Regex pattern for scripture references (e.g., 'John 3:16', '1 Corinthians 13:4-7')
    private let pattern = #"([1-3]?\s?[A-Za-z]+)\s(\d+):(\d+)(?:-(\d+))?"#
    private lazy var regex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: pattern, options: [])
    }()
    
    func analyzeScriptureReferences(in text: String) -> [ScriptureReference] {
        guard let regex = regex else { return [] }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsrange)
        var results: [ScriptureReference] = []
        for match in matches {
            guard match.numberOfRanges >= 4 else { continue }
            let raw = (text as NSString).substring(with: match.range)
            let book = (text as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            guard let chapter = Int((text as NSString).substring(with: match.range(at: 2))),
                  let verseStart = Int((text as NSString).substring(with: match.range(at: 3))) else { continue }
            var verseEnd: Int? = nil
            if match.numberOfRanges > 4, let range = Range(match.range(at: 4), in: text), !range.isEmpty {
                verseEnd = Int((text as NSString).substring(with: match.range(at: 4)))
            }
            let reference = ScriptureReference(book: book, chapter: chapter, verseStart: verseStart, verseEnd: verseEnd, raw: raw)
            results.append(reference)
        }
        return results
    }
} 