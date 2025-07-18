import Foundation
import SwiftData

@Model
final class Sermon {
    @Attribute(.unique) var id: UUID
    var title: String
    var audioFileURL: URL
    var date: Date
    var serviceType: String // Could be enum, but use String for SwiftData compatibility
    var speaker: String? // Speaker name for the sermon
    @Relationship(deleteRule: .cascade) var transcript: Transcript?
    @Relationship(deleteRule: .cascade) var notes: [Note]
    @Relationship(deleteRule: .cascade) var summary: Summary?
    var syncStatus: String // e.g., "localOnly", "syncing", "synced", "error"
    var transcriptionStatus: String // e.g., "processing", "complete", "failed"
    var summaryStatus: String // e.g., "processing", "complete", "failed"
    var isArchived: Bool = false // Whether the sermon is archived
    
    // Sync metadata for cross-device sync
    var lastSyncedAt: Date?
    var remoteId: String? // Supabase row ID for synced items
    var updatedAt: Date?
    var needsSync: Bool = false // Flag to track if local changes need syncing
    
    // User relationship - each sermon belongs to a user
    var userId: UUID? // Foreign key to User - optional for migration compatibility
    @Relationship(inverse: \User.sermons) var user: User?

    init(id: UUID = UUID(), title: String, audioFileURL: URL, date: Date, serviceType: String, speaker: String? = nil, transcript: Transcript? = nil, notes: [Note] = [], summary: Summary? = nil, syncStatus: String = "localOnly", transcriptionStatus: String = "processing", summaryStatus: String = "processing", isArchived: Bool = false, userId: UUID? = nil, lastSyncedAt: Date? = nil, remoteId: String? = nil, updatedAt: Date? = Date(), needsSync: Bool = false) {
        self.id = id
        self.title = title
        self.audioFileURL = audioFileURL
        self.date = date
        self.serviceType = serviceType
        self.speaker = speaker
        self.transcript = transcript
        self.notes = notes
        self.summary = summary
        self.syncStatus = syncStatus
        self.transcriptionStatus = transcriptionStatus
        self.summaryStatus = summaryStatus
        self.isArchived = isArchived
        self.userId = userId
        self.lastSyncedAt = lastSyncedAt
        self.remoteId = remoteId
        self.updatedAt = updatedAt
        self.needsSync = needsSync
    }
} 