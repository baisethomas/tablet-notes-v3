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
    var summaryPreviewText: String?
    var isArchived: Bool = false // Whether the sermon is archived
    
    // Sync metadata for cross-device sync
    var lastSyncedAt: Date?
    var remoteId: String? // Supabase row ID for synced items
    var updatedAt: Date?
    var needsSync: Bool = false // Flag to track if local changes need syncing
    var metadataNeedsSync: Bool = false
    var notesNeedSync: Bool = false
    var transcriptNeedsSync: Bool = false
    var summaryNeedsSync: Bool = false
    
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

    var hasPendingSyncWork: Bool {
        metadataNeedsSync ||
        notesNeedSync ||
        transcriptNeedsSync ||
        summaryNeedsSync ||
        notes.contains(where: \.needsSync) ||
        transcript?.needsSync == true ||
        summary?.needsSync == true ||
        needsSync
    }

    func markPendingSync(
        metadata: Bool = false,
        notes: Bool = false,
        transcript: Bool = false,
        summary: Bool = false,
        updatedAt: Date = Date()
    ) {
        if metadata {
            metadataNeedsSync = true
        }

        if notes {
            notesNeedSync = true
        }

        if transcript {
            transcriptNeedsSync = true
        }

        if summary {
            summaryNeedsSync = true
        }

        self.updatedAt = updatedAt
        syncStatus = "pending"
        refreshPendingSyncState()
    }

    func clearPendingSync(
        metadata: Bool = false,
        notes: Bool = false,
        transcript: Bool = false,
        summary: Bool = false
    ) {
        if metadata {
            metadataNeedsSync = false
        }

        if notes {
            notesNeedSync = false
        }

        if transcript {
            transcriptNeedsSync = false
        }

        if summary {
            summaryNeedsSync = false
        }

        refreshPendingSyncState()
    }

    func refreshPendingSyncState() {
        needsSync = metadataNeedsSync ||
            notesNeedSync ||
            transcriptNeedsSync ||
            summaryNeedsSync ||
            notes.contains(where: \.needsSync) ||
            transcript?.needsSync == true ||
            summary?.needsSync == true
    }

    // Computed property to count user questions (for usage limit tracking)
    var userQuestionCount: Int {
        return chatMessages.filter { $0.countsTowardLimit }.count
    }

    static func makeSummaryPreview(from text: String) -> String {
        let collapsedWhitespace = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if collapsedWhitespace.isEmpty {
            return "Summary available"
        }

        return String(collapsedWhitespace.prefix(160))
    }

    init(id: UUID = UUID(), title: String, audioFileName: String, date: Date, serviceType: String, speaker: String? = nil, transcript: Transcript? = nil, notes: [Note] = [], summary: Summary? = nil, syncStatus: String = "localOnly", transcriptionStatus: String = "processing", summaryStatus: String = "processing", summaryPreviewText: String? = nil, isArchived: Bool = false, userId: UUID? = nil, lastSyncedAt: Date? = nil, remoteId: String? = nil, updatedAt: Date? = Date(), needsSync: Bool = false, metadataNeedsSync: Bool = false, notesNeedSync: Bool = false, transcriptNeedsSync: Bool = false, summaryNeedsSync: Bool = false) {
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
        self.summaryPreviewText = summaryPreviewText
        self.isArchived = isArchived
        self.userId = userId
        self.lastSyncedAt = lastSyncedAt
        self.remoteId = remoteId
        self.updatedAt = updatedAt
        self.needsSync = needsSync
        self.metadataNeedsSync = metadataNeedsSync
        self.notesNeedSync = notesNeedSync
        self.transcriptNeedsSync = transcriptNeedsSync
        self.summaryNeedsSync = summaryNeedsSync
    }
    
    // Convenience initializer that accepts a URL and extracts the filename
    convenience init(id: UUID = UUID(), title: String, audioFileURL: URL, date: Date, serviceType: String, speaker: String? = nil, transcript: Transcript? = nil, notes: [Note] = [], summary: Summary? = nil, syncStatus: String = "localOnly", transcriptionStatus: String = "processing", summaryStatus: String = "processing", summaryPreviewText: String? = nil, isArchived: Bool = false, userId: UUID? = nil, lastSyncedAt: Date? = nil, remoteId: String? = nil, updatedAt: Date? = Date(), needsSync: Bool = false, metadataNeedsSync: Bool = false, notesNeedSync: Bool = false, transcriptNeedsSync: Bool = false, summaryNeedsSync: Bool = false) {
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
            summaryPreviewText: summaryPreviewText,
            isArchived: isArchived,
            userId: userId,
            lastSyncedAt: lastSyncedAt,
            remoteId: remoteId,
            updatedAt: updatedAt,
            needsSync: needsSync,
            metadataNeedsSync: metadataNeedsSync,
            notesNeedSync: notesNeedSync,
            transcriptNeedsSync: transcriptNeedsSync,
            summaryNeedsSync: summaryNeedsSync
        )
    }
}
