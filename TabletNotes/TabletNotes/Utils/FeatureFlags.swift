import Foundation

/// Runtime feature flags (TAB-72).
///
/// The durable processing pipeline replaces a path that handles irreplaceable
/// recordings, so it ships dark: the code is present, reachable and testable in
/// a production build, but every user stays on the legacy path until the flag is
/// deliberately flipped. Flipping it back is a settings toggle, not a redeploy —
/// which is the whole point of gating it rather than cutting over at merge.
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
        case durableProcessingPipeline = "feature.durableProcessingPipeline"
    }

    /// Defaults to `false` for every flag: an unset flag must never mean "on".
    func isEnabled(_ key: Key) -> Bool {
        defaults.bool(forKey: key.rawValue)
    }

    func setEnabled(_ enabled: Bool, for key: Key) {
        defaults.set(enabled, forKey: key.rawValue)
    }

    var durableProcessingPipeline: Bool {
        isEnabled(.durableProcessingPipeline)
    }
}
