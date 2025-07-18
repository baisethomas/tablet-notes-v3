import Foundation
import Combine
import SwiftData
import Supabase

class SyncService: SyncServiceProtocol {
    
    // MARK: - Properties
    
    private let modelContext: ModelContext
    private let supabaseService: SupabaseServiceProtocol
    private let authService: AuthenticationManager
    
    @Published private var syncStatus: String = "idle"
    @Published private var syncError: Error?
    
    var syncStatusPublisher: AnyPublisher<String, Never> {
        $syncStatus.eraseToAnyPublisher()
    }
    
    var errorPublisher: AnyPublisher<Error?, Never> {
        $syncError.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext, supabaseService: SupabaseServiceProtocol, authService: AuthenticationManager) {
        self.modelContext = modelContext
        self.supabaseService = supabaseService
        self.authService = authService
    }
    
    // MARK: - Public Methods
    
    func syncAllData() async {
        await performFullSync()
    }
    
    func deleteAllCloudData() async {
        await performCloudDataDeletion()
    }
    
    // MARK: - Sync Operations
    
    @MainActor
    private func performFullSync() async {
        // Check if user can sync
        guard let currentUser = authService.currentUser,
              currentUser.canSync else {
            syncError = SyncError.subscriptionRequired
            return
        }
        
        syncStatus = "syncing"
        syncError = nil
        
        do {
            // 1. Push local changes to cloud
            try await pushLocalChanges()
            
            // 2. Pull cloud changes to local
            try await pullCloudChanges()
            
            syncStatus = "synced"
        } catch {
            syncStatus = "error"
            syncError = error
        }
    }
    
    private func pushLocalChanges() async throws {
        // Get all local sermons that need syncing
        let descriptor = FetchDescriptor<Sermon>(
            predicate: #Predicate<Sermon> { sermon in
                sermon.needsSync == true || sermon.remoteId == nil
            }
        )
        
        let sermonsToSync = try modelContext.fetch(descriptor)
        
        for sermon in sermonsToSync {
            try await syncSermonToCloud(sermon)
        }
    }
    
    private func pullCloudChanges() async throws {
        guard let currentUser = await authService.currentUser else { return }
        
        // Fetch all remote sermons for current user
        let remoteSermons = try await fetchRemoteSermons(for: currentUser.id)
        
        for remoteSermon in remoteSermons {
            try await syncSermonFromCloud(remoteSermon)
        }
    }
    
    private func syncSermonToCloud(_ sermon: Sermon) async throws {
        let sermonData = SermonSyncData(
            id: sermon.id,
            title: sermon.title,
            audioFileURL: sermon.audioFileURL,
            date: sermon.date,
            serviceType: sermon.serviceType,
            speaker: sermon.speaker,
            transcriptionStatus: sermon.transcriptionStatus,
            summaryStatus: sermon.summaryStatus,
            isArchived: sermon.isArchived,
            userId: sermon.userId,
            updatedAt: sermon.updatedAt ?? Date()
        )
        
        // Upload to Supabase
        if let remoteId = sermon.remoteId {
            // Update existing record
            try await updateRemoteSermon(remoteId: remoteId, data: sermonData)
        } else {
            // Create new record
            let newRemoteId = try await createRemoteSermon(data: sermonData)
            sermon.remoteId = newRemoteId
        }
        
        // Update local sync metadata
        sermon.lastSyncedAt = Date()
        sermon.needsSync = false
        sermon.syncStatus = "synced"
        
        // Sync related data
        try await syncRelatedData(for: sermon)
        
        try modelContext.save()
    }
    
    private func syncSermonFromCloud(_ remoteSermon: RemoteSermonData) async throws {
        // Find existing local sermon
        let remoteId = remoteSermon.id
        let descriptor = FetchDescriptor<Sermon>(
            predicate: #Predicate<Sermon> { sermon in
                sermon.remoteId == remoteId
            }
        )
        
        let existingSermons = try modelContext.fetch(descriptor)
        
        if let existingSermon = existingSermons.first {
            // Update existing sermon if remote is newer
            if remoteSermon.updatedAt > (existingSermon.updatedAt ?? Date.distantPast) {
                updateLocalSermon(existingSermon, with: remoteSermon)
            }
        } else {
            // Create new local sermon
            try await createLocalSermon(from: remoteSermon)
        }
    }
    
    private func syncRelatedData(for sermon: Sermon) async throws {
        // Sync notes
        for note in sermon.notes {
            try await syncNoteToCloud(note, sermonId: sermon.remoteId!)
        }
        
        // Sync transcript
        if let transcript = sermon.transcript {
            try await syncTranscriptToCloud(transcript, sermonId: sermon.remoteId!)
        }
        
        // Sync summary
        if let summary = sermon.summary {
            try await syncSummaryToCloud(summary, sermonId: sermon.remoteId!)
        }
    }
    
    private func performCloudDataDeletion() async {
        guard let currentUser = await authService.currentUser else { return }
        
        do {
            try await deleteAllRemoteData(for: currentUser.id)
            
            // Reset local sync metadata
            let descriptor = FetchDescriptor<Sermon>()
            let allSermons = try modelContext.fetch(descriptor)
            
            for sermon in allSermons {
                sermon.remoteId = nil
                sermon.lastSyncedAt = nil
                sermon.syncStatus = "localOnly"
                sermon.needsSync = false
            }
            
            try modelContext.save()
        } catch {
            syncError = error
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateLocalSermon(_ sermon: Sermon, with remoteData: RemoteSermonData) {
        sermon.title = remoteData.title
        sermon.serviceType = remoteData.serviceType
        sermon.speaker = remoteData.speaker
        sermon.isArchived = remoteData.isArchived
        sermon.transcriptionStatus = remoteData.transcriptionStatus
        sermon.summaryStatus = remoteData.summaryStatus
        sermon.updatedAt = remoteData.updatedAt
        sermon.lastSyncedAt = Date()
        sermon.syncStatus = "synced"
    }
    
    private func createLocalSermon(from remoteData: RemoteSermonData) async throws {
        // Download audio file if needed
        let localAudioURL = try await downloadAudioFile(from: remoteData.audioFileURL)
        
        let sermon = Sermon(
            id: remoteData.localId,
            title: remoteData.title,
            audioFileURL: localAudioURL,
            date: remoteData.date,
            serviceType: remoteData.serviceType,
            speaker: remoteData.speaker,
            syncStatus: "synced",
            transcriptionStatus: remoteData.transcriptionStatus,
            summaryStatus: remoteData.summaryStatus,
            isArchived: remoteData.isArchived,
            userId: remoteData.userId,
            lastSyncedAt: Date(),
            remoteId: remoteData.id,
            updatedAt: remoteData.updatedAt
        )
        
        modelContext.insert(sermon)
        try modelContext.save()
    }
}

// MARK: - Supabase Operations

extension SyncService {
    
    private func fetchRemoteSermons(for userId: UUID) async throws -> [RemoteSermonData] {
        // Use SupabaseService to make authenticated request to Netlify endpoint
        guard let supabaseService = self.supabaseService as? SupabaseService else {
            throw SyncError.networkError
        }
        let sermons = try await supabaseService.fetchRemoteSermons(for: userId)
        return sermons
    }
    
    private func createRemoteSermon(data: SermonSyncData) async throws -> String {
        // This would call your Netlify function to create a sermon
        // Return the remote ID
        return UUID().uuidString
    }
    
    private func updateRemoteSermon(remoteId: String, data: SermonSyncData) async throws {
        // This would call your Netlify function to update a sermon
    }
    
    private func deleteAllRemoteData(for userId: UUID) async throws {
        // This would call your Netlify function to delete all user data
    }
    
    private func downloadAudioFile(from url: URL) async throws -> URL {
        // Download audio file to local storage
        // Return local URL
        return url // Placeholder
    }
    
    private func syncNoteToCloud(_ note: Note, sermonId: String) async throws {
        // Sync note to cloud
    }
    
    private func syncTranscriptToCloud(_ transcript: Transcript, sermonId: String) async throws {
        // Sync transcript to cloud
    }
    
    private func syncSummaryToCloud(_ summary: Summary, sermonId: String) async throws {
        // Sync summary to cloud
    }
}

// MARK: - Data Models

struct SermonSyncData {
    let id: UUID
    let title: String
    let audioFileURL: URL
    let date: Date
    let serviceType: String
    let speaker: String?
    let transcriptionStatus: String
    let summaryStatus: String
    let isArchived: Bool
    let userId: UUID?
    let updatedAt: Date
}

struct RemoteSermonData: Codable {
    let id: String // Remote ID
    let localId: UUID
    let title: String
    let audioFileURL: URL
    let date: Date
    let serviceType: String
    let speaker: String?
    let transcriptionStatus: String
    let summaryStatus: String
    let isArchived: Bool
    let userId: UUID
    let updatedAt: Date
}

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case subscriptionRequired
    case networkError
    case dataCorruption
    case conflictResolution
    
    var errorDescription: String? {
        switch self {
        case .subscriptionRequired:
            return "Sync requires a paid subscription"
        case .networkError:
            return "Network connection error during sync"
        case .dataCorruption:
            return "Data corruption detected during sync"
        case .conflictResolution:
            return "Unable to resolve sync conflicts"
        }
    }
}