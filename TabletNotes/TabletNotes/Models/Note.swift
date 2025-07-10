import Foundation
import SwiftData

@Model
final class Note {
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
} 