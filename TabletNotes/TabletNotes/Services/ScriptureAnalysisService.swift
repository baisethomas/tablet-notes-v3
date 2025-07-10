import Foundation
// If needed, import the module where ScriptureAnalysisServiceProtocol and ScriptureReference are defined
// import TabletNotes

// Import the protocol and struct from the protocol file
// If in the same module, this is sufficient. If not, ensure access control is public.

class ScriptureAnalysisService: ObservableObject, ScriptureAnalysisServiceProtocol {
    // Enhanced regex patterns for various scripture reference formats
    private let patterns = [
        // Standard format: "John 3:16", "1 Corinthians 13:4-7" (word boundary at start)
        #"(?:^|[^a-zA-Z])([1-3]?\s?[A-Za-z]+(?:\s[A-Za-z]+)?)\s(\d+):(\d+)(?:-(\d+))?"#,
        // Abbreviated format: "Jn 3:16", "1 Cor 13:4-7" (word boundary at start)
        #"(?:^|[^a-zA-Z])([1-3]?\s?[A-Za-z]{2,4}\.?)\s(\d+):(\d+)(?:-(\d+))?"#
    ]
    
    private lazy var regexes: [NSRegularExpression] = {
        patterns.compactMap { pattern in
            try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
    }()
    
    func analyzeScriptureReferences(in text: String) -> [ScriptureReference] {
        var results: Set<ScriptureReference> = []
        var processedRanges: [NSRange] = []
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        
        // Try each regex pattern, but avoid overlapping matches
        for regex in regexes {
            let matches = regex.matches(in: text, options: [], range: nsrange)
            
            for match in matches {
                // Check if this match overlaps with any previously processed range
                let matchRange = match.range
                let overlaps = processedRanges.contains { range in
                    NSIntersectionRange(range, matchRange).length > 0
                }
                
                if !overlaps, let reference = parseMatch(match, in: text) {
                    // Only add if we don't already have this exact reference
                    if !results.contains(where: { existing in
                        existing.book == reference.book &&
                        existing.chapter == reference.chapter &&
                        existing.verseStart == reference.verseStart &&
                        existing.verseEnd == reference.verseEnd
                    }) {
                        results.insert(reference)
                        processedRanges.append(matchRange)
                    }
                }
            }
        }
        
        // Filter out partial matches that are contained within larger matches
        let filteredResults = results.filter { reference in
            !results.contains { other in
                other != reference &&
                other.book == reference.book &&
                other.chapter == reference.chapter &&
                ((other.verseStart <= reference.verseStart && 
                  (other.verseEnd ?? other.verseStart) >= (reference.verseEnd ?? reference.verseStart)))
            }
        }
        
        return Array(filteredResults).sorted { lhs, rhs in
            if lhs.book != rhs.book {
                return lhs.book < rhs.book
            }
            if lhs.chapter != rhs.chapter {
                return lhs.chapter < rhs.chapter
            }
            return lhs.verseStart < rhs.verseStart
        }
    }
    
    private func parseMatch(_ match: NSTextCheckingResult, in text: String) -> ScriptureReference? {
        guard match.numberOfRanges >= 3 else { return nil }
        
        let raw = (text as NSString).substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
        let book = (text as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        
        guard let chapter = Int((text as NSString).substring(with: match.range(at: 2))) else { return nil }
        
        // Check if this is a verse reference or just a chapter reference
        var verseStart: Int = 1
        var verseEnd: Int? = nil
        
        if match.numberOfRanges >= 4 && match.range(at: 3).location != NSNotFound {
            // Has verse number
            guard let verse = Int((text as NSString).substring(with: match.range(at: 3))) else { return nil }
            verseStart = verse
            
            // Check for verse range
            if match.numberOfRanges > 4 && match.range(at: 4).location != NSNotFound {
                verseEnd = Int((text as NSString).substring(with: match.range(at: 4)))
            }
        }
        
        let normalizedBook = normalizeBookName(book)
        return ScriptureReference(
            book: normalizedBook,
            chapter: chapter,
            verseStart: verseStart,
            verseEnd: verseEnd,
            raw: raw
        )
    }
    
    private func normalizeBookName(_ book: String) -> String {
        let normalizedBook = book.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\.", with: "", options: .regularExpression)
        
        // Map common abbreviations to full names
        let bookMappings: [String: String] = [
            "Gen": "Genesis", "Ex": "Exodus", "Exo": "Exodus", "Lev": "Leviticus",
            "Num": "Numbers", "Deut": "Deuteronomy", "Josh": "Joshua", "Judg": "Judges",
            "1 Sam": "1 Samuel", "2 Sam": "2 Samuel", "1 Ki": "1 Kings", "1 Kgs": "1 Kings",
            "2 Ki": "2 Kings", "2 Kgs": "2 Kings", "1 Chr": "1 Chronicles", "2 Chr": "2 Chronicles",
            "Neh": "Nehemiah", "Est": "Esther", "Ps": "Psalms", "Psa": "Psalms",
            "Prov": "Proverbs", "Eccl": "Ecclesiastes", "Song": "Song of Solomon",
            "Isa": "Isaiah", "Jer": "Jeremiah", "Lam": "Lamentations", "Ezek": "Ezekiel",
            "Dan": "Daniel", "Hos": "Hosea", "Obad": "Obadiah", "Jon": "Jonah",
            "Mic": "Micah", "Nah": "Nahum", "Hab": "Habakkuk", "Zeph": "Zephaniah",
            "Hag": "Haggai", "Zech": "Zechariah", "Mal": "Malachi",
            "Matt": "Matthew", "Mk": "Mark", "Lk": "Luke", "Jn": "John",
            "Rom": "Romans", "1 Cor": "1 Corinthians", "2 Cor": "2 Corinthians",
            "Gal": "Galatians", "Eph": "Ephesians", "Phil": "Philippians",
            "Col": "Colossians", "1 Thess": "1 Thessalonians", "2 Thess": "2 Thessalonians",
            "1 Tim": "1 Timothy", "2 Tim": "2 Timothy", "Tit": "Titus",
            "Philem": "Philemon", "Heb": "Hebrews", "Jas": "James", "1 Pet": "1 Peter",
            "2 Pet": "2 Peter", "1 Jn": "1 John", "2 Jn": "2 John", "3 Jn": "3 John",
            "Rev": "Revelation"
        ]
        
        return bookMappings[normalizedBook] ?? normalizedBook
    }
} 