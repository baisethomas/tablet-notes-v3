import Foundation

struct CachedTranscriptSnapshot: Codable {
    let transcriptId: UUID
    let text: String
}

enum TranscriptSnapshotStore {
    private static let defaults = UserDefaults.standard
    private static let keyPrefix = "transcript_snapshot_"

    static func save(transcriptId: UUID, text: String, for sermonId: UUID) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            remove(for: sermonId)
            return
        }

        let snapshot = CachedTranscriptSnapshot(transcriptId: transcriptId, text: text)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key(for: sermonId))
    }

    static func snapshot(for sermonId: UUID) -> CachedTranscriptSnapshot? {
        guard let data = defaults.data(forKey: key(for: sermonId)) else { return nil }
        return try? JSONDecoder().decode(CachedTranscriptSnapshot.self, from: data)
    }

    static func remove(for sermonId: UUID) {
        defaults.removeObject(forKey: key(for: sermonId))
    }

    private static func key(for sermonId: UUID) -> String {
        keyPrefix + sermonId.uuidString
    }
}
