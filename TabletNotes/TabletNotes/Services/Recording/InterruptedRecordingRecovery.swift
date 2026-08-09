import Foundation

// Moved verbatim from RecordingService.swift during the TAB-71 audio-core
// rewrite so the recovery types outlive the service that originally hosted
// them. SermonService's recovery flow (recoverInterruptedRecordingIfNeeded,
// sign-out wipe guard, ownership checks) depends on these exact shapes and
// the "active_recording_manifest" UserDefaults key — do not rename either.

struct InterruptedRecordingManifest: Codable, Equatable {
    let sessionId: String
    let serviceType: String
    let audioFileName: String
    let startedAt: Date
    /// Owner at recording time; recovery is only allowed for the same signed-in user.
    let userId: UUID?
}

/// Persists the "a recording was in progress" manifest.
///
/// The backing `UserDefaults` is injected rather than hardcoded to `.standard`.
/// In the app there is exactly one store (`.shared`, over `.standard`) and the
/// behavior is unchanged; the seam exists because this is process-global state
/// that four test suites read and clear. With Swift Testing's parallelism they
/// were overwriting each other's manifests — a suite calling `clear()` in its
/// setup would wipe a manifest another suite had just written, which is what
/// made `SermonService`'s sign-out guard see (or miss) an interrupted
/// recording at random. Injecting a per-test suite removes the sharing instead
/// of trying to order the sharers.
struct InterruptedRecordingRecoveryStore {
    private static let activeRecordingKey = "active_recording_manifest"
    private let userDefaults: UserDefaults

    /// The app-wide store. Production code resolves this by default, so the
    /// key and its semantics are exactly as before.
    static let shared = InterruptedRecordingRecoveryStore()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func save(_ manifest: InterruptedRecordingManifest) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        userDefaults.set(data, forKey: Self.activeRecordingKey)
    }

    func load() -> InterruptedRecordingManifest? {
        guard let data = userDefaults.data(forKey: Self.activeRecordingKey) else { return nil }
        return try? JSONDecoder().decode(InterruptedRecordingManifest.self, from: data)
    }

    func clear() {
        userDefaults.removeObject(forKey: Self.activeRecordingKey)
    }
}
