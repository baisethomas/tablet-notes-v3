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

class SermonService: ObservableObject {
    private let modelContext: ModelContext
    private let authManager: AuthenticationManager
    @Published private(set) var sermons: [Sermon] = []
    @Published private(set) var filteredSermons: [Sermon] = []
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

    init(modelContext: ModelContext, authManager: AuthenticationManager? = nil) {
        self.modelContext = modelContext
        self.authManager = authManager ?? AuthenticationManager.shared
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
                return
            }
            
            print("[SermonService] Saving sermon for user: \(currentUser.name) (ID: \(currentUser.id))")
            
            let sermonID = id ?? UUID()
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
                print("[DEBUG] saveSermon: updated existing sermon \(existing.id) for user \(currentUser.id)")
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
                print("[DEBUG] saveSermon: inserted new sermon \(sermon.id) for user \(currentUser.id)")
            }
            try? modelContext.save()
            print("[SermonService] Sermon inserted/updated and modelContext saved.")
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
        try? modelContext.save()
        applyFilters()
    }
    
    func unarchiveSermon(_ sermon: Sermon) {
        sermon.isArchived = false
        try? modelContext.save()
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
} 