import Combine
import Foundation
import SwiftData

@MainActor
class SyncService: ObservableObject, SyncServiceProtocol {
    private enum SyncPhase: String, CaseIterable {
        case pushLocalChanges
        case pullCloudChanges

        var logMessage: String {
            switch self {
            case .pushLocalChanges:
                return "[SyncService] 📤 Pushing local changes..."
            case .pullCloudChanges:
                return "[SyncService] 📥 Pulling cloud changes..."
            }
        }
    }

    private let authService: AuthenticationManager
    private let localRepository: SermonSyncLocalRepository
    private let remoteGateway: SermonSyncRemoteGatewayProtocol

    @Published private var syncStatus: String = "idle"
    @Published private var syncError: Error?
    private var isSyncInProgress = false

    var syncStatusPublisher: AnyPublisher<String, Never> {
        $syncStatus.eraseToAnyPublisher()
    }

    var errorPublisher: AnyPublisher<Error?, Never> {
        $syncError.eraseToAnyPublisher()
    }

    init(
        modelContext: ModelContext,
        supabaseService: SupabaseServiceProtocol,
        authService: AuthenticationManager,
        localRepository: SermonSyncLocalRepository? = nil,
        remoteGateway: SermonSyncRemoteGatewayProtocol? = nil
    ) {
        self.authService = authService
        self.localRepository = localRepository ?? SermonSyncLocalRepository(modelContext: modelContext)
        self.remoteGateway = remoteGateway ?? SermonSyncRemoteGateway(supabaseService: supabaseService)
    }

    func syncAllData() async {
        guard !isSyncInProgress else {
            print("[SyncService] ⏭️ Sync already in progress, skipping duplicate trigger")
            return
        }

        isSyncInProgress = true
        defer { isSyncInProgress = false }

        await performFullSync()
    }

    func deleteAllCloudData() async {
        guard let currentUser = authService.currentUser else { return }

        do {
            try await remoteGateway.deleteAllRemoteData(for: currentUser.id)
            try localRepository.resetCloudSyncState()
        } catch {
            syncError = error
        }
    }

    func updateLocalSermon(_ sermon: Sermon, with remoteData: RemoteSermonData) {
        localRepository.updateLocalSermon(sermon, with: remoteData)
    }

    private func performFullSync() async {
        print("[SyncService] 🔄 Starting full sync...")

        guard let currentUser = authService.currentUser else {
            print("[SyncService] ❌ No current user - cannot sync")
            syncError = SyncError.subscriptionRequired
            return
        }

        print("[SyncService] Current user: \(currentUser.email), canSync: \(currentUser.canSync)")

        guard currentUser.canSync else {
            print("[SyncService] ❌ User cannot sync (requires Premium subscription)")
            syncError = SyncError.subscriptionRequired
            return
        }

        syncStatus = "syncing"
        syncError = nil

        do {
            try await runSyncPhases()
            syncStatus = "synced"
            print("[SyncService] ✅ Sync completed successfully")
        } catch {
            syncStatus = "error"
            syncError = error
            print("[SyncService] ❌ Sync failed: \(error.localizedDescription)")
        }
    }

    private func runSyncPhases() async throws {
        for phase in SyncPhase.allCases {
            print(phase.logMessage)
            try await run(phase)
        }
    }

    private func run(_ phase: SyncPhase) async throws {
        switch phase {
        case .pushLocalChanges:
            try await pushLocalChanges()
        case .pullCloudChanges:
            try await pullCloudChanges()
        }
    }

    private func pushLocalChanges() async throws {
        let sermonsToSync = try localRepository.sermonsNeedingSync()
        print("[SyncService] Found \(sermonsToSync.count) sermons marked for sync")

        for sermon in sermonsToSync {
            print("[SyncService] Syncing sermon: \(sermon.title)")
            try await pushSermonToCloud(sermon)
        }
    }

    private func pushSermonToCloud(_ sermon: Sermon) async throws {
        let syncData = localRepository.syncData(for: sermon)
        let syncedAt = Date()

        if let remoteId = sermon.remoteId, !remoteId.isEmpty {
            try await remoteGateway.updateRemoteSermon(remoteId: remoteId, data: syncData)
            try localRepository.markSermonSynced(sermon, syncedAt: syncedAt)
            return
        }

        let newRemoteId = try await remoteGateway.createRemoteSermon(data: syncData)
        guard !newRemoteId.isEmpty else {
            print("[SyncService] ❌ createRemoteSermon returned empty remoteId")
            throw SyncError.conflictResolution
        }

        try localRepository.markSermonSynced(sermon, remoteId: newRemoteId, syncedAt: syncedAt)
    }

    private func pullCloudChanges() async throws {
        guard let currentUser = authService.currentUser else { return }

        let remoteSermons = try await remoteGateway.fetchRemoteSermons(for: currentUser.id)
        print("[SyncService] Found \(remoteSermons.count) remote sermons to pull")

        for remoteSermon in remoteSermons {
            print("[SyncService] Syncing remote sermon: \(remoteSermon.title)")
            try await pullSermonFromCloud(remoteSermon)
        }
    }

    private func pullSermonFromCloud(_ remoteSermon: RemoteSermonData) async throws {
        print("[SyncService] 📥 Syncing sermon from cloud: \(remoteSermon.title)")

        if let initialSermon = try localRepository.findSermon(remoteId: remoteSermon.id) {
            print("[SyncService] Found existing local sermon with remoteId: \(remoteSermon.id)")
            let localSermonId = initialSermon.id

            if !initialSermon.audioFileExists {
                print("[SyncService] Audio file missing locally, attempting download...")
                do {
                    let localAudioURL = try await remoteGateway.downloadAudioFile(
                        from: remoteSermon.audioFileURL,
                        remotePath: remoteSermon.audioFilePath
                    )
                    try localRepository.markAudioDownloaded(
                        fileName: localAudioURL.lastPathComponent,
                        for: localSermonId
                    )
                    print("[SyncService] ✅ Audio file downloaded successfully")
                } catch {
                    print("[SyncService] ⚠️ Audio download failed, but continuing with sermon sync: \(error.localizedDescription)")
                }
            }

            guard let existingSermon = try localRepository.refreshSermon(id: localSermonId) else {
                print("[SyncService] ⚠️ Local sermon disappeared during sync, skipping update")
                return
            }

            if remoteSermon.updatedAt > (existingSermon.updatedAt ?? Date.distantPast) {
                print("[SyncService] Remote sermon is newer, updating local copy")
                localRepository.updateLocalSermon(existingSermon, with: remoteSermon)
                try localRepository.save()
            } else {
                print("[SyncService] Local sermon is up to date")
            }

            return
        }

        print("[SyncService] No existing local sermon found, creating new one")
        let localAudioURL = try await remoteGateway.downloadAudioFile(
            from: remoteSermon.audioFileURL,
            remotePath: remoteSermon.audioFilePath
        )
        try localRepository.createLocalSermon(from: remoteSermon, audioFileURL: localAudioURL)
    }
}
