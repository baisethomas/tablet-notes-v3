import Foundation

// MARK: - API Bible Configuration
// Bible translation identifiers and the user's translation preference.
// API.Bible requests are proxied through the backend (bible-api), which holds
// the key server-side — the client no longer stores an API.Bible key (TAB-48).

struct ApiBibleConfig {
    // MARK: - Bible Identifiers

    // Default Bible ID (King James Version)
    static let defaultBibleId = "06125adad2d5898a-01"

    // MARK: - Preference Management

    /// Sets the preferred Bible translation
    /// - Parameter translationId: The Bible ID to set as preferred
    static func setPreferredBibleTranslation(_ translationId: String) {
        UserDefaults.standard.set(translationId, forKey: "preferredBibleTranslationId")
    }

    /// Gets the preferred Bible translation ID from UserDefaults, or returns default
    static var preferredBibleTranslationId: String {
        return UserDefaults.standard.string(forKey: "preferredBibleTranslationId") ?? defaultBibleId
    }

    // MARK: - Popular Bible IDs

    struct BibleIDs {
        static let kingJamesVersion = "06125adad2d5898a-01"
        static let newAmericanStandardBible = "90b8dbe0143dd92c-01"
        static let newKingJamesVersion = "478cdd0b0b6f4567-01"
        static let englishStandardVersion = "f72b840c855f362c-04"
        static let newInternationalVersion = "78a9f6124f344018-01"
    }

    // MARK: - Popular English Bibles Array

    /// Array of popular English Bible IDs for fallback when API fails
    static let popularEnglishBibles = [
        BibleIDs.kingJamesVersion,
        BibleIDs.newAmericanStandardBible,
        BibleIDs.newKingJamesVersion,
        BibleIDs.englishStandardVersion,
        BibleIDs.newInternationalVersion,
        "01b29f4b342acc35-01", // New Living Translation
        "463b3b6b37664e71-01", // Good News Translation
        "8bc59cdb7b6e0ed4-01", // Contemporary English Version
        "89c4e5cd-508c-4b83-9da6-26e7dc18b96e"  // World English Bible
    ]
}

// MARK: - Configuration Status
/*
 ✅ API.Bible is fully configured and ready to use!

 Features enabled:
 - Scripture lookup and display
 - Multiple Bible translations (KJV, NASB, NKJV, ESV, NIV, etc.)
 - Bible browser with book/chapter navigation
 - Scripture references in sermon notes
 - Clickable scripture text in summaries
 - Direct Bible verse fetching

 Supported translations:
 - King James Version (KJV)
 - New American Standard Bible (NASB)
 - New King James Version (NKJV)
 - English Standard Version (ESV)
 - New International Version (NIV)
 - New Living Translation (NLT)
 - And more...
 */