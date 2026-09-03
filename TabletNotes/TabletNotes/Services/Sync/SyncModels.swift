import Foundation

struct SermonSyncData {
    let id: UUID
    let title: String
    let audioFileURL: URL
    let date: Date
    let serviceType: String
    let speaker: String?
    let transcriptionStatus: String
    let summaryStatus: String
    let isArchived: Bool
    let userId: UUID?
    let updatedAt: Date
    let notes: [NoteSyncPayload]?
    let transcript: TranscriptSyncPayload?
    let summary: SummarySyncPayload?
    let scopes: SermonSyncScopes
    /// Epochs at snapshot time (TAB-98). Defaulted so payload-shape tests
    /// that construct SermonSyncData directly need no epoch bookkeeping.
    var epochs: SermonScopeEpochs = .zero
}

/// The per-scope write epochs a push snapshot was built from (TAB-98). The
/// ack compares these against the sermon's current epochs and clears only
/// the scopes that did not change while the push was in flight.
struct SermonScopeEpochs: Equatable {
    let metadata: Int
    let notes: Int
    let transcript: Int
    let summary: Int

    static let zero = SermonScopeEpochs(metadata: 0, notes: 0, transcript: 0, summary: 0)

    init(metadata: Int, notes: Int, transcript: Int, summary: Int) {
        self.metadata = metadata
        self.notes = notes
        self.transcript = transcript
        self.summary = summary
    }

    init(of sermon: Sermon) {
        self.metadata = sermon.metadataSyncEpoch
        self.notes = sermon.notesSyncEpoch
        self.transcript = sermon.transcriptSyncEpoch
        self.summary = sermon.summarySyncEpoch
    }
}

struct SermonSyncScopes: Equatable {
    let metadata: Bool
    let notes: Bool
    let transcript: Bool
    let summary: Bool

    var hasWork: Bool {
        metadata || notes || transcript || summary
    }

    /// Scopes present in both — used to narrow a pushed snapshot's scopes to
    /// the ones the server actually acknowledged (TAB-110).
    func intersection(_ other: SermonSyncScopes) -> SermonSyncScopes {
        SermonSyncScopes(
            metadata: metadata && other.metadata,
            notes: notes && other.notes,
            transcript: transcript && other.transcript,
            summary: summary && other.summary
        )
    }

    static let all = SermonSyncScopes(
        metadata: true,
        notes: true,
        transcript: true,
        summary: true
    )

    /// Sync bookkeeping only (remoteId/lastSyncedAt/syncStatus) — clears no
    /// dirty scopes, so pending local changes still push afterwards.
    static let none = SermonSyncScopes(
        metadata: false,
        notes: false,
        transcript: false,
        summary: false
    )
}

/// Outcome of a remote sermon create. `syncedScopes` reports which scopes the
/// backend actually persisted — a failed child insert stays dirty locally and
/// is re-pushed via update on the next sync (TAB-34).
struct RemoteSermonCreateResult {
    let remoteId: String
    let syncedScopes: SermonSyncScopes
}

struct NoteSyncPayload {
    let id: UUID
    let text: String
    let timestamp: TimeInterval
}

struct TranscriptSyncPayload {
    let id: UUID
    let text: String
}

struct SummarySyncPayload {
    let id: UUID
    let title: String
    let text: String
    let type: String
    let status: String
}

struct RemoteSermonData: Codable {
    let id: String
    let localId: UUID
    let title: String
    let audioFileURL: URL
    let audioFilePath: String?
    let date: Date
    let serviceType: String
    let speaker: String?
    let transcriptionStatus: String
    let summaryStatus: String
    let isArchived: Bool
    let userId: UUID
    let updatedAt: Date
    let notes: [RemoteNoteData]?
    let transcript: RemoteTranscriptData?
    let summary: RemoteSummaryData?
}

struct RemoteNoteData: Codable {
    let id: String
    let localId: UUID
    let text: String
    let timestamp: TimeInterval

    init(id: String, localId: UUID, text: String, timestamp: TimeInterval) {
        self.id = id
        self.localId = localId
        self.text = text
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.localId = try container.decode(UUID.self, forKey: .localId)
        self.text = try container.decode(String.self, forKey: .text)
        self.timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .timestamp) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case id, localId, text, timestamp
    }
}

struct RemoteTranscriptData: Codable {
    let id: String
    let localId: UUID
    let text: String
    /// Unused on pull (`transcriptSnapshot` always imports `segments: []`).
    /// Kept so a leftover string value still round-trips; jsonb arrays/objects
    /// decode as `nil` instead of failing the whole library (TAB-93).
    let segments: String?
    let status: String

    init(id: String, localId: UUID, text: String, segments: String? = nil, status: String) {
        self.id = id
        self.localId = localId
        self.text = text
        self.segments = segments
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        localId = try container.decode(UUID.self, forKey: .localId)
        text = try container.decode(String.self, forKey: .text)
        status = try container.decode(String.self, forKey: .status)
        // Prod `transcripts.segments` is jsonb. A synthesized `String?` throws
        // `Expected to decode String but found an array instead` and aborts
        // the entire `[RemoteSermonData]` pull. Import ignores this field
        // (TAB-40); tolerate any JSON value so one timed transcript cannot
        // drop the library.
        if let value = try? container.decode(String.self, forKey: .segments) {
            segments = value
        } else {
            segments = nil
        }
    }
}

struct RemoteSummaryData: Codable {
    let id: String
    let localId: UUID
    let title: String
    let text: String
    let type: String
    let status: String
}

enum SyncError: LocalizedError {
    case subscriptionRequired
    case networkError
    case dataCorruption
    case conflictResolution
    case remoteAlreadyExists
    case authenticationFailed
    case rateLimited(retryAfter: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .subscriptionRequired:
            return "Sync requires a paid subscription"
        case .remoteAlreadyExists:
            return "Remote sermon already exists"
        case .authenticationFailed:
            return "Authentication failed. Please sign in again."
        case .networkError:
            return "Network connection error during sync"
        case .dataCorruption:
            return "Data corruption detected during sync"
        case .conflictResolution:
            return "Unable to resolve sync conflicts"
        case .rateLimited(let retryAfter):
            return "Rate limited by server; retry after \(Int(retryAfter))s"
        }
    }
}
