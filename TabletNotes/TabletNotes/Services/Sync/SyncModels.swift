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
    let notes: [NoteSyncPayload]
    let transcript: TranscriptSyncPayload?
    let summary: SummarySyncPayload?
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
    let segments: String?
    let status: String
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
        }
    }
}
