import Foundation

extension Sermon {
    /// Fallback title for a recording that has no AI-generated title (yet).
    ///
    /// Includes seconds (TAB-54): recordings created in the same minute —
    /// batch recovery imports especially — otherwise collide into identical
    /// titles and read as duplicate rows in the list. The "Sermon on " prefix
    /// is load-bearing for nothing but recognition; processed sermons replace
    /// the whole title with the AI-generated one.
    static func fallbackTitle(for date: Date = Date()) -> String {
        "Sermon on " + DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .medium)
    }
}
