import Foundation

// MARK: - API Bible Configuration
// Bible translation identifiers and the user's translation preference.
// API.Bible requests are proxied through the backend (bible-api), which holds
// the key server-side — the client no longer stores an API.Bible key (TAB-48).

struct ApiBibleConfig {
    // MARK: - Bible Identifiers

    /// Default Bible ID — the real King James Version (see `BibleTranslationCatalog`).
    static var defaultBibleId: String { BibleTranslationCatalog.defaultId }

    // MARK: - Preference Management

    /// Sets the preferred Bible translation
    /// - Parameter translationId: The Bible ID to set as preferred
    static func setPreferredBibleTranslation(_ translationId: String) {
        UserDefaults.standard.set(translationId, forKey: "preferredBibleTranslationId")
    }

    /// The preferred Bible translation ID from UserDefaults, or the default.
    ///
    /// The stored value is validated against `BibleTranslationCatalog`: earlier
    /// builds let users pick translation IDs that were mislabeled or not actually
    /// accessible (e.g. "NKJV"/"ESV"/"NLT"). A stale or unsupported stored ID is
    /// migrated in place — the bad key is cleared so subsequent reads resolve to
    /// the (catalog-derived) default rather than re-validating it forever (TAB-51).
    static var preferredBibleTranslationId: String {
        guard let stored = UserDefaults.standard.string(forKey: "preferredBibleTranslationId") else {
            return defaultBibleId
        }
        guard BibleTranslationCatalog.contains(stored) else {
            UserDefaults.standard.removeObject(forKey: "preferredBibleTranslationId")
            return defaultBibleId
        }
        return stored
    }
}

// MARK: - Configuration Status
/*
 API.Bible is proxied through the backend (bible-api); the curated list of
 translations the app offers lives in `BibleTranslationCatalog`.

 Only public-domain / openly-licensed translations are available on the API key
 (KJV, BSB, WEB, ASV, FBV, LSV, GNV). Copyrighted translations (NIV, ESV, NLT,
 NKJV, NASB, CSB) require paid publisher licensing and are intentionally not
 listed — see TAB-51.
 */