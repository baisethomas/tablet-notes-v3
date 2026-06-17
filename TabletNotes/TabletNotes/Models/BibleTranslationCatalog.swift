import Foundation

// MARK: - Curated Bible Translation

/// A Bible translation the app offers in its pickers.
///
/// This is a lightweight, display-only value type — distinct from the
/// `BibleTranslation` SwiftData `@Model`. It is the single source of truth for
/// *which* translations the app advertises, shared by Settings and the in-app
/// Bible browser so both screens always show the same list (TAB-51).
struct CuratedBibleTranslation: Identifiable, Hashable {
    /// API.Bible bible id.
    let id: String
    let abbreviation: String
    let name: String
    let translationDescription: String
}

// MARK: - Bible Translation Catalog

/// The curated, verified list of Bible translations the app offers.
///
/// Why curated rather than "whatever the API returns": API.Bible's key only
/// grants **public-domain / openly-licensed** translations. The popular
/// copyrighted ones (NIV, ESV, NLT, NKJV, NASB, CSB) require paid publisher
/// licensing and are not available — so we ship only translations that actually
/// work, with honest labels. Every id below has been verified to return a
/// complete Bible (OT+NT) from the live API. The live API is still used to fetch
/// verse text; it is no longer used to populate the picker list (TAB-51).
enum BibleTranslationCatalog {

    /// The default translation for new installs: the real King James Version.
    ///
    /// Note: the app historically used `06125adad2d5898a-01` as "KJV", but that
    /// id actually serves the American Standard Version. The real KJV is below.
    static let defaultId = "de4e12af7f28f599-01"

    /// The translations shown in every picker, in display order.
    static let all: [CuratedBibleTranslation] = [
        CuratedBibleTranslation(
            id: "de4e12af7f28f599-01",
            abbreviation: "KJV",
            name: "King James Version",
            translationDescription: "The classic 1611 Authorized Version — the most widely known English translation."
        ),
        CuratedBibleTranslation(
            id: "bba9f40183526463-01",
            abbreviation: "BSB",
            name: "Berean Standard Bible",
            translationDescription: "A modern, highly readable translation — a great everyday alternative to the NIV/ESV."
        ),
        CuratedBibleTranslation(
            id: "9879dbb7cfe39e4d-04",
            abbreviation: "WEB",
            name: "World English Bible",
            translationDescription: "A modern, public-domain update of the American Standard Version in contemporary English."
        ),
        CuratedBibleTranslation(
            id: "06125adad2d5898a-01",
            abbreviation: "ASV",
            name: "American Standard Version",
            translationDescription: "The 1901 American Standard Version — known for its formal, literal accuracy."
        ),
        CuratedBibleTranslation(
            id: "65eec8e0b60e656b-01",
            abbreviation: "FBV",
            name: "Free Bible Version",
            translationDescription: "A clear, easy-to-read translation aimed at natural, modern English."
        ),
        CuratedBibleTranslation(
            id: "01b29f4b342acc35-01",
            abbreviation: "LSV",
            name: "Literal Standard Version",
            translationDescription: "A modern, very literal translation that stays close to the original wording."
        ),
        CuratedBibleTranslation(
            id: "c315fa9f71d4af3a-01",
            abbreviation: "GNV",
            name: "Geneva Bible",
            translationDescription: "The historic 1599 Geneva Bible, predating and influencing the King James Version."
        )
    ]

    /// Whether `id` is one of the offered translations.
    static func contains(_ id: String) -> Bool {
        all.contains { $0.id == id }
    }

    /// The translation for `id`, if it is one we offer.
    static func translation(for id: String) -> CuratedBibleTranslation? {
        all.first { $0.id == id }
    }

    /// A "ABBR - Name" display label for `id`, falling back to the default.
    static func displayName(for id: String) -> String {
        let translation = translation(for: id)
            ?? translation(for: defaultId)
            ?? all[0]
        return "\(translation.abbreviation) - \(translation.name)"
    }
}
