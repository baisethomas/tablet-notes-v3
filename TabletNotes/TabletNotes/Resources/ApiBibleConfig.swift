import Foundation

// MARK: - API Bible Configuration
// Bible translation identifiers and the user's translation preference.
// API.Bible requests are proxied through the backend (bible-api), which holds
// the key server-side — the client no longer stores an API.Bible key (TAB-48).

struct ApiBibleConfig {
    // MARK: - Bible Identifiers

    /// Default Bible ID — the real King James Version (see `BibleTranslationCatalog`).
    static var defaultBibleId: String { BibleTranslationCatalog.defaultId }

    // MARK: - Storage Keys

    private static let preferenceKey = "preferredBibleTranslationId"
    private static let migrationVersionKey = "bibleTranslationMigrationVersion"
    private static let currentMigrationVersion = 1

    /// The id the app historically stored as "KJV". It actually serves the
    /// American Standard Version and is a valid catalog entry today (as ASV),
    /// so it must be migrated by a one-time versioned pass rather than by the
    /// validity check below — see `runMigrationsIfNeeded()`.
    private static let legacyKjvBibleId = "06125adad2d5898a-01"

    // MARK: - Preference Management

    /// Sets the preferred Bible translation
    /// - Parameter translationId: The Bible ID to set as preferred
    static func setPreferredBibleTranslation(_ translationId: String) {
        UserDefaults.standard.set(translationId, forKey: preferenceKey)
    }

    /// The preferred Bible translation ID from UserDefaults, or the default.
    ///
    /// The stored value is validated against `BibleTranslationCatalog`: earlier
    /// builds let users pick translation IDs that were mislabeled or not actually
    /// accessible (e.g. "NKJV"/"ESV"/"NLT"). A stale or unsupported stored ID is
    /// cleared in place so subsequent reads resolve to the (catalog-derived)
    /// default rather than re-validating it forever (TAB-51).
    ///
    /// This getter is the single read choke point, so it also drives the
    /// one-time versioned migration of the legacy "KJV" alias.
    static var preferredBibleTranslationId: String {
        runMigrationsIfNeeded()

        guard let stored = UserDefaults.standard.string(forKey: preferenceKey) else {
            return defaultBibleId
        }
        guard BibleTranslationCatalog.contains(stored) else {
            UserDefaults.standard.removeObject(forKey: preferenceKey)
            return defaultBibleId
        }
        return stored
    }

    /// Runs one-time, versioned preference migrations. Idempotent: gated on a
    /// stored version counter so each migration runs at most once per install,
    /// and so deliberate later selections are never re-clobbered.
    private static func runMigrationsIfNeeded() {
        let defaults = UserDefaults.standard
        let version = defaults.integer(forKey: migrationVersionKey) // 0 when unset
        guard version < currentMigrationVersion else { return }

        // v1: the old default/"KJV" option stored `06125adad2d5898a-01`, which
        // actually serves ASV. Those users intended KJV, so repoint them to the
        // real KJV id — but only this once. After the version flag is set, a
        // deliberate ASV selection (same id) persists normally and is left alone.
        if version < 1,
           defaults.string(forKey: preferenceKey) == legacyKjvBibleId {
            defaults.set(BibleTranslationCatalog.defaultId, forKey: preferenceKey)
        }

        defaults.set(currentMigrationVersion, forKey: migrationVersionKey)
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