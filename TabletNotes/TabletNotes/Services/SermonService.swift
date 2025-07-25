import Foundation
import SwiftData
import Combine

extension Sermon: Identifiable {}
extension Transcript: Identifiable {}
extension Note: Identifiable {}
extension Summary: Identifiable {}

enum SortOption: String, CaseIterable {
    case newest = "Newest First"
    case oldest = "Oldest First"
}

@MainActor
class SermonService: ObservableObject {
    private let modelContext: ModelContext
    private let authManager: AuthenticationManager
    private var syncService: (any SyncServiceProtocol)?
    private var subscriptionService: (any SubscriptionServiceProtocol)?
    @Published private(set) var sermons: [Sermon] = []
    @Published private(set) var filteredSermons: [Sermon] = []
    @Published var limitReachedMessage: String?
    @Published var searchText: String = "" {
        didSet {
            applyFilters()
        }
    }
    @Published var sortOption: SortOption = .newest {
        didSet {
            applyFilters()
        }
    }
    @Published var showArchivedSermons: Bool = false {
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
    
    @MainActor
    private func setupAuthStateObserver() {
        // Refresh sermons when auth state changes
        authManager.$authState
            .sink { [weak self] authState in
                Task { @MainActor in
                    self?.fetchSermons()
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()

    func saveSermon(title: String, audioFileURL: URL, date: Date, serviceType: String, speaker: String? = nil, transcript: Transcript?, notes: [Note], summary: Summary?, transcriptionStatus: String = "processing", summaryStatus: String = "processing", isArchived: Bool = false, id: UUID? = nil) {
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
            
            // First, ensure all notes are inserted into the context
            for note in notes {
                modelContext.insert(note)
            }
            
            // Add debugging for notes
            print("[DEBUG] saveSermon: Processing \(notes.count) notes")
            for (index, note) in notes.enumerated() {
                print("[DEBUG] Note \(index): '\(note.text)' at \(note.timestamp)s")
            }
            
            if let existing = sermons.first(where: { $0.id == sermonID }) {
                // Update existing sermon
                existing.title = title
                existing.audioFileURL = audioFileURL
                existing.date = date
                existing.serviceType = serviceType
                existing.speaker = speaker
                existing.transcript = transcript
                existing.notes = notes
                existing.summary = summary
                existing.transcriptionStatus = transcriptionStatus
                existing.summaryStatus = summaryStatus
                existing.isArchived = isArchived
                // Update userId to current user (in case of user changes)
                existing.userId = currentUser.id
                print("[DEBUG] saveSermon: updated existing sermon \(existing.id) with \(notes.count) notes for user \(currentUser.id)")
            } else {
                // Insert new sermon
                let sermon = Sermon(
                    id: sermonID,
                    title: title,
                    audioFileURL: audioFileURL,
                    date: date,
                    serviceType: serviceType,
                    speaker: speaker,
                    transcript: transcript,
                    notes: notes,
                    summary: summary,
                    syncStatus: "localOnly",
                    transcriptionStatus: transcriptionStatus,
                    summaryStatus: summaryStatus,
                    isArchived: isArchived,
                    userId: currentUser.id
                )
                modelContext.insert(sermon)
                print("[DEBUG] saveSermon: inserted new sermon \(sermon.id) with \(notes.count) notes for user \(currentUser.id)")
            }
            try? modelContext.save()
            print("[SermonService] Sermon inserted/updated and modelContext saved.")
            
            // Track usage for new sermons
            if isNewSermon {
                subscriptionService?.incrementRecordingCount()
                
                // Calculate audio file size and update storage usage
                if let fileSize = getFileSize(audioFileURL) {
                    let fileSizeGB = Double(fileSize) / 1_073_741_824 // Convert bytes to GB
                    subscriptionService?.incrementStorageUsage(fileSizeGB)
                }
            }
            
            // Trigger sync if user has sync enabled
            if let currentUser = authManager.currentUser, currentUser.canSync {
                markSermonForSync(sermonID)
                triggerSyncIfNeeded()
            }
            
            fetchSermons()
        }
    }

    func fetchSermons() {
        print("[SermonService] fetchSermons called.")
        
        Task { @MainActor in
            // If no user is authenticated, show all sermons (for migration compatibility)
            guard let currentUser = authManager.currentUser else {
                print("[SermonService] No authenticated user - fetching all sermons")
                let fetchDescriptor = FetchDescriptor<Sermon>()
                if let results = try? modelContext.fetch(fetchDescriptor) {
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
            
            // Create predicate to filter by userId
            let userIdToMatch = currentUser.id
            let predicate = #Predicate<Sermon> { sermon in
                sermon.userId == userIdToMatch
            }
            
            let fetchDescriptor = FetchDescriptor<Sermon>(predicate: predicate)
            
            if let results = try? modelContext.fetch(fetchDescriptor) {
                sermons = results
                print("[SermonService] sermons fetched for user \(currentUser.id): \(sermons.map { $0.title })")
                applyFilters()
            } else {
                print("[SermonService] fetch failed for user \(currentUser.id).")
                sermons = []
                applyFilters()
            }
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
                (sermon.speaker?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (sermon.transcript?.text.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (sermon.summary?.text.localizedCaseInsensitiveContains(searchText) ?? false)
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
        markSermonForSync(sermon.id)
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
    
    private func markSermonForSync(_ sermonId: UUID) {
        guard let sermon = sermons.first(where: { $0.id == sermonId }) else { return }
        sermon.needsSync = true
        sermon.updatedAt = Date()
        sermon.syncStatus = "pending"
    }
    
    private func triggerSyncIfNeeded() {
        guard let syncService = syncService else { return }
        
        // Check if there are any sermons that need syncing
        let needsSync = sermons.contains { $0.needsSync }
        
        if needsSync {
            // Trigger sync in background
            Task {
                await syncService.syncAllData()
            }
        }
    }
    
    // Public sync methods
    func syncAllData() {
        guard let currentUser = authManager.currentUser, currentUser.canSync else { return }
        Task {
            await syncService?.syncAllData()
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
} 