import Foundation

/// Finds scripture references in summary and transcript text (TAB-121).
///
/// Book names are anchored to the known catalog so a preceding word
/// ("in Romans 8:28") is not swallowed. Spoken forms such as
/// "Joshua 14, verse 12" and "Mark's gospel, the 11th chapter, verse 23"
/// normalise to the same `ScriptureReference` as `Book chapter:verse`.
/// `raw` is the matched text so callers can restore reading order.
class ScriptureAnalysisService: ObservableObject, ScriptureAnalysisServiceProtocol {

    private static let catalog: [(canonical: String, aliases: [String])] = [
        ("Genesis", ["Genesis", "Gen"]),
        ("Exodus", ["Exodus", "Exo", "Ex"]),
        ("Leviticus", ["Leviticus", "Lev"]),
        ("Numbers", ["Numbers", "Num"]),
        ("Deuteronomy", ["Deuteronomy", "Deut"]),
        ("Joshua", ["Joshua", "Josh"]),
        ("Judges", ["Judges", "Judg"]),
        ("Ruth", ["Ruth"]),
        ("1 Samuel", ["1 Samuel", "1 Sam"]),
        ("2 Samuel", ["2 Samuel", "2 Sam"]),
        ("1 Kings", ["1 Kings", "1 Kgs", "1 Ki"]),
        ("2 Kings", ["2 Kings", "2 Kgs", "2 Ki"]),
        ("1 Chronicles", ["1 Chronicles", "1 Chr"]),
        ("2 Chronicles", ["2 Chronicles", "2 Chr"]),
        ("Ezra", ["Ezra"]),
        ("Nehemiah", ["Nehemiah", "Neh"]),
        ("Esther", ["Esther", "Est"]),
        ("Job", ["Job"]),
        ("Psalms", ["Psalms", "Psa", "Ps"]),
        ("Psalm", ["Psalm"]),
        ("Proverbs", ["Proverbs", "Prov"]),
        ("Ecclesiastes", ["Ecclesiastes", "Eccl"]),
        ("Song of Solomon", ["Song of Solomon", "Song"]),
        ("Isaiah", ["Isaiah", "Isa"]),
        ("Jeremiah", ["Jeremiah", "Jer"]),
        ("Lamentations", ["Lamentations", "Lam"]),
        ("Ezekiel", ["Ezekiel", "Ezek"]),
        ("Daniel", ["Daniel", "Dan"]),
        ("Hosea", ["Hosea", "Hos"]),
        ("Joel", ["Joel"]),
        ("Amos", ["Amos"]),
        ("Obadiah", ["Obadiah", "Obad"]),
        ("Jonah", ["Jonah", "Jon"]),
        ("Micah", ["Micah", "Mic"]),
        ("Nahum", ["Nahum", "Nah"]),
        ("Habakkuk", ["Habakkuk", "Hab"]),
        ("Zephaniah", ["Zephaniah", "Zeph"]),
        ("Haggai", ["Haggai", "Hag"]),
        ("Zechariah", ["Zechariah", "Zech"]),
        ("Malachi", ["Malachi", "Mal"]),
        ("Matthew", ["Matthew", "Matt"]),
        ("Mark", ["Mark", "Mk"]),
        ("Luke", ["Luke", "Lk"]),
        ("John", ["John", "Jn"]),
        ("Acts", ["Acts"]),
        ("Romans", ["Romans", "Rom"]),
        ("1 Corinthians", ["1 Corinthians", "1 Cor"]),
        ("2 Corinthians", ["2 Corinthians", "2 Cor"]),
        ("Galatians", ["Galatians", "Gal"]),
        ("Ephesians", ["Ephesians", "Eph"]),
        ("Philippians", ["Philippians", "Phil"]),
        ("Colossians", ["Colossians", "Col"]),
        ("1 Thessalonians", ["1 Thessalonians", "1 Thess"]),
        ("2 Thessalonians", ["2 Thessalonians", "2 Thess"]),
        ("1 Timothy", ["1 Timothy", "1 Tim"]),
        ("2 Timothy", ["2 Timothy", "2 Tim"]),
        ("Titus", ["Titus", "Tit"]),
        ("Philemon", ["Philemon", "Philem"]),
        ("Hebrews", ["Hebrews", "Heb"]),
        ("James", ["James", "Jas"]),
        ("1 Peter", ["1 Peter", "1 Pet"]),
        ("2 Peter", ["2 Peter", "2 Pet"]),
        ("1 John", ["1 John", "1 Jn"]),
        ("2 John", ["2 John", "2 Jn"]),
        ("3 John", ["3 John", "3 Jn"]),
        ("Jude", ["Jude"]),
        ("Revelation", ["Revelation", "Rev"])
    ]

    private lazy var regex: NSRegularExpression = {
        let book = Self.bookAlternation
        let pattern = """
        (?<book>\(book))(?:\
        \\s+(?<chColon>\\d+)\\s*:\\s*(?<vsColon>\\d+)(?:-(?<enColon>\\d+))?|\
        \\s*,?\\s+the\\s+(?<chOrd>\\d+)(?:st|nd|rd|th)\\s+chapter\\s*,?\\s+verses?\\s+(?<vsOrd>\\d+)(?:\\s+(?:to|through|-)\\s+(?<enOrd>\\d+))?|\
        \\s+chapter\\s+(?<chWord>\\d+)\\s*,?\\s+verses?\\s+(?<vsWord>\\d+)(?:\\s+(?:to|through|-)\\s+(?<enWord>\\d+))?|\
        \\s+(?<chComma>\\d+)\\s*,\\s+(?:and\\s+(?:let['’]?s\\s+start\\s+at\\s+)?)?verses?\\s+(?<vsComma>\\d+)(?:\\s+(?:to|through|-)\\s+(?<enComma>\\d+))?|\
        \\s+(?<chAnd>\\d+)\\s+and\\s+(?:let['’]?s\\s+start\\s+at\\s+)?verses?\\s+(?<vsAnd>\\d+)(?:\\s+(?:to|through|-)\\s+(?<enAnd>\\d+))?|\
        \\s+(?<chSpace>\\d+)\\s+verses?\\s+(?<vsSpace>\\d+)(?:\\s+(?:to|through|-)\\s+(?<enSpace>\\d+))?\
        )
        """
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static var bookAlternation: String {
        let gospel = #"(?:Matthew|Mark|Luke|John)['’]?s\s+gospel"#
        let aliases = catalog
            .flatMap(\.aliases)
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
        return #"\b(?:\#(gospel)|\#(aliases.joined(separator: "|")))"#
    }

    func analyzeScriptureReferences(in text: String) -> [ScriptureReference] {
        var results: Set<ScriptureReference> = []
        var processedRanges: [NSRange] = []
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)

        for match in regex.matches(in: text, options: [], range: nsrange) {
            let matchRange = match.range
            let overlaps = processedRanges.contains { range in
                NSIntersectionRange(range, matchRange).length > 0
            }

            if !overlaps, let reference = parseMatch(match, in: text) {
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
        let raw = (text as NSString).substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bookRaw = namedString(match, "book", in: text) else { return nil }
        guard isValidBibleBook(bookRaw) else { return nil }

        guard let chapter = firstInt(match, names: ["chColon", "chOrd", "chWord", "chComma", "chAnd", "chSpace"], in: text),
              let verseStart = firstInt(match, names: ["vsColon", "vsOrd", "vsWord", "vsComma", "vsAnd", "vsSpace"], in: text)
        else { return nil }

        let verseEnd = firstInt(match, names: ["enColon", "enOrd", "enWord", "enComma", "enAnd", "enSpace"], in: text)

        return ScriptureReference(
            book: normalizeBookName(bookRaw),
            chapter: chapter,
            verseStart: verseStart,
            verseEnd: verseEnd,
            raw: raw
        )
    }

    private func namedString(_ match: NSTextCheckingResult, _ name: String, in text: String) -> String? {
        let range = match.range(withName: name)
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        return (text as NSString).substring(with: range).trimmingCharacters(in: .whitespaces)
    }

    private func firstInt(_ match: NSTextCheckingResult, names: [String], in text: String) -> Int? {
        for name in names {
            if let value = namedString(match, name, in: text), let number = Int(value) {
                return number
            }
        }
        return nil
    }

    private func normalizeBookName(_ book: String) -> String {
        var trimmed = book.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
        let lower = trimmed.lowercased()
        if lower.hasSuffix(" gospel") {
            trimmed = trimmed.replacingOccurrences(of: "'s gospel", with: "", options: .caseInsensitive)
            trimmed = trimmed.replacingOccurrences(of: "’s gospel", with: "", options: .caseInsensitive)
            trimmed = trimmed.replacingOccurrences(of: "s gospel", with: "", options: .caseInsensitive)
            trimmed = trimmed.trimmingCharacters(in: .whitespaces)
        }

        let folded = trimmed.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if let canonical = Self.aliasToCanonical[folded] {
            return canonical
        }
        return trimmed
    }

    private static let aliasToCanonical: [String: String] = {
        var map: [String: String] = [:]
        for entry in catalog {
            map[entry.canonical.lowercased()] = entry.canonical
            for alias in entry.aliases {
                map[alias.lowercased()] = entry.canonical
            }
        }
        return map
    }()

    private func isValidBibleBook(_ bookName: String) -> Bool {
        let folded = bookName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .lowercased()
        if Self.aliasToCanonical[folded] != nil { return true }
        if folded.hasSuffix(" gospel") {
            let withoutGospel = folded
                .replacingOccurrences(of: "'s gospel", with: "")
                .replacingOccurrences(of: "’s gospel", with: "")
                .replacingOccurrences(of: "s gospel", with: "")
                .trimmingCharacters(in: .whitespaces)
            return Self.aliasToCanonical[withoutGospel] != nil
        }
        return false
    }
}
