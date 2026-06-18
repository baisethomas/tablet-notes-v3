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

enum SermonSaveError: LocalizedError {
    case notAuthenticated
    case recordingLimitReached(String)
    case persistenceFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to save sermons."
        case .recordingLimitReached(let message):
            return message
        case .persistenceFailed:
            return "Couldn't save the sermon to this device. Your recording is safe — please try again."
        }
    }
}

enum SermonDeleteError: LocalizedError {
    case cloudDeleteFailed
    case syncUnavailable

    var errorDescription: String? {
        switch self {
        case .cloudDeleteFailed:
            return "Couldn't remove this sermon from the cloud, so it wasn't deleted. Check your connection and try again."
        case .syncUnavailable:
            return "Couldn't remove this sermon from the cloud, so it wasn't deleted. Please try again later."
        }
    }
}

@MainActor
@Observable
class SermonService {
    private let modelContext: ModelContext
    private let authManager: AuthenticationManager
    private var syncService: (any SyncServiceProtocol)?
    private var subscriptionService: (any SubscriptionServiceProtocol)?
    private var hasAttemptedInterruptedRecordingRecovery = false
    private var recoveredInterruptedSermonIDs: [UUID] = []
    private(set) var sermons: [Sermon] = []
    private(set) var filteredSermons: [Sermon] = []
    /// True while a cloud re-hydration is in flight (TAB-53), so the list can
    /// show a loading/restoring state instead of a bare empty library.
    private(set) var isRestoringFromCloud = false
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
        if case .authenticated = self.authManager.authState {
            wasAuthenticated = true
        }
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
        authManager.$authStatePublished
            .sink { [weak self] authState in
                Task { @MainActor in
                    guard let self else { return }

                    switch authState {
                    case .authenticated:
                        self.wasAuthenticated = true
                    case .unauthenticated:
                        if self.wasAuthenticated {
                            print("[SermonService] User signed out — clearing local data")
                            self.deleteAllLocalUserData()
                        }
                        self.wasAuthenticated = false
                    case .loading, .error:
                        // Preserve local data on transient auth errors (e.g. failed sign-out).
                        break
                    }

                    self.fetchSermons()
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    /// Tracks authenticated → unauthenticated transitions so sign-out wipes local data once.
    private var wasAuthenticated = false
    private static let localDataOwnerUserIdKey = "SermonService.localDataOwnerUserId"
    private let interruptedRecordingMinimumSizeBytes: Int64 = 1024

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
            TranscriptSnapshotStore.remove(for: sermon.id)
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
            TranscriptSnapshotStore.save(
                transcriptId: existingTranscript.id,
                text: snapshot.text,
                for: sermon.id
            )
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
        TranscriptSnapshotStore.save(
            transcriptId: transcript.id,
            text: snapshot.text,
            for: sermon.id
        )
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

    func saveSermon(title: String, audioFileURL: URL, date: Date, serviceType: String, speaker: String? = nil, transcript: Transcript?, notes: [Note], summary: Summary?, transcriptionStatus: String = "processing", summaryStatus: String = "processing", isArchived: Bool = false, id: UUID? = nil, completion: ((Result<UUID, Error>) -> Void)? = nil) {
        print("[SermonService] saveSermon called with title: \(title), date: \(date), serviceType: \(serviceType)")
        
        Task { @MainActor in
            // Ensure user is authenticated
            guard let currentUser = authManager.currentUser else {
                print("[SermonService] ERROR: No authenticated user found. Cannot save sermon.")
                limitReachedMessage = "Please sign in to save sermons"
                completion?(.failure(SermonSaveError.notAuthenticated))
                return
            }
            
            // Treat the audio file as the durable identity for interrupted recording recovery.
            let requestedSermonID = id ?? UUID()
            let existingSermon = findSermon(by: requestedSermonID) ?? findSermon(withAudioFileName: audioFileURL.lastPathComponent)
            let sermonID = existingSermon?.id ?? requestedSermonID
            let isNewSermon = existingSermon == nil
            
            // Check usage limits for new sermons
            if isNewSermon && !currentUser.canCreateNewRecording() {
                let message: String
                if let remaining = currentUser.remainingRecordings() {
                    message = "Recording limit reached! You have \(remaining) recordings remaining this month. Upgrade to Pro for unlimited recordings."
                } else {
                    message = "Recording limit reached! Upgrade to Pro for unlimited recordings."
                }
                limitReachedMessage = message
                completion?(.failure(SermonSaveError.recordingLimitReached(message)))
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

            if let existing = existingSermon {
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
                // Discard the partially-applied changes so the context stays
                // consistent, and report the failure honestly. Callers must NOT
                // clear the note session or navigate as if the save succeeded.
                modelContext.rollback()
                fetchSermons()
                completion?(.failure(SermonSaveError.persistenceFailed(error)))
                return
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
            completion?(.success(sermonID))
        }
    }

    private var activeUser: User? {
        if let currentUser = authManager.currentUser {
            return currentUser
        }
        if case .authenticated(let user) = authManager.authState {
            return user
        }
        return nil
    }

    func fetchSermons() {
        print("[SermonService] fetchSermons called.")

        // IMPORTANT: This runs synchronously on @MainActor (no Task wrapper) so that
        // notes relationships are force-loaded BEFORE any @Observable-triggered re-render.
        // A deferred Task would allow the view to re-render with faulted/empty notes first.

        // Never show another user's local rows while signed out.
        guard let currentUser = activeUser else {
            print("[SermonService] No authenticated user — empty sermon list")
            sermons = []
            filteredSermons = []
            applyFilters()
            return
        }

        print("[SermonService] Fetching sermons for user: \(currentUser.name) (ID: \(currentUser.id))")

        ensureLocalDataBelongsToCurrentUser()

        recoverInterruptedRecordingIfNeeded()

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

    func deleteSermon(_ sermon: Sermon) async throws {
        let sermonId = sermon.id

        // Delete the cloud copy first: removing the local row alone leaves a
        // remote row that the next pull resurrects on every device (TAB-32).
        if let remoteId = sermon.remoteId, !remoteId.isEmpty {
            guard let syncService else {
                print("[SermonService] ❌ Sync service unavailable; refusing local-only delete of synced sermon \(sermonId)")
                throw SermonDeleteError.syncUnavailable
            }
            do {
                try await syncService.deleteRemoteSermon(remoteId: remoteId)
            } catch {
                print("[SermonService] ❌ Cloud delete failed for sermon \(sermonId): \(error.localizedDescription)")
                throw SermonDeleteError.cloudDeleteFailed
            }
        }

        // Re-resolve after the await — the model may have been deleted or
        // invalidated while the network call was suspended (TAB-21).
        guard let sermonToDelete = findSermon(by: sermonId) else {
            sermons.removeAll { $0.id == sermonId }
            applyFilters()
            return
        }

        deleteLocalAudioFile(for: sermonToDelete)
        if let index = sermons.firstIndex(where: { $0.id == sermonId }) {
            sermons.remove(at: index)
            modelContext.delete(sermonToDelete)
            try? modelContext.save()
            applyFilters()
        } else {
            modelContext.delete(sermonToDelete)
            try? modelContext.save()
            fetchSermons()
        }
    }

    /// Removes the sermon's local audio file so deleted sermons don't leave
    /// orphaned recordings on disk (which orphan recovery would resurrect).
    private func deleteLocalAudioFile(for sermon: Sermon) {
        let audioURL = sermon.audioFileURL
        guard FileManager.default.fileExists(atPath: audioURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: audioURL)
            sermon.invalidateFileExistenceCache()
            print("[SermonService] Deleted local audio file \(sermon.audioFileName)")
        } catch {
            print("[SermonService] Failed to delete local audio file \(sermon.audioFileName): \(error)")
        }
    }

    func deleteAllSermons() {
        guard let allSermons = try? modelContext.fetch(FetchDescriptor<Sermon>()) else {
            sermons.removeAll()
            filteredSermons.removeAll()
            return
        }

        for sermon in allSermons {
            deleteLocalAudioFile(for: sermon)
            modelContext.delete(sermon)
        }

        if let jobs = try? modelContext.fetch(FetchDescriptor<ProcessingJob>()) {
            for job in jobs {
                modelContext.delete(job)
            }
        }

        do {
            try modelContext.save()

            sermons.removeAll()
            filteredSermons.removeAll()

            print("[SermonService] Successfully deleted all sermons")
        } catch {
            print("[SermonService] Failed to delete all sermons: \(error)")
        }
    }

    /// Wipes all on-device user content after a confirmed server-side account
    /// deletion: sermon rows, audio files (including orphans), recovery state,
    /// and in-progress note sessions.
    func deleteAllLocalUserData() {
        deleteAllSermons()
        removeAllRemainingLocalAudioFiles()
        InterruptedRecordingRecoveryStore.clear()
        clearRecordingNoteSessions()
        DataMigration.clearRecoveryFlags()
        clearLocalDataOwnershipMarker()
    }

    /// Ensures leftover on-device content from a prior account cannot attach to
    /// the newly signed-in user (e.g. after a failed sign-out or partial wipe).
    private func ensureLocalDataBelongsToCurrentUser() {
        guard let userId = activeUser?.id else { return }

        let storedOwnerId = UserDefaults.standard.string(forKey: Self.localDataOwnerUserIdKey)
        if storedOwnerId != userId.uuidString {
            let shouldWipe = storedOwnerId != nil
                || hasSermonsOwnedByDifferentUser(than: userId)
                || hasRecoveryManifestOwnedByDifferentUser(than: userId)

            if shouldWipe {
                print("[SermonService] Local data belongs to another user — wiping before continuing")
                deleteAllLocalUserData()
            }
            UserDefaults.standard.set(userId.uuidString, forKey: Self.localDataOwnerUserIdKey)
        }
    }

    private func hasSermonsOwnedByDifferentUser(than userId: UUID) -> Bool {
        guard let sermons = try? modelContext.fetch(FetchDescriptor<Sermon>()) else { return false }
        return sermons.contains { sermon in
            guard let sermonUserId = sermon.userId else { return false }
            return sermonUserId != userId
        }
    }

    private func hasRecoveryManifestOwnedByDifferentUser(than userId: UUID) -> Bool {
        guard let manifest = InterruptedRecordingRecoveryStore.load(),
              let manifestUserId = manifest.userId else {
            return false
        }
        return manifestUserId != userId
    }

    private func clearLocalDataOwnershipMarker() {
        UserDefaults.standard.removeObject(forKey: Self.localDataOwnerUserIdKey)
    }

    private static var audioRecordingsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings", isDirectory: true)
    }

    private func removeAllRemainingLocalAudioFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Self.audioRecordingsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for fileURL in files {
            do {
                try FileManager.default.removeItem(at: fileURL)
                print("[SermonService] Deleted remaining audio file \(fileURL.lastPathComponent)")
            } catch {
                print("[SermonService] Failed to delete remaining audio file \(fileURL.lastPathComponent): \(error)")
            }
        }
    }

    private func clearRecordingNoteSessions() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("recordingSessionNotes") {
            defaults.removeObject(forKey: key)
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

    /// Drives a full cloud re-hydration when the local library is empty — after a
    /// destructive store reset (TAB-53) or a fresh install. Clears the reset
    /// signal only on a *confirmed* outcome (data restored, or a successful sync
    /// that found nothing), so a failed or offline attempt keeps the restoring
    /// state instead of falling back to the misleading empty-library screen.
    @MainActor
    func performCloudRestore() async {
        // Can't restore yet (not signed in / sync unavailable): leave the reset
        // flag set so we retry rather than show the empty screen as if data lost.
        guard isSyncAvailable() else { return }

        isRestoringFromCloud = true
        defer { isRestoringFromCloud = false }

        // Use the result-reporting sync: clear the reset signal ONLY on a
        // confirmed success. Connectivity doesn't prove the backend/auth sync
        // worked, and clearing on a failed sync would bring back the misleading
        // empty-library screen (TAB-53, finding a).
        let succeeded = await (syncService?.syncAllDataReportingSuccess() ?? false)
        fetchSermons()

        guard succeeded else { return }  // keep flags, retry; UI stays restoring

        DataMigration.clearLocalStoreResetFlag()
        // The cloud copy is now local. Drop the orphan-audio recovery catalog
        // too: after a reset, those on-disk files are the same recordings the
        // pull just re-downloaded, and re-importing them would create duplicate
        // local-only rows that push as new cloud sermons (TAB-53, finding b).
        DataMigration.clearRecoveryFlags()
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

    func consumeRecoveredInterruptedSermonIDs() -> [UUID] {
        let sermonIDs = recoveredInterruptedSermonIDs
        recoveredInterruptedSermonIDs.removeAll()
        return sermonIDs
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
    private func recoverInterruptedRecordingIfNeeded() {
        guard !hasAttemptedInterruptedRecordingRecovery else { return }
        hasAttemptedInterruptedRecordingRecovery = true

        guard let manifest = InterruptedRecordingRecoveryStore.load() else { return }

        guard let activeUserId = activeUser?.id else {
            print("[SermonService] Skipping interrupted recording recovery — no signed-in user")
            return
        }

        guard let manifestUserId = manifest.userId else {
            print("[SermonService] Discarding legacy interrupted recording manifest without owner")
            InterruptedRecordingRecoveryStore.clear()
            return
        }

        guard manifestUserId == activeUserId else {
            print("[SermonService] Skipping interrupted recording recovery — manifest belongs to another user")
            InterruptedRecordingRecoveryStore.clear()
            return
        }

        let audioURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings")
            .appendingPathComponent(manifest.audioFileName)

        if sermons.contains(where: { $0.audioFileName == manifest.audioFileName }) || findSermon(withAudioFileName: manifest.audioFileName) != nil {
            InterruptedRecordingRecoveryStore.clear()
            NoteService(sessionId: manifest.sessionId).clearSession()
            return
        }

        guard FileManager.default.fileExists(atPath: audioURL.path),
              let fileSize = getFileSize(audioURL),
              fileSize >= interruptedRecordingMinimumSizeBytes else {
            print("[SermonService] Interrupted recording manifest found but audio file was unavailable or too small")
            InterruptedRecordingRecoveryStore.clear()
            return
        }

        let noteService = NoteService(sessionId: manifest.sessionId)
        let recoveredNotes = noteService.currentNotes

        let sermon = Sermon(
            title: generateInterruptedRecordingTitle(from: manifest.startedAt),
            audioFileName: manifest.audioFileName,
            date: manifest.startedAt,
            serviceType: manifest.serviceType,
            speaker: nil,
            transcript: nil,
            notes: recoveredNotes,
            summary: nil,
            syncStatus: "localOnly",
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            isArchived: false,
            userId: activeUserId
        )
        sermon.markPendingSync(metadata: true, notes: !recoveredNotes.isEmpty)

        for note in recoveredNotes {
            note.sermon = sermon
            modelContext.insert(note)
        }

        modelContext.insert(sermon)

        do {
            try modelContext.save()
            recoveredInterruptedSermonIDs.append(sermon.id)
            InterruptedRecordingRecoveryStore.clear()
            noteService.clearSession()
            print("[SermonService] Recovered interrupted recording \(manifest.audioFileName)")
        } catch {
            print("[SermonService] Failed to recover interrupted recording: \(error)")
        }
    }
    
    @MainActor
    private func checkForRecoverableAudioFiles() {
        // After a destructive store reset, the orphan audio files on disk are the
        // SAME recordings already in the cloud. Importing them as local-only rows
        // here would let the two-phase sync push them as brand-new cloud sermons
        // (push runs before pull) — creating duplicates. While a reset+restore is
        // pending and sync is available, defer to the cloud pull instead; the
        // restore clears the recovery catalog on success (TAB-53, finding b).
        if DataMigration.didResetLocalStore() && isSyncAvailable() {
            print("[SermonService] Skipping orphan-audio import — cloud restore pending after store reset")
            return
        }

        // Check for recoverable files from migration OR orphaned files in empty database
        if !DataMigration.hasRecoverableAudioFiles() {
            checkForOrphanedAudioFiles()
        } else {
            recoverFromMigration()
        }
    }
    
    @MainActor
    private func recoverFromMigration() {
        guard let activeUserId = activeUser?.id else { return }

        let storedOwnerId = UserDefaults.standard.string(forKey: Self.localDataOwnerUserIdKey)
        guard storedOwnerId == activeUserId.uuidString else {
            print("[SermonService] Skipping migration recovery — local data owner mismatch")
            DataMigration.clearRecoveryFlags()
            return
        }

        guard let recoveryOwnerId = DataMigration.recoveryOwnerUserId(),
              recoveryOwnerId == activeUserId.uuidString else {
            print("[SermonService] Skipping migration recovery — catalog has no ownership proof for current user")
            DataMigration.clearRecoveryFlags()
            return
        }

        guard DataMigration.hasRecoverableAudioFiles() else { return }
        
        print("[SermonService] Found recoverable audio files after migration, attempting recovery...")
        
        let recoverableFiles = DataMigration.getRecoverableAudioFiles()
        performRecovery(from: recoverableFiles, source: "migration")
    }
    
    /// Recovery window for orphaned audio files. Old strays (e.g. files left
    /// behind before sermon deletion started removing audio from disk) should
    /// not be resurrected as new sermons.
    private static let orphanedAudioRecoveryWindow: TimeInterval = 7 * 24 * 3600

    /// Minimum age before a file counts as orphaned. A recording that just
    /// stopped is briefly unmatched while the processing pipeline creates its
    /// Sermon row; don't race it.
    private static let orphanedAudioMinimumAge: TimeInterval = 10 * 60

    @MainActor
    private func checkForOrphanedAudioFiles() {
        guard let activeUserId = activeUser?.id else { return }

        let storedOwnerId = UserDefaults.standard.string(forKey: Self.localDataOwnerUserIdKey)
        guard storedOwnerId == activeUserId.uuidString else {
            print("[SermonService] Skipping orphan audio recovery — local data owner mismatch")
            return
        }

        // Recover any recent sermon audio file that has no matching Sermon row,
        // regardless of how many sermons exist. Previously this only ran on an
        // empty database, so a recording lost while other sermons existed
        // (e.g. auto-stop with no handler) stayed orphaned on disk forever.
        do {
            let fetchDescriptor = FetchDescriptor<Sermon>()
            let allSermons = try modelContext.fetch(fetchDescriptor)
            let knownAudioFileNames = Set(allSermons.map { $0.audioFileName })

            // Never treat the in-flight recording as orphaned.
            let activeRecordingFileName = InterruptedRecordingRecoveryStore.load()?.audioFileName

            let audioDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("AudioRecordings")

            guard FileManager.default.fileExists(atPath: audioDir.path) else { return }

            let audioFiles = try FileManager.default.contentsOfDirectory(
                at: audioDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey]
            )

            var recoverableFiles: [(filename: String, creationDate: Date, path: String)] = []
            let recoveryCutoff = Date().addingTimeInterval(-Self.orphanedAudioRecoveryWindow)
            let minimumAgeCutoff = Date().addingTimeInterval(-Self.orphanedAudioMinimumAge)

            for audioFile in audioFiles {
                let filename = audioFile.lastPathComponent
                guard filename.hasPrefix("sermon_"), filename.hasSuffix(".m4a"),
                      !knownAudioFileNames.contains(filename),
                      filename != activeRecordingFileName else { continue }

                let resourceValues = try audioFile.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let creationDate = resourceValues.creationDate ?? resourceValues.contentModificationDate ?? Date()
                guard creationDate >= recoveryCutoff, creationDate <= minimumAgeCutoff else { continue }

                recoverableFiles.append((
                    filename: filename,
                    creationDate: creationDate,
                    path: audioFile.path
                ))
            }

            if !recoverableFiles.isEmpty {
                print("[SermonService] Found \(recoverableFiles.count) orphaned audio files")
                performRecovery(from: recoverableFiles, source: "orphaned files")
            }
        } catch {
            print("[SermonService] Error checking database or audio files: \(error)")
        }
    }
    
    @MainActor
    private func performRecovery(from recoverableFiles: [(filename: String, creationDate: Date, path: String)], source: String) {
        guard let activeUserId = activeUser?.id else { return }

        var recoveredCount = 0
        
        // Get backed-up notes if available
        let backedUpNotes = DataMigration.getBackedUpSermonNotes()
        
        for fileInfo in recoverableFiles {
            // Check if audio file still exists
            if FileManager.default.fileExists(atPath: fileInfo.path) {
                if findSermon(withAudioFileName: fileInfo.filename) != nil {
                    print("[SermonService] Skipping recovery for \(fileInfo.filename); sermon already exists")
                    continue
                }

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
                    userId: activeUserId
                )
                sermon.markPendingSync(metadata: true, notes: !recoveredNotes.isEmpty)

                for note in recoveredNotes {
                    note.sermon = sermon
                }
                
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
            } catch {
                print("[SermonService] Failed to save recovered sermons: \(error)")
            }
        }
    }
    
    private func generateTitleFromFilename(_ filename: String, date: Date) -> String {
        // Extract UUID from filename if possible, otherwise use date
        if filename.hasPrefix("sermon_") {
            return "Sermon on " + DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        }
        return "Sermon"
    }

    private func generateInterruptedRecordingTitle(from date: Date) -> String {
        "Sermon on " + DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    private func findSermon(withAudioFileName audioFileName: String) -> Sermon? {
        if let sermon = sermons.first(where: { $0.audioFileName == audioFileName }) {
            return sermon
        }

        let descriptor = FetchDescriptor<Sermon>(predicate: #Predicate { sermon in
            sermon.audioFileName == audioFileName
        })
        return try? modelContext.fetch(descriptor).first
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
