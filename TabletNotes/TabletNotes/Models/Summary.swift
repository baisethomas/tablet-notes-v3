import Foundation
import SwiftData

@Model
final class Summary {
    @Attribute(.unique) var id: UUID
    var text: String
    var type: String // e.g., devotional, bullet, theological
    var status: String // e.g., pending, complete, failed
    
    // Refresh tracking
    var refreshCount: Int = 0
    var lastRefreshedAt: Date?
    
    // Sync metadata
    var remoteId: String?
    var updatedAt: Date?
    var needsSync: Bool = false

    init(id: UUID = UUID(), text: String, type: String, status: String, refreshCount: Int = 0, lastRefreshedAt: Date? = nil, remoteId: String? = nil, updatedAt: Date? = Date(), needsSync: Bool = false) {
        self.id = id
        self.text = text
        self.type = type
        self.status = status
        self.refreshCount = refreshCount
        self.lastRefreshedAt = lastRefreshedAt
        self.remoteId = remoteId
        self.updatedAt = updatedAt
        self.needsSync = needsSync
    }
} 