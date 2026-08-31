import Foundation

/// Runtime feature flags (TAB-72).
///
/// A feature replacing a path that handles irreplaceable recordings ships
/// dark: the code is present, reachable and testable in a production build,
/// while every user stays on the legacy path until the shipped default is
/// deliberately flipped per key (durableProcessingPipeline flipped ON in
/// TAB-103 after prod verification). Flipping back is a settings toggle, not
/// a redeploy — which is the whole point of gating rather than cutting over
/// at merge.
/// `@unchecked Sendable` because the only stored property is `UserDefaults`,
/// which is documented as thread-safe but not annotated as `Sendable`.
struct FeatureFlags: @unchecked Sendable {
    /// The only mutable state is UserDefaults; injecting the suite is what makes
    /// flag-dependent behavior testable without touching the user's defaults.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static let shared = FeatureFlags()

    enum Key: String {
        /// Route new recordings through `POST /api/jobs` + the server-side
        /// reaper + Realtime completion, instead of the on-device retry queues.
        /// Shipped default ON since TAB-103 (prod-verified in the TAB-72
        /// closing ledger); the Settings toggle remains the per-device rollback.
        case durableProcessingPipeline = "feature.durableProcessingPipeline"
        /// Upload sermon audio via TUS on a background URLSession (TAB-73 Part B).
        /// Default off — flip only after device airplane-mode / kill-app proof.
        case resumableUploads = "feature.resumableUploads"

        /// What an untouched flag means. Flags ship dark (`false`) until their
        /// rollout decision deliberately flips the shipped default — a stored
        /// value (the user's Settings choice) always wins over this, in either
        /// direction.
        var shippedDefault: Bool {
            switch self {
            case .durableProcessingPipeline: return true
            case .resumableUploads: return false
            }
        }
    }

    /// A stored value is the user's choice and always wins; an unset flag
    /// means the key's shipped default.
    func isEnabled(_ key: Key) -> Bool {
        guard defaults.object(forKey: key.rawValue) != nil else {
            return key.shippedDefault
        }
        return defaults.bool(forKey: key.rawValue)
    }

    func setEnabled(_ enabled: Bool, for key: Key) {
        defaults.set(enabled, forKey: key.rawValue)
    }

    var durableProcessingPipeline: Bool {
        isEnabled(.durableProcessingPipeline)
    }

    var resumableUploads: Bool {
        isEnabled(.resumableUploads)
    }
}
