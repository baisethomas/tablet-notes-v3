import Foundation
import SwiftData

@Model
final class Sermon {
    @Attribute(.unique) var id: UUID
    var title: String
    var audioFileName: String // Store just the filename, not the full URL
    var date: Date
    var serviceType: String // Could be enum, but use String for SwiftData compatibility
    var speaker: String? // Speaker name for the sermon
    @Relationship(deleteRule: .cascade) var transcript: Transcript?
    @Relationship(deleteRule: .cascade) var notes: [Note]
    @Relationship(deleteRule: .cascade) var summary: Summary?
    @Relationship(deleteRule: .cascade) var chatMessages: [ChatMessage] = []
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

    // Cache for file existence check (not persisted, recomputed on demand)
    @Transient private var _audioFileExistsCache: (checked: Date, exists: Bool)?
    private static let cacheValidityDuration: TimeInterval = 5.0 // Cache for 5 seconds

    // Computed property to dynamically construct the full audio file URL
    var audioFileURL: URL {
        get {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioPath = documentsPath.appendingPathComponent("AudioRecordings")
            return audioPath.appendingPathComponent(audioFileName)
        }
    }

    // Helper method to check if audio file exists (with caching to reduce I/O)
    var audioFileExists: Bool {
        let now = Date()

        // Return cached value if it's still valid
        if let cache = _audioFileExistsCache,
           now.timeIntervalSince(cache.checked) < Self.cacheValidityDuration {
            return cache.exists
        }

        // Perform actual file check and cache result
        let exists = FileManager.default.fileExists(atPath: audioFileURL.path)
        _audioFileExistsCache = (checked: now, exists: exists)
        return exists
    }

    // Method to invalidate cache (call when file is created/deleted)
    func invalidateFileExistenceCache() {
        _audioFileExistsCache = nil
    }

    // Computed property to count user questions (for usage limit tracking)
    var userQuestionCount: Int {
        return chatMessages.filter { $0.countsTowardLimit }.count
    }

    init(id: UUID = UUID(), title: String, audioFileName: String, date: Date, serviceType: String, speaker: String? = nil, transcript: Transcript? = nil, notes: [Note] = [], summary: Summary? = nil, syncStatus: String = "localOnly", transcriptionStatus: String = "processing", summaryStatus: String = "processing", isArchived: Bool = false, userId: UUID? = nil, lastSyncedAt: Date? = nil, remoteId: String? = nil, updatedAt: Date? = Date(), needsSync: Bool = false) {
        self.id = id
        self.title = title
        self.audioFileName = audioFileName
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
    
    // Convenience initializer that accepts a URL and extracts the filename
    convenience init(id: UUID = UUID(), title: String, audioFileURL: URL, date: Date, serviceType: String, speaker: String? = nil, transcript: Transcript? = nil, notes: [Note] = [], summary: Summary? = nil, syncStatus: String = "localOnly", transcriptionStatus: String = "processing", summaryStatus: String = "processing", isArchived: Bool = false, userId: UUID? = nil, lastSyncedAt: Date? = nil, remoteId: String? = nil, updatedAt: Date? = Date(), needsSync: Bool = false) {
        self.init(
            id: id,
            title: title,
            audioFileName: audioFileURL.lastPathComponent,
            date: date,
            serviceType: serviceType,
            speaker: speaker,
            transcript: transcript,
            notes: notes,
            summary: summary,
            syncStatus: syncStatus,
            transcriptionStatus: transcriptionStatus,
            summaryStatus: summaryStatus,
            isArchived: isArchived,
            userId: userId,
            lastSyncedAt: lastSyncedAt,
            remoteId: remoteId,
            updatedAt: updatedAt,
            needsSync: needsSync
        )
    }
} 