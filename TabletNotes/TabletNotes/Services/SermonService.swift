import Foundation
import SwiftData
import Combine
import Observation

extension Sermon: Identifiable {}
extension Transcript: Identifiable {}
extension Note: Identifiable {}
extension Summary: Identifiable {}

enum SortOption: String, CaseIterable {
    case newest = "Newest First"
    case oldest = "Oldest First"
}

@MainActor
@Observable
class SermonService {
    private let modelContext: ModelContext
    private let authManager: AuthenticationManager
    private var syncService: (any SyncServiceProtocol)?
    private var subscriptionService: (any SubscriptionServiceProtocol)?
    private(set) var sermons: [Sermon] = []
    private(set) var filteredSermons: [Sermon] = []
    var limitReachedMessage: String?
    var searchText: String = "" {
        didSet {
            applyFilters()
        }
    }
    var sortOption: SortOption = .newest {
        didSet {
            applyFilters()
        }
    }
    var showArchivedSermons: Bool = false {
        didSet {
            applyFilters()
        }
    }

    init(modelContext: ModelContext, authManager: AuthenticationManager? = nil, syncService: (any SyncServiceProtocol)? = nil, subscriptionService: (any SubscriptionServiceProtocol)? = nil) {
        self.modelContext = modelContext
        self.authManager = authManager ?? AuthenticationManager.shared
        self.syncService = syncService
        self.subscriptionService = subscriptionService
        fetchSermons()

        // Listen for auth state changes to refresh sermons
        Task { @MainActor in
            setupAuthStateObserver()
        }
    }

    // Allow injecting sync service after initialization
    func setSyncService(_ syncService: any SyncServiceProtocol) {
        self.syncService = syncService
        print("[SermonService] SyncService injected")
    }
    
    @MainActor
    private func setupAuthStateObserver() {
        // Refresh sermons when auth state changes
        authManager.$authStatePublished
            .sink { [weak self] authState in
                Task { @MainActor in
                    self?.fetchSermons()
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()

    private struct TranscriptSegmentSnapshot {
        let id: UUID
        let text: String
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

    private struct TranscriptSnapshot {
        let id: UUID
        let text: String
        let segments: [TranscriptSegmentSnapshot]
        let remoteId: String?
        let updatedAt: Date?
        let needsSync: Bool
    }

    private struct SummarySnapshot {
        let id: UUID
        let title: String
        let text: String
        let type: String
        let status: String
        let remoteId: String?
        let updatedAt: Date?
        let needsSync: Bool
    }

    private struct NoteSnapshot {
        let id: UUID
        let text: String
        let timestamp: TimeInterval
        let remoteId: String?
    }

    private func makeTranscriptSnapshot(from transcript: Transcript?) -> TranscriptSnapshot? {
        guard let transcript else { return nil }

        let segments = transcript.segments.map { segment in
            TranscriptSegmentSnapshot(
                id: segment.id,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime
            )
        }

        return TranscriptSnapshot(
            id: transcript.id,
            text: transcript.text,
            segments: segments,
            remoteId: transcript.remoteId,
            updatedAt: transcript.updatedAt,
            needsSync: transcript.needsSync
        )
    }

    private func makeSummarySnapshot(from summary: Summary?) -> SummarySnapshot? {
        guard let summary else { return nil }

        return SummarySnapshot(
            id: summary.id,
            title: summary.title,
            text: summary.text,
            type: summary.type,
            status: summary.status,
            remoteId: summary.remoteId,
            updatedAt: summary.updatedAt,
            needsSync: summary.needsSync
        )
    }

    private func makeNoteSnapshots(from notes: [Note]) -> [NoteSnapshot] {
        notes.map { note in
            NoteSnapshot(
                id: note.id,
                text: note.text,
                timestamp: note.timestamp,
                remoteId: note.remoteId
            )
        }
    }

    private func makeTranscriptSnapshot(
        text: String,
        segments: [TranscriptSegment],
        existingTranscript: Transcript?
    ) -> TranscriptSnapshot {
        let segmentSnapshots = segments.map { segment in
            TranscriptSegmentSnapshot(
                id: segment.id,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime
            )
        }

        return TranscriptSnapshot(
            id: existingTranscript?.id ?? UUID(),
            text: text,
            segments: segmentSnapshots,
            remoteId: existingTranscript?.remoteId,
            updatedAt: Date(),
            needsSync: true
        )
    }

    private func findSermon(by id: UUID) -> Sermon? {
        if let sermon = sermons.first(where: { $0.id == id }) {
            return sermon
        }

        let fetchDescriptor = FetchDescriptor<Sermon>(predicate: #Predicate { sermon in
            sermon.id == id
        })
        return try? modelContext.fetch(fetchDescriptor).first
    }

    private func transcriptMatches(_ existing: Transcript?, snapshot: TranscriptSnapshot?) -> Bool {
        switch (existing, snapshot) {
        case (nil, nil):
            return true
        case let (existing?, snapshot?):
            guard existing.text == snapshot.text,
                  existing.remoteId == snapshot.remoteId,
                  existing.segments.count == snapshot.segments.count else {
                return false
            }

            return zip(existing.segments, snapshot.segments).allSatisfy { segment, snapshot in
                segment.id == snapshot.id &&
                segment.text == snapshot.text &&
                segment.startTime == snapshot.startTime &&
                segment.endTime == snapshot.endTime
            }
        default:
            return false
        }
    }

    @discardableResult
    private func applyTranscriptSnapshot(_ snapshot: TranscriptSnapshot?, to sermon: Sermon) -> Bool {
        if transcriptMatches(sermon.transcript, snapshot: snapshot) {
            return false
        }

        guard let snapshot else {
            if let existingTranscript = sermon.transcript {
                sermon.transcript = nil
                modelContext.delete(existingTranscript)
            }
            return true
        }

        let newSegments = snapshot.segments.map { segment in
            TranscriptSegment(
                id: segment.id,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime
            )
        }

        if let existingTranscript = sermon.transcript {
            let oldSegments = Array(existingTranscript.segments)
            existingTranscript.segments.removeAll()
            for segment in oldSegments {
                modelContext.delete(segment)
            }

            existingTranscript.text = snapshot.text
            existingTranscript.segments = newSegments
            existingTranscript.remoteId = snapshot.remoteId
            existingTranscript.updatedAt = snapshot.updatedAt
            existingTranscript.needsSync = snapshot.needsSync
            return true
        }

        let transcript = Transcript(
            id: snapshot.id,
            text: snapshot.text,
            segments: newSegments,
            remoteId: snapshot.remoteId,
            updatedAt: snapshot.updatedAt,
            needsSync: snapshot.needsSync
        )
        modelContext.insert(transcript)
        sermon.transcript = transcript
        return true
    }

    private func summaryMatches(_ existing: Summary?, snapshot: SummarySnapshot?) -> Bool {
        switch (existing, snapshot) {
        case (nil, nil):
            return true
        case let (existing?, snapshot?):
            return existing.title == snapshot.title &&
                existing.text == snapshot.text &&
                existing.type == snapshot.type &&
                existing.status == snapshot.status &&
                existing.remoteId == snapshot.remoteId
        default:
            return false
        }
    }

    @discardableResult
    private func applySummarySnapshot(_ snapshot: SummarySnapshot?, to sermon: Sermon) -> Bool {
        if summaryMatches(sermon.summary, snapshot: snapshot) {
            return false
        }

        guard let snapshot else {
            if let existingSummary = sermon.summary {
                sermon.summary = nil
                modelContext.delete(existingSummary)
            }
            sermon.summaryPreviewText = nil
            return true
        }

        if let existingSummary = sermon.summary {
            existingSummary.title = snapshot.title
            existingSummary.text = snapshot.text
            existingSummary.type = snapshot.type
            existingSummary.status = snapshot.status
            existingSummary.remoteId = snapshot.remoteId
            existingSummary.updatedAt = snapshot.updatedAt
            existingSummary.needsSync = snapshot.needsSync
            sermon.summaryPreviewText = Sermon.makeSummaryPreview(from: snapshot.text)
            return true
        }

        let summary = Summary(
            id: snapshot.id,
            title: snapshot.title,
            text: snapshot.text,
            type: snapshot.type,
            status: snapshot.status,
            remoteId: snapshot.remoteId,
            updatedAt: snapshot.updatedAt,
            needsSync: snapshot.needsSync
        )
        modelContext.insert(summary)
        sermon.summary = summary
        sermon.summaryPreviewText = Sermon.makeSummaryPreview(from: snapshot.text)
        return true
    }

    @discardableResult
    private func applyNoteSnapshots(_ snapshots: [NoteSnapshot], to sermon: Sermon) -> Bool {
        var notesChanged = false
        let snapshotIDs = Set(snapshots.map(\.id))
        let removedNotes = sermon.notes.filter { !snapshotIDs.contains($0.id) }

        if !removedNotes.isEmpty {
            let removedIDs = Set(removedNotes.map(\.id))
            sermon.notes.removeAll { removedIDs.contains($0.id) }
            for note in removedNotes {
                modelContext.delete(note)
            }
            notesChanged = true
        }

        let existingNotesByID = Dictionary(uniqueKeysWithValues: sermon.notes.map { ($0.id, $0) })

        for snapshot in snapshots {
            if let existingNote = existingNotesByID[snapshot.id] {
                let noteChanged =
                    existingNote.text != snapshot.text ||
                    existingNote.timestamp != snapshot.timestamp ||
                    existingNote.remoteId != snapshot.remoteId

                if noteChanged {
                    existingNote.text = snapshot.text
                    existingNote.timestamp = snapshot.timestamp
                    existingNote.remoteId = snapshot.remoteId
                    existingNote.updatedAt = Date()
                    existingNote.needsSync = sermon.remoteId != nil
                    notesChanged = true
                }
                continue
            }

            let note = Note(
                id: snapshot.id,
                text: snapshot.text,
                timestamp: snapshot.timestamp,
                remoteId: snapshot.remoteId,
                updatedAt: Date(),
                needsSync: sermon.remoteId != nil
            )
            note.sermon = sermon
            modelContext.insert(note)
            sermon.notes.append(note)
            notesChanged = true
        }

        return notesChanged
    }

    func saveSermon(title: String, audioFileURL: URL, date: Date, serviceType: String, speaker: String? = nil, transcript: Transcript?, notes: [Note], summary: Summary?, transcriptionStatus: String = "processing", summaryStatus: String = "processing", isArchived: Bool = false, id: UUID? = nil, completion: ((UUID) -> Void)? = nil) {
        print("[SermonService] saveSermon called with title: \(title), date: \(date), serviceType: \(serviceType)")
        
        Task { @MainActor in
            // Ensure user is authenticated
            guard let currentUser = authManager.currentUser else {
                print("[SermonService] ERROR: No authenticated user found. Cannot save sermon.")
                limitReachedMessage = "Please sign in to save sermons"
                return
            }
            
            // Check if this is a new sermon (not an update)
            let sermonID = id ?? UUID()
            let isNewSermon = !sermons.contains { $0.id == sermonID }
            
            // Check usage limits for new sermons
            if isNewSermon && !currentUser.canCreateNewRecording() {
                if let remaining = currentUser.remainingRecordings() {
                    limitReachedMessage = "Recording limit reached! You have \(remaining) recordings remaining this month. Upgrade to Pro for unlimited recordings."
                } else {
                    limitReachedMessage = "Recording limit reached! Upgrade to Pro for unlimited recordings."
                }
                return
            }
            
            // Clear any previous limit messages
            limitReachedMessage = nil
            
            print("[SermonService] Saving sermon for user: \(currentUser.name) (ID: \(currentUser.id))")

            // Add debugging for notes
            print("[DEBUG] saveSermon: Processing \(notes.count) notes")
            for (index, note) in notes.enumerated() {
                print("[DEBUG] Note \(index): '\(note.text)' at \(note.timestamp)s, id: \(note.id)")
            }

            let noteSnapshots = makeNoteSnapshots(from: notes)
            let transcriptSnapshot = makeTranscriptSnapshot(from: transcript)
            let summarySnapshot = makeSummarySnapshot(from: summary)
            var metadataChangedForSync = isNewSermon
            var notesChangedForSync = isNewSermon && !noteSnapshots.isEmpty
            var transcriptChangedForSync = isNewSermon && transcriptSnapshot != nil
            var summaryChangedForSync = isNewSermon && summarySnapshot != nil

            if let existing = sermons.first(where: { $0.id == sermonID }) {
                // Update existing sermon
                let metadataChanged =
                    existing.title != title ||
                    existing.audioFileName != audioFileURL.lastPathComponent ||
                    existing.date != date ||
                    existing.serviceType != serviceType ||
                    existing.speaker != speaker ||
                    existing.transcriptionStatus != transcriptionStatus ||
                    existing.summaryStatus != summaryStatus ||
                    existing.isArchived != isArchived ||
                    existing.userId != currentUser.id

                existing.title = title
                existing.audioFileName = audioFileURL.lastPathComponent
                existing.date = date
                existing.serviceType = serviceType
                existing.speaker = speaker
                let transcriptChanged = applyTranscriptSnapshot(transcriptSnapshot, to: existing)
                let notesChanged = applyNoteSnapshots(noteSnapshots, to: existing)
                let summaryChanged = applySummarySnapshot(summarySnapshot, to: existing)
                existing.transcriptionStatus = transcriptionStatus
                existing.summaryStatus = summaryStatus
                existing.isArchived = isArchived
                existing.userId = currentUser.id
                print("[DEBUG] saveSermon: updated existing sermon \(existing.id) with \(existing.notes.count) notes for user \(currentUser.id)")

                metadataChangedForSync = metadataChanged
                notesChangedForSync = notesChanged
                transcriptChangedForSync = transcriptChanged
                summaryChangedForSync = summaryChanged
            } else {
                // For new sermons: Create sermon, insert it, then add notes with explicit relationship
                let sermon = Sermon(
                    id: sermonID,
                    title: title,
                    audioFileURL: audioFileURL,
                    date: date,
                    serviceType: serviceType,
                    speaker: speaker,
                    transcript: nil,
                    notes: [], // Start empty, add notes after insertion
                    summary: nil,
                    syncStatus: "localOnly",
                    transcriptionStatus: transcriptionStatus,
                    summaryStatus: summaryStatus,
                    isArchived: isArchived,
                    userId: currentUser.id
                )
                
                // Insert sermon first
                modelContext.insert(sermon)

                // Create related models inside this ModelContext to avoid detached @Model relationships.
                transcriptChangedForSync = applyTranscriptSnapshot(transcriptSnapshot, to: sermon)
                summaryChangedForSync = applySummarySnapshot(summarySnapshot, to: sermon)
                notesChangedForSync = applyNoteSnapshots(noteSnapshots, to: sermon)
                
                // Verify relationship is set up correctly
                print("[DEBUG] saveSermon: inserted new sermon \(sermon.id) with \(sermon.notes.count) notes for user \(currentUser.id)")
                for (index, note) in sermon.notes.enumerated() {
                    print("[DEBUG]   Note \(index) ID: \(note.id), text: '\(note.text)', sermon ref: \(note.sermon?.id.uuidString ?? "nil")")
                }
            }
            do {
                try modelContext.save()
                print("[SermonService] Sermon inserted/updated and modelContext saved.")
                
                // IMMEDIATE VERIFICATION: Query the sermon directly from model context
                let verifyDescriptor = FetchDescriptor<Sermon>(predicate: #Predicate { sermon in
                    sermon.id == sermonID
                })
                if let verifiedSermon = try? modelContext.fetch(verifyDescriptor).first {
                    print("[DEBUG] IMMEDIATE VERIFY: Sermon \(verifiedSermon.id) has \(verifiedSermon.notes.count) notes")
                    for (index, note) in verifiedSermon.notes.enumerated() {
                        print("[DEBUG] IMMEDIATE VERIFY Note \(index): '\(note.text)' at \(note.timestamp)s, sermon=\(note.sermon?.id.uuidString ?? "nil")")
                    }
                } else {
                    print("[DEBUG] IMMEDIATE VERIFY: Could not find sermon \(sermonID) after save!")
                }
            } catch {
                print("[SermonService] ERROR: Failed to save modelContext: \(error)")
            }

            // Refresh the sermons array to ensure UI has latest data
            fetchSermons()

            // Track usage for new sermons
            if isNewSermon {
                subscriptionService?.incrementRecordingCount()

                // Calculate audio file size and update storage usage
                if let fileSize = getFileSize(audioFileURL) {
                    let fileSizeGB = Double(fileSize) / 1_073_741_824 // Convert bytes to GB
                    subscriptionService?.incrementStorageUsage(fileSizeGB)
                }
            }

            // ALWAYS trigger sync for ALL sermons (new or updated) if user has sync enabled
            // This ensures notes, transcripts, and summaries are synced
            if let currentUser = authManager.currentUser, currentUser.canSync {
                print("[SermonService] Marking sermon \(sermonID) for sync (isNew: \(isNewSermon))")
                markSermonForSync(
                    sermonID,
                    metadata: metadataChangedForSync,
                    notes: notesChangedForSync,
                    transcript: transcriptChangedForSync,
                    summary: summaryChangedForSync
                )
                triggerSyncIfNeeded()
            }
            
            fetchSermons()

            // Notify caller that save is complete
            completion?(sermonID)
        }
    }

    func fetchSermons() {
        print("[SermonService] fetchSermons called.")

        // IMPORTANT: This runs synchronously on @MainActor (no Task wrapper) so that
        // notes relationships are force-loaded BEFORE any @Observable-triggered re-render.
        // A deferred Task would allow the view to re-render with faulted/empty notes first.

        // If no user is authenticated, show all sermons (for migration compatibility)
        guard let currentUser = authManager.currentUser else {
            print("[SermonService] No authenticated user - fetching all sermons")
            let fetchDescriptor = FetchDescriptor<Sermon>()
            if let results = try? modelContext.fetch(fetchDescriptor) {
                // Force-load relationship-backed data BEFORE assigning to sermons.
                // Assignment triggers @Observable, and views must see loaded relationships.
                for sermon in results {
                    let _ = sermon.notes.count
                    let _ = Array(sermon.notes)
                }
                sermons = results
                print("[SermonService] sermons fetched (no user filter): \(sermons.map { $0.title })")
            } else {
                sermons = []
            }
            applyFilters()
            return
        }

        print("[SermonService] Fetching sermons for user: \(currentUser.name) (ID: \(currentUser.id))")

        // First, migrate any existing sermons without userId to current user
        migrateExistingSermons(to: currentUser.id)

        // Migrate any sermons that still have absolute URLs to relative filenames
        migrateAudioFilePaths()

        // Check for recoverable audio files after database operations are complete
        checkForRecoverableAudioFiles()

        // Create predicate to filter by userId
        let userIdToMatch = currentUser.id
        let predicate = #Predicate<Sermon> { sermon in
            sermon.userId == userIdToMatch
        }

        let fetchDescriptor = FetchDescriptor<Sermon>(predicate: predicate)

        if let results = try? modelContext.fetch(fetchDescriptor) {
            // CRITICAL: Force SwiftData to load relationship-backed data BEFORE assigning to sermons.
            // Assignment triggers @Observable, and views must see loaded values — not faulted data.
            for sermon in results {
                let notesCount = sermon.notes.count
                let _ = Array(sermon.notes)
                let hasTranscript = sermon.transcript != nil
                let summaryStatus = sermon.summaryStatus
                let hasSummary = sermon.summary != nil

                print("[DEBUG] Sermon '\(sermon.title)' (ID: \(sermon.id)) has \(notesCount) notes")
                print("[DEBUG]   hasTranscript: \(hasTranscript), summaryStatus: \(summaryStatus), hasSummary: \(hasSummary)")
                if notesCount > 0 {
                    for (index, note) in sermon.notes.enumerated() {
                        print("[DEBUG]   Note \(index): '\(note.text)' at \(note.timestamp)s, sermon ref: \(note.sermon?.id.uuidString ?? "nil")")
                    }
                }
            }

            sermons = results  // @Observable fires AFTER notes are loaded
            print("[SermonService] sermons fetched for user \(currentUser.id): \(sermons.map { $0.title })")

            applyFilters()
        } else {
            print("[SermonService] fetch failed for user \(currentUser.id).")
            sermons = []
            applyFilters()
        }
    }
    
    @MainActor
    private func migrateExistingSermons(to userId: UUID) {
        print("[SermonService] Checking for sermons without userId to migrate...")
        
        // Fetch sermons without userId
        let fetchDescriptor = FetchDescriptor<Sermon>()
        guard let allSermons = try? modelContext.fetch(fetchDescriptor) else { return }
        
        let sermonsToMigrate = allSermons.filter { $0.userId == nil }
        
        if !sermonsToMigrate.isEmpty {
            print("[SermonService] Migrating \(sermonsToMigrate.count) sermons to user \(userId)")
            
            for sermon in sermonsToMigrate {
                sermon.userId = userId
                print("[SermonService] Migrated sermon: \(sermon.title)")
            }
            
            try? modelContext.save()
            print("[SermonService] Migration completed")
        }
    }
    
    @MainActor
    private func migrateAudioFilePaths() {
        print("[SermonService] Checking for sermons with absolute audio file paths to migrate...")
        
        // Fetch all sermons to check for old absolute path format
        let fetchDescriptor = FetchDescriptor<Sermon>()
        guard let allSermons = try? modelContext.fetch(fetchDescriptor) else { return }
        
        var migratedCount = 0
        for sermon in allSermons {
            // Check if the audioFileName contains path separators, indicating it's still an absolute path
            if sermon.audioFileName.contains("/") {
                // Extract just the filename from the stored path
                let filename = sermon.audioFileName.components(separatedBy: "/").last ?? sermon.audioFileName
                
                print("[SermonService] Migrating sermon '\(sermon.title)' from path '\(sermon.audioFileName)' to filename '\(filename)'")
                
                // Update to store just the filename
                sermon.audioFileName = filename
                
                // Check if the file actually exists at the new computed path
                if !sermon.audioFileExists {
                    print("[SermonService] WARNING: Audio file '\(filename)' not found at expected location for sermon '\(sermon.title)'")
                    // Try to find the file in the AudioRecordings directory
                    let audioDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("AudioRecordings")
                    if let files = try? FileManager.default.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil) {
                        if let foundFile = files.first(where: { $0.lastPathComponent == filename }) {
                            print("[SermonService] Found audio file at: \(foundFile.path)")
                        } else {
                            print("[SermonService] Audio file '\(filename)' not found in AudioRecordings directory")
                        }
                    }
                }
                
                migratedCount += 1
            }
        }
        
        if migratedCount > 0 {
            print("[SermonService] Migrated \(migratedCount) sermons to use relative file paths")
            try? modelContext.save()
        } else {
            print("[SermonService] No sermons needed audio path migration")
        }
    }
    
    private func applyFilters() {
        var filtered = sermons
        
        // Apply archive filter
        if !showArchivedSermons {
            filtered = filtered.filter { !$0.isArchived }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { sermon in
                sermon.title.localizedCaseInsensitiveContains(searchText) ||
                sermon.serviceType.localizedCaseInsensitiveContains(searchText) ||
                (sermon.speaker?.localizedCaseInsensitiveContains(searchText) ?? false)
                // Intentionally avoid transcript/summary persisted-property reads here.
                // Corrupted local SwiftData relationship records can assert when faulted.
            }
        }
        
        // Apply sort order
        switch sortOption {
        case .newest:
            filtered = filtered.sorted { $0.date > $1.date }
        case .oldest:
            filtered = filtered.sorted { $0.date < $1.date }
        }
        
        filteredSermons = filtered
    }
    
    func clearSearch() {
        searchText = ""
    }
    
    func archiveSermon(_ sermon: Sermon) {
        sermon.isArchived = true
        markSermonForSync(sermon.id)
        try? modelContext.save()
        
        // Trigger sync if user has sync enabled
        if let currentUser = authManager.currentUser, currentUser.canSync {
            triggerSyncIfNeeded()
        }
        
        applyFilters()
    }
    
    func unarchiveSermon(_ sermon: Sermon) {
        sermon.isArchived = false
        markSermonForSync(sermon.id, metadata: true)
        try? modelContext.save()
        
        // Trigger sync if user has sync enabled
        if let currentUser = authManager.currentUser, currentUser.canSync {
            triggerSyncIfNeeded()
        }
        
        applyFilters()
    }
    
    func toggleSermonArchiveStatus(_ sermon: Sermon) {
        sermon.isArchived.toggle()
        try? modelContext.save()
        applyFilters()
    }
    
    func updateSermon(_ sermon: Sermon) {
        markSermonForSync(sermon.id, metadata: true)
        try? modelContext.save()
        
        // Trigger sync if user has sync enabled
        if let currentUser = authManager.currentUser, currentUser.canSync {
            triggerSyncIfNeeded()
        }
        
        applyFilters()
    }

    func applyTranscriptionResult(sermonId: UUID, text: String, segments: [TranscriptSegment]) {
        guard let sermon = findSermon(by: sermonId) else {
            print("[SermonService] Could not find sermon \(sermonId) to apply transcription result")
            return
        }

        let transcriptSnapshot = makeTranscriptSnapshot(
            text: text,
            segments: segments,
            existingTranscript: sermon.transcript
        )
        applyTranscriptSnapshot(transcriptSnapshot, to: sermon)

        sermon.transcriptionStatus = "complete"
        sermon.markPendingSync(metadata: true, transcript: true)

        try? modelContext.save()

        if let currentUser = authManager.currentUser, currentUser.canSync {
            triggerSyncIfNeeded()
        }

        applyFilters()
    }

    func markTranscriptionFailed(sermonId: UUID) {
        guard let sermon = findSermon(by: sermonId) else {
            print("[SermonService] Could not find sermon \(sermonId) to mark transcription failed")
            return
        }

        sermon.transcriptionStatus = "failed"
        sermon.markPendingSync(metadata: true)

        try? modelContext.save()

        if let currentUser = authManager.currentUser, currentUser.canSync {
            triggerSyncIfNeeded()
        }

        applyFilters()
    }

    func deleteSermon(_ sermon: Sermon) {
        if let index = sermons.firstIndex(where: { $0.id == sermon.id }) {
            let sermonToDelete = sermons[index]
            sermons.remove(at: index)
            modelContext.delete(sermonToDelete)
            try? modelContext.save()
            applyFilters()
        } else {
            modelContext.delete(sermon)
            try? modelContext.save()
            fetchSermons()
        }
    }
    
    func deleteAllSermons() {
        // Delete all sermons from the model context
        for sermon in sermons {
            modelContext.delete(sermon)
        }
        
        // Save the context to persist the deletions
        do {
            try modelContext.save()
            
            // Clear the local arrays
            sermons.removeAll()
            filteredSermons.removeAll()
            
            print("[SermonService] Successfully deleted all sermons")
        } catch {
            print("[SermonService] Failed to delete all sermons: \(error)")
        }
    }
    
    // MARK: - Sync Methods
    
    private func markSermonForSync(
        _ sermonId: UUID,
        metadata: Bool = false,
        notes: Bool = false,
        transcript: Bool = false,
        summary: Bool = false
    ) {
        guard let sermon = sermons.first(where: { $0.id == sermonId }) else { return }
        sermon.markPendingSync(
            metadata: metadata,
            notes: notes,
            transcript: transcript,
            summary: summary
        )

        // CRITICAL: Save the context to persist needsSync flag
        do {
            try modelContext.save()
            print("[SermonService] ✅ Saved needsSync flag for sermon \(sermonId)")
        } catch {
            print("[SermonService] ❌ Failed to save needsSync flag: \(error)")
        }
    }
    
    private func triggerSyncIfNeeded() {
        // Check if there are any sermons that need syncing
        let needsSync = sermons.contains { $0.hasPendingSyncWork }
        
        if needsSync {
            Task { @MainActor in
                await SermonProcessingCoordinator.shared.syncPendingChanges()
            }
        }
    }
    
    // Public sync methods
    func syncAllData() {
        guard let currentUser = authManager.currentUser, currentUser.canSync else { return }
        Task { @MainActor in
            await SermonProcessingCoordinator.shared.triggerManualSync()
        }
    }
    
    func isSyncAvailable() -> Bool {
        guard let currentUser = authManager.currentUser else { return false }
        return currentUser.canSync
    }
    
    // MARK: - Usage Limits
    
    func canCreateNewRecording() -> Bool {
        guard let currentUser = authManager.currentUser else { return false }
        return currentUser.canCreateNewRecording()
    }
    
    func canExportSermon() -> Bool {
        guard let currentUser = authManager.currentUser else { return false }
        
        if !currentUser.canExportThisMonth() {
            if let remaining = currentUser.remainingExports() {
                limitReachedMessage = "Export limit reached! You have \(remaining) exports remaining this month. Upgrade to Pro for unlimited exports."
            } else {
                limitReachedMessage = "Export limit reached! Upgrade to Pro for unlimited exports."
            }
            return false
        }
        
        return true
    }
    
    func exportSermon(_ sermon: Sermon) {
        guard canExportSermon() else { return }
        
        // Track export usage
        subscriptionService?.incrementExportCount()
        
        // Perform export logic here
        // ...
    }
    
    func getRemainingRecordings() -> Int? {
        return authManager.currentUser?.remainingRecordings()
    }
    
    func getRemainingStorageGB() -> Double? {
        return authManager.currentUser?.remainingStorageGB()
    }
    
    func getRemainingExports() -> Int? {
        return authManager.currentUser?.remainingExports()
    }
    
    func clearLimitMessage() {
        limitReachedMessage = nil
    }
    
    // MARK: - Manual Recovery
    
    func checkForRecoverableRecordings() {
        Task { @MainActor in
            print("[SermonService] Manual recovery triggered by user")
            checkForOrphanedAudioFiles()
        }
    }
    
    // MARK: - Helper Methods
    
    private func getFileSize(_ url: URL) -> Int64? {
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return fileAttributes[FileAttributeKey.size] as? Int64
        } catch {
            print("[SermonService] Error getting file size: \(error)")
            return nil
        }
    }
    
    // MARK: - Data Recovery
    
    @MainActor
    private func checkForRecoverableAudioFiles() {
        // Check for recoverable files from migration OR orphaned files in empty database
        if !DataMigration.hasRecoverableAudioFiles() {
            checkForOrphanedAudioFiles()
        } else {
            recoverFromMigration()
        }
    }
    
    @MainActor
    private func recoverFromMigration() {
        guard DataMigration.hasRecoverableAudioFiles() else { return }
        
        print("[SermonService] Found recoverable audio files after migration, attempting recovery...")
        
        let recoverableFiles = DataMigration.getRecoverableAudioFiles()
        performRecovery(from: recoverableFiles, source: "migration")
    }
    
    @MainActor
    private func checkForOrphanedAudioFiles() {
        // Check if we have an empty database but audio files exist by querying database directly
        do {
            let fetchDescriptor = FetchDescriptor<Sermon>()
            let allSermons = try modelContext.fetch(fetchDescriptor)
            
            if allSermons.isEmpty {
                print("[SermonService] Empty database detected (direct query), checking for orphaned audio files...")
                
                let audioDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("AudioRecordings")
                
                let audioFiles = try FileManager.default.contentsOfDirectory(
                    at: audioDir,
                    includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey]
                )
                
                let sermonFiles = audioFiles.filter { 
                    $0.lastPathComponent.hasPrefix("sermon_") && $0.lastPathComponent.hasSuffix(".m4a") 
                }
                
                if !sermonFiles.isEmpty {
                    print("[SermonService] Found \(sermonFiles.count) orphaned audio files")
                    
                    // Convert to recovery format
                    var recoverableFiles: [(filename: String, creationDate: Date, path: String)] = []
                    
                    for audioFile in sermonFiles {
                        let resourceValues = try audioFile.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                        let creationDate = resourceValues.creationDate ?? resourceValues.contentModificationDate ?? Date()
                        
                        recoverableFiles.append((
                            filename: audioFile.lastPathComponent,
                            creationDate: creationDate,
                            path: audioFile.path
                        ))
                    }
                    
                    performRecovery(from: recoverableFiles, source: "orphaned files")
                }
            } else {
                print("[SermonService] Database has \(allSermons.count) existing sermons, no recovery needed")
            }
        } catch {
            print("[SermonService] Error checking database or audio files: \(error)")
        }
    }
    
    @MainActor
    private func performRecovery(from recoverableFiles: [(filename: String, creationDate: Date, path: String)], source: String) {
        var recoveredCount = 0
        
        // Get backed-up notes if available
        let backedUpNotes = DataMigration.getBackedUpSermonNotes()
        
        for fileInfo in recoverableFiles {
            // Check if audio file still exists
            if FileManager.default.fileExists(atPath: fileInfo.path) {
                // Create a new sermon record for this audio file
                let title = generateTitleFromFilename(fileInfo.filename, date: fileInfo.creationDate)
                
                // Recover notes for this sermon if available
                var recoveredNotes: [Note] = []
                if let notesData = backedUpNotes[fileInfo.filename] {
                    for noteDict in notesData {
                        if let id = noteDict["id"] as? String,
                           let text = noteDict["text"] as? String,
                           let timestamp = noteDict["timestamp"] as? TimeInterval,
                           let uuid = UUID(uuidString: id) {
                            
                            let remoteId = noteDict["remoteId"] as? String
                            let updatedAtInterval = noteDict["updatedAt"] as? TimeInterval
                            let updatedAt = updatedAtInterval != nil ? Date(timeIntervalSince1970: updatedAtInterval!) : nil
                            let needsSync = noteDict["needsSync"] as? Bool ?? false
                            
                            let note = Note(
                                id: uuid,
                                text: text,
                                timestamp: timestamp,
                                remoteId: remoteId?.isEmpty == false ? remoteId : nil,
                                updatedAt: updatedAt,
                                needsSync: needsSync
                            )
                            
                            modelContext.insert(note)
                            recoveredNotes.append(note)
                        }
                    }
                    print("[SermonService] Recovered \(recoveredNotes.count) notes for \(fileInfo.filename)")
                }
                
                let sermon = Sermon(
                    title: title,
                    audioFileName: fileInfo.filename,
                    date: fileInfo.creationDate,
                    serviceType: "Sunday Service", // Default service type
                    speaker: nil,
                    transcript: nil,
                    notes: recoveredNotes,
                    summary: nil,
                    syncStatus: "localOnly",
                    transcriptionStatus: "pending",
                    summaryStatus: "pending",
                    isArchived: false,
                    userId: authManager.currentUser?.id
                )
                
                modelContext.insert(sermon)
                recoveredCount += 1
                
                print("[SermonService] Recovered sermon: \(title) with \(recoveredNotes.count) notes")
            }
        }
        
        if recoveredCount > 0 {
            do {
                try modelContext.save()
                print("[SermonService] Successfully recovered \(recoveredCount) sermons from \(source)")
                
                // Clear recovery flags if from migration
                if source == "migration" {
                    DataMigration.clearRecoveryFlags()
                }
                
                // Refresh sermon list
                fetchSermons()
                
                // Show user notification about recovery
                limitReachedMessage = "Recovered \(recoveredCount) recordings from previous version!"
                
                // Clear the message after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self.limitReachedMessage = nil
                }
                
            } catch {
                print("[SermonService] Failed to save recovered sermons: \(error)")
            }
        }
    }
    
    private func generateTitleFromFilename(_ filename: String, date: Date) -> String {
        // Extract UUID from filename if possible, otherwise use date
        if filename.hasPrefix("sermon_") {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Recovered Recording from \(formatter.string(from: date))"
        }
        return "Recovered Recording"
    }
    
    // MARK: - Summary Generation
    
    /// Generate summary for a sermon and handle completion at service level
    /// This ensures summaries are updated even if views are dismissed
    func generateSummaryForSermon(sermonId: UUID, transcript: String, serviceType: String) {
        print("[SermonService] Starting summary generation for sermon: \(sermonId)")

        guard let sermon = findSermon(by: sermonId) else {
            print("[SermonService] Could not find sermon \(sermonId) to queue summary generation")
            return
        }

        let transcriptText = sermon.transcript?.text ?? transcript
        guard !transcriptText.isEmpty else {
            print("[SermonService] No transcript available for sermon \(sermonId)")
            return
        }

        SermonProcessingCoordinator.shared.retrySummary(for: sermonId)
    }
    
    /// Check for sermons with stuck processing status and recover them
    func recoverStuckSummaries() {
        Task { @MainActor in
            SermonProcessingCoordinator.shared.refreshBackgroundProcessing()
        }
    }
}
