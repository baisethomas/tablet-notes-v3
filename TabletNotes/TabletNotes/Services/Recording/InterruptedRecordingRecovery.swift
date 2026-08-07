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

enum InterruptedRecordingRecoveryStore {
    private static let activeRecordingKey = "active_recording_manifest"
    private static let userDefaults = UserDefaults.standard

    static func save(_ manifest: InterruptedRecordingManifest) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        userDefaults.set(data, forKey: activeRecordingKey)
    }

    static func load() -> InterruptedRecordingManifest? {
        guard let data = userDefaults.data(forKey: activeRecordingKey) else { return nil }
        return try? JSONDecoder().decode(InterruptedRecordingManifest.self, from: data)
    }

    static func clear() {
        userDefaults.removeObject(forKey: activeRecordingKey)
    }
}
