import Foundation

/// One scripture reminder for a sermon, before any verse text is fetched (TAB-119).
struct PlannedScriptureReminder: Equatable {
    /// Position in the sermon's run of reminders, starting at 0.
    let index: Int
    let reference: ScriptureReference
    /// A complete, meaningful sentence from the summary, or nil when none qualifies.
    /// The caller falls back to the sermon title when this is nil.
    let message: String?
    /// Local wall-clock delivery time, for `UNCalendarNotificationTrigger`.
    let fireDateComponents: DateComponents
}

/// Decides which scriptures a sermon's reminders show, which summary line goes
/// with each, and which mornings they fire. Pure: no I/O and no notification
/// center, so all of the content rules are unit-tested here.
struct ScriptureReminderPlanner {
    /// Days after the planning day on which reminders fire: four over one week.
    static let dayOffsets = [1, 3, 5, 7]
    static let deliveryHour = 8
    /// Longer sentences are skipped rather than truncated mid-thought.
    static let maxMessageLength = 160
    static let minMessageWords = 5

    private let scriptureAnalyzer: ScriptureAnalysisServiceProtocol

    init(scriptureAnalyzer: ScriptureAnalysisServiceProtocol = ScriptureAnalysisService()) {
        self.scriptureAnalyzer = scriptureAnalyzer
    }

    /// Plans up to four reminders. Returns an empty array when the sermon has no
    /// scripture references: a reminder without a scripture is not sent.
    /// - Parameter now: the planning time; the first reminder fires the next morning.
    func plan(
        summaryText: String,
        transcriptText: String?,
        now: Date,
        calendar: Calendar = .current
    ) -> [PlannedScriptureReminder] {
        let document = SummaryDocument(parsing: summaryText)
        let references = orderedReferences(in: document, transcriptText: transcriptText)
        guard !references.isEmpty else { return [] }

        let messages = meaningfulMessages(in: document)
        let startOfToday = calendar.startOfDay(for: now)

        return references.enumerated().compactMap { index, reference in
            guard let day = calendar.date(byAdding: .day, value: Self.dayOffsets[index], to: startOfToday),
                  let fireDate = calendar.date(bySettingHour: Self.deliveryHour, minute: 0, second: 0, of: day) else {
                return nil
            }
            return PlannedScriptureReminder(
                index: index,
                reference: reference,
                message: index < messages.count ? messages[index] : nil,
                fireDateComponents: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            )
        }
    }

    // MARK: - Scripture selection

    /// Main scripture text first, then the summary's reference list, then the rest
    /// of the summary, then the transcript. First-seen order; overlapping passages
    /// collapse to the first one seen.
    private func orderedReferences(in document: SummaryDocument, transcriptText: String?) -> [ScriptureReference] {
        let limit = Self.dayOffsets.count
        var ordered: [ScriptureReference] = []

        func absorb(_ lines: [String]) {
            for line in lines {
                guard ordered.count < limit else { return }
                for reference in referencesInReadingOrder(in: line) where !ordered.contains(where: { $0.overlaps(reference) }) {
                    ordered.append(reference)
                    if ordered.count == limit { return }
                }
            }
        }

        absorb(document.lines(of: [.mainScripture]))
        absorb(document.lines(of: [.scriptureReferences]))
        absorb(document.lines(excluding: [.mainScripture, .scriptureReferences]))
        if let transcriptText {
            absorb(transcriptText.components(separatedBy: .newlines))
        }
        return ordered
    }

    /// The analyzer is fed one line at a time: across a line break its pattern
    /// reads the previous line's last word as part of the book name and drops
    /// the reference. The same thing happens after any word within a line
    /// ("in Romans 8:28" is dropped), which line splitting cannot fix; that is an
    /// analyzer bug tracked separately. Summaries mostly list references at the
    /// start of a line, so the summary passes are affected far less than the
    /// transcript fallback. The analyzer also sorts by book, so reading order is
    /// restored from where each match sits in the line.
    private func referencesInReadingOrder(in line: String) -> [ScriptureReference] {
        scriptureAnalyzer.analyzeScriptureReferences(in: line).sorted { lhs, rhs in
            position(of: lhs.raw, in: line) < position(of: rhs.raw, in: line)
        }
    }

    private func position(of raw: String, in line: String) -> Int {
        guard let range = line.range(of: raw) else { return Int.max }
        return line.distance(from: line.startIndex, to: range.lowerBound)
    }

    // MARK: - Message selection

    /// Candidate lines in priority order: what to do this week first, then
    /// questions to reflect on, then the teaching itself.
    private static let messageSectionPriority: [SummarySectionKind] = [
        .application, .studyQuestions, .keyPoints, .memorableElements, .overview
    ]

    private func meaningfulMessages(in document: SummaryDocument) -> [String] {
        var messages: [String] = []
        for kind in Self.messageSectionPriority {
            for line in document.lines(of: [kind]) where !document.isPossiblyTruncatedFinalLine(line) {
                for message in Self.meaningfulSentences(in: line) {
                    let isDuplicate = messages.contains { $0.caseInsensitiveCompare(message) == .orderedSame }
                    if !isDuplicate {
                        messages.append(message)
                    }
                }
            }
        }
        return messages
    }

    static func meaningfulSentences(in line: String) -> [String] {
        let plain = plainText(line)
        guard !plain.isEmpty else { return [] }

        return sentences(in: plain).enumerated().compactMap { offset, sentence in
            // A later sentence that opens with a pronoun leans on the one before it.
            if offset > 0 && startsWithDanglingPronoun(sentence.text) { return nil }
            guard isMeaningful(sentence.text) else { return nil }
            return sentence.isTerminated ? sentence.text : sentence.text + "."
        }
    }

    private static let listMarkerPattern = try! NSRegularExpression(pattern: #"^(?:[-*+•>]|\d+[.)])\s+"#)
    private static let leadingLabelPattern = try! NSRegularExpression(pattern: #"^([A-Za-z][A-Za-z &'’/-]{0,40}):\s+"#)

    /// Strips markdown, list markers, and a short leading label such as "Key Quotes:".
    static func plainText(_ line: String) -> String {
        var text = MarkdownCleaner.clean(line)
        text = removingFirstMatch(of: listMarkerPattern, in: text)
        if let match = leadingLabelPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let labelRange = Range(match.range(at: 1), in: text),
           text[labelRange].split(separator: " ").count <= 4 {
            text = removingFirstMatch(of: leadingLabelPattern, in: text)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removingFirstMatch(of regex: NSRegularExpression, in text: String) -> String {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return text
        }
        return text.replacingCharacters(in: range, with: "")
    }

    struct Sentence: Equatable {
        let text: String
        /// False for trailing text with no closing punctuation, such as a bullet.
        let isTerminated: Bool
    }

    private static let sentenceTerminators: Set<Character> = [".", "!", "?"]
    private static let closingMarks: Set<Character> = ["\"", "”", "’", "'", ")"]

    /// Splits on closing punctuation followed by whitespace, never inside a
    /// quotation, so a quoted saying of several sentences stays whole.
    static func sentences(in text: String) -> [Sentence] {
        var result: [Sentence] = []
        var current = ""
        let characters = Array(text)
        var index = 0
        var isInsideQuote = false

        func take(_ character: Character) {
            current.append(character)
            if character == "\"" {
                isInsideQuote.toggle()
            } else if character == "“" {
                isInsideQuote = true
            } else if character == "”" {
                isInsideQuote = false
            }
        }

        while index < characters.count {
            let character = characters[index]
            take(character)
            index += 1
            guard sentenceTerminators.contains(character) else { continue }

            while index < characters.count, closingMarks.contains(characters[index]) {
                take(characters[index])
                index += 1
            }
            if !isInsideQuote && (index == characters.count || characters[index].isWhitespace) {
                let sentence = current.trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty {
                    result.append(Sentence(text: sentence, isTerminated: true))
                }
                current = ""
            }
        }

        let remainder = current.trimmingCharacters(in: .whitespaces)
        if !remainder.isEmpty {
            result.append(Sentence(text: remainder, isTerminated: false))
        }
        return result
    }

    /// Sentences that narrate the sermon or the summary instead of speaking to the reader.
    private static let narrationPrefixes = [
        "in this sermon", "this sermon", "the sermon",
        "in this message", "this message", "the message",
        "in this teaching", "this teaching", "the teaching",
        "the speaker", "the pastor", "the preacher",
        "this is a basic summary", "for a more detailed", "note:"
    ]
    private static let narrationTerms = ["summary", "transcript", "generated offline"]
    private static let danglingPronouns: Set<String> = [
        "it", "this", "that", "these", "those", "they", "he", "she", "his", "her", "their"
    ]
    private static let continuationEndings: Set<Character> = [",", ";", ":", "-", "–", "—", "("]

    static func isMeaningful(_ sentence: String) -> Bool {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maxMessageLength else { return false }
        guard !text.contains("..."), !text.contains("…") else { return false }
        if let last = text.last, continuationEndings.contains(last) { return false }

        // Words carrying no digits, so a bare "Romans 8:28" line never qualifies.
        let words = text.split(whereSeparator: \.isWhitespace)
        let proseWords = words.filter { word in
            word.contains(where: \.isLetter) && !word.contains(where: \.isNumber)
        }
        guard proseWords.count >= minMessageWords else { return false }
        guard text != text.uppercased() else { return false }

        let lowered = text.lowercased()
        if narrationPrefixes.contains(where: { lowered.hasPrefix($0) }) { return false }
        if narrationTerms.contains(where: { lowered.contains($0) }) { return false }

        return hasBalancedQuotes(text)
    }

    private static func startsWithDanglingPronoun(_ sentence: String) -> Bool {
        guard let firstWord = sentence.split(separator: " ").first else { return false }
        let word = firstWord.lowercased().trimmingCharacters(in: .punctuationCharacters)
        return danglingPronouns.contains(word)
    }

    private static func hasBalancedQuotes(_ text: String) -> Bool {
        let straight = text.filter { $0 == "\"" }.count
        let opening = text.filter { $0 == "“" }.count
        let closing = text.filter { $0 == "”" }.count
        return straight % 2 == 0 && opening == closing
    }
}

// MARK: - Summary structure

enum SummarySectionKind: Hashable {
    case mainScripture
    case scriptureReferences
    case application
    case studyQuestions
    case keyPoints
    case memorableElements
    case overview
    /// Sections that are never message sources (structure, deeper dive, notes).
    case excluded
    /// Text before the first recognised heading.
    case other

    private static let namesByKind: [(SummarySectionKind, Set<String>)] = [
        (.mainScripture, ["main scripture text", "main scripture", "main text", "primary scripture",
                          "primary text", "key scripture", "focal scripture", "main passage", "sermon text"]),
        (.scriptureReferences, ["scripture references", "scripture reference", "scriptures",
                                "supporting scriptures", "bible references", "references", "scriptures referenced"]),
        (.application, ["application", "applications", "practical application", "practical applications",
                        "call to action", "takeaway", "takeaways", "key takeaways", "next steps"]),
        (.studyQuestions, ["study questions", "discussion questions", "reflection questions"]),
        (.keyPoints, ["key points", "main points", "key insights", "key teaching points"]),
        (.memorableElements, ["memorable elements", "key quotes", "memorable quotes", "impact statements",
                              "analogies & metaphors", "analogies and metaphors", "stories & testimonies",
                              "stories and testimonies", "pastoral challenges", "memorable phrasing"]),
        (.overview, ["brief summary", "summary", "main theme", "overview", "theme", "big idea"]),
        (.excluded, ["deeper dive", "sermon structure", "related insights", "outline", "note", "notes"])
    ]

    private static let parentheticalPattern = try! NSRegularExpression(pattern: #"\s*\([^)]*\)"#)

    /// The section a heading names, or nil when it is not a known section.
    /// Matching ignores case, markup, a trailing colon and parentheticals such
    /// as "(Comprehensive)".
    static func classify(_ heading: String) -> SummarySectionKind? {
        var name = heading.replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
        name = parentheticalPattern.stringByReplacingMatches(
            in: name, range: NSRange(name.startIndex..., in: name), withTemplate: ""
        )
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasSuffix(":") {
            name.removeLast()
        }
        name = name.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        return namesByKind.first { $0.1.contains(name) }?.0
    }
}

/// A summary split into sections by the headings the summarize prompt asks for.
/// Headings arrive as "**Heading**", "## Heading", a bare line, or inline as
/// "**Heading:** content", so all four forms are recognised.
struct SummaryDocument {
    struct Section {
        let kind: SummarySectionKind
        var lines: [String]
    }

    private(set) var sections: [Section] = []
    /// The document's last line when it lacks closing punctuation, which is what a
    /// response cut off by a token limit looks like.
    private var unterminatedFinalLine: String?

    init(parsing text: String) {
        var current = Section(kind: .other, lines: [])
        var lastContentLine: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.uppercased().hasPrefix("TITLE:") else { continue }

            switch Self.heading(in: line) {
            case .section(let kind, let remainder):
                sections.append(current)
                current = Section(kind: kind, lines: [])
                if let remainder {
                    current.lines.append(remainder)
                    lastContentLine = remainder
                }
            case .subheading:
                continue
            case nil:
                current.lines.append(line)
                lastContentLine = line
            }
        }
        sections.append(current)

        if let lastContentLine,
           let last = lastContentLine.last,
           !".!?\"”’)".contains(last) {
            unterminatedFinalLine = lastContentLine
        }
    }

    func lines(of kinds: Set<SummarySectionKind>) -> [String] {
        sections.filter { kinds.contains($0.kind) }.flatMap(\.lines)
    }

    func lines(excluding kinds: Set<SummarySectionKind>) -> [String] {
        sections.filter { !kinds.contains($0.kind) }.flatMap(\.lines)
    }

    func isPossiblyTruncatedFinalLine(_ line: String) -> Bool {
        line == unterminatedFinalLine
    }

    enum Heading: Equatable {
        /// A known section, with any content that followed the heading on its line.
        case section(SummarySectionKind, remainder: String?)
        /// Marked up as a heading but not a known section: stay in the current section.
        case subheading
    }

    static func heading(in line: String) -> Heading? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") || line.hasPrefix("• ") {
            return nil
        }

        var text = line
        var isMarkedUp = false
        if text.hasPrefix("#") {
            text = String(text.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
            isMarkedUp = true
        }

        if text.hasPrefix("**"),
           let close = text.range(of: "**", range: text.index(text.startIndex, offsetBy: 2)..<text.endIndex) {
            let inner = String(text[text.index(text.startIndex, offsetBy: 2)..<close.lowerBound])
            var rest = String(text[close.upperBound...]).trimmingCharacters(in: .whitespaces)
            let restStartsWithColon = rest.hasPrefix(":")
            if restStartsWithColon {
                rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
            }

            if rest.isEmpty {
                if let kind = SummarySectionKind.classify(inner) {
                    return .section(kind, remainder: nil)
                }
                return .subheading
            }
            // "**Heading:** content" or "**Heading**: content"
            if inner.hasSuffix(":") || restStartsWithColon,
               let kind = SummarySectionKind.classify(inner) {
                return .section(kind, remainder: rest)
            }
            return nil
        }

        if let colon = text.firstIndex(of: ":") {
            let head = String(text[..<colon])
            let tail = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if let kind = SummarySectionKind.classify(head) {
                return .section(kind, remainder: tail.isEmpty ? nil : tail)
            }
        } else if let kind = SummarySectionKind.classify(text) {
            return .section(kind, remainder: nil)
        }

        return isMarkedUp ? .subheading : nil
    }
}

private extension ScriptureReference {
    /// Same book and chapter with intersecting verse ranges.
    func overlaps(_ other: ScriptureReference) -> Bool {
        guard canonicalBook == other.canonicalBook, chapter == other.chapter else {
            return false
        }
        let end = verseEnd ?? verseStart
        let otherEnd = other.verseEnd ?? other.verseStart
        return verseStart <= otherEnd && other.verseStart <= end
    }

    /// The analyzer expands "Ps" to "Psalms" but keeps "Psalm" as written.
    private var canonicalBook: String {
        let lowered = book.lowercased()
        return lowered == "psalms" ? "psalm" : lowered
    }
}
