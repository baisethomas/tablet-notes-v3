import Foundation
import SwiftData

@Model
final class Note: Codable {
    @Attribute(.unique) var id: UUID
    var text: String
    var timestamp: TimeInterval // seconds into audio
    // Relationship to Sermon omitted for now due to cross-file reference issues
    
    // Sync metadata
    var remoteId: String?
    var updatedAt: Date?
    var needsSync: Bool = false

    init(id: UUID = UUID(), text: String, timestamp: TimeInterval, remoteId: String? = nil, updatedAt: Date? = Date(), needsSync: Bool = false) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.remoteId = remoteId
        self.updatedAt = updatedAt
        self.needsSync = needsSync
    }
    
    // MARK: - Codable Implementation
    enum CodingKeys: String, CodingKey {
        case id, text, timestamp, remoteId, updatedAt, needsSync
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(remoteId, forKey: .remoteId)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encode(needsSync, forKey: .needsSync)
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.text = try container.decode(String.self, forKey: .text)
        self.timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        self.remoteId = try container.decodeIfPresent(String.self, forKey: .remoteId)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        self.needsSync = try container.decode(Bool.self, forKey: .needsSync)
    }
} 