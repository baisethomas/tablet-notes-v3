import Foundation

/// High-performance markdown cleaner with pre-compiled regex patterns
/// Performance optimization: Regex patterns are compiled once and reused
enum MarkdownCleaner {
    // MARK: - Pre-compiled Regex Patterns (compiled once at app launch)

    private static let headerPattern = try! NSRegularExpression(pattern: #"^#{1,6}\s+"#, options: [])
    private static let boldDoubleStarPattern = try! NSRegularExpression(pattern: #"\*\*([^*]+)\*\*"#, options: [])
    private static let boldUnderscorePattern = try! NSRegularExpression(pattern: #"__([^_]+)__"#, options: [])
    private static let italicSingleStarPattern = try! NSRegularExpression(pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#, options: [])
    private static let italicSingleUnderscorePattern = try! NSRegularExpression(pattern: #"(?<!_)_([^_]+)_(?!_)"#, options: [])
    private static let numberedListPattern = try! NSRegularExpression(pattern: #"^(\d+)\.\s+"#, options: [])
    private static let bulletPointPattern = try! NSRegularExpression(pattern: #"^[\*\-\+]\s+"#, options: [])
    private static let codeBlockPattern = try! NSRegularExpression(pattern: #"```[\s\S]*?```"#, options: [.dotMatchesLineSeparators])
    private static let inlineCodePattern = try! NSRegularExpression(pattern: #"`([^`]+)`"#, options: [])
    private static let linkPattern = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\([^\)]+\)"#, options: [])
    private static let strikethroughPattern = try! NSRegularExpression(pattern: #"~~([^~]+)~~"#, options: [])
    private static let multipleNewlinesPattern = try! NSRegularExpression(pattern: #"\n{3,}"#, options: [])
    private static let multipleSpacesPattern = try! NSRegularExpression(pattern: #" {2,}"#, options: [])

    // MARK: - Public API

    /// Cleans markdown formatting from text using cached regex patterns
    /// - Parameter text: Raw markdown text
    /// - Returns: Plain text with markdown formatting removed
    static func clean(_ text: String) -> String {
        var cleaned = text

        // Remove markdown headers (# ## ###) - process line by line
        let lines = cleaned.components(separatedBy: .newlines)
        cleaned = lines.map { line in
            replace(in: line, using: headerPattern, with: "")
        }.joined(separator: "\n")

        // Remove bold (**text** or __text__) - handle multiline
        cleaned = replace(in: cleaned, using: boldDoubleStarPattern, with: "$1")
        cleaned = replace(in: cleaned, using: boldUnderscorePattern, with: "$1")

        // Remove italic (*text* or _text_) - be careful not to match bold
        cleaned = replace(in: cleaned, using: italicSingleStarPattern, with: "$1")
        cleaned = replace(in: cleaned, using: italicSingleUnderscorePattern, with: "$1")

        // Process numbered lists and bullet points line by line
        let processedLines = cleaned.components(separatedBy: .newlines).map { line in
            var processed = line
            // Convert numbered lists (1. 2. 3.) - keep the number and period
            processed = replace(in: processed, using: numberedListPattern, with: "$1. ")
            // Remove bullet points (* - +) but keep the content
            processed = replace(in: processed, using: bulletPointPattern, with: "")
            return processed
        }
        cleaned = processedLines.joined(separator: "\n")

        // Remove code blocks (```code```)
        cleaned = replace(in: cleaned, using: codeBlockPattern, with: "")

        // Remove inline code (`code`)
        cleaned = replace(in: cleaned, using: inlineCodePattern, with: "$1")

        // Remove links [text](url) - keep just the text
        cleaned = replace(in: cleaned, using: linkPattern, with: "$1")

        // Remove strikethrough (~~text~~)
        cleaned = replace(in: cleaned, using: strikethroughPattern, with: "$1")

        // Clean up extra whitespace (multiple newlines to double newline, multiple spaces to single space)
        cleaned = replace(in: cleaned, using: multipleNewlinesPattern, with: "\n\n")
        cleaned = replace(in: cleaned, using: multipleSpacesPattern, with: " ")

        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    // MARK: - Private Helpers

    /// Performs regex replacement using pre-compiled pattern
    private static func replace(in string: String, using regex: NSRegularExpression, with template: String) -> String {
        let range = NSRange(string.startIndex..., in: string)
        return regex.stringByReplacingMatches(in: string, range: range, withTemplate: template)
    }
}
