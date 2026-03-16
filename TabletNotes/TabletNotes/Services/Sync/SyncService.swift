import Combine
import Foundation
import SwiftData

@MainActor
final class SermonSyncEngine {
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

    private let localRepository: any SermonSyncLocalRepositoryProtocol
    private let remoteGateway: any SermonSyncRemoteGatewayProtocol
    private var currentSyncTask: Task<Void, Error>?

    init(
        localRepository: any SermonSyncLocalRepositoryProtocol,
        remoteGateway: any SermonSyncRemoteGatewayProtocol
    ) {
        self.localRepository = localRepository
        self.remoteGateway = remoteGateway
    }

    func sync(userId: UUID) async throws {
        if let currentSyncTask {
            try await currentSyncTask.value
            return
        }

        let task = Task { @MainActor in
            try await self.runSyncPhases(userId: userId)
        }

        currentSyncTask = task
        defer { currentSyncTask = nil }

        try await task.value
    }

    func deleteAllRemoteData(for userId: UUID) async throws {
        try await remoteGateway.deleteAllRemoteData(for: userId)
        try localRepository.resetCloudSyncState()
    }

    func updateLocalSermon(_ sermon: Sermon, with remoteData: RemoteSermonData) {
        localRepository.updateLocalSermon(sermon, with: remoteData)
    }

    private func runSyncPhases(userId: UUID) async throws {
        for phase in SyncPhase.allCases {
            print(phase.logMessage)
            try await run(phase, userId: userId)
        }
    }

    private func run(_ phase: SyncPhase, userId: UUID) async throws {
        switch phase {
        case .pushLocalChanges:
            try await pushLocalChanges(userId: userId)
        case .pullCloudChanges:
            try await pullCloudChanges(userId: userId)
        }
    }

    private func pushLocalChanges(userId: UUID) async throws {
        let sermonsToSync = try localRepository.sermonsNeedingSync()
        print("[SyncService] Found \(sermonsToSync.count) sermons marked for sync")

        for sermon in sermonsToSync {
            print("[SyncService] Syncing sermon: \(sermon.title)")
            try await pushSermonToCloud(sermon, userId: userId)
        }
    }

    private func pushSermonToCloud(_ sermon: Sermon, userId: UUID) async throws {
        let syncData = localRepository.syncData(for: sermon)
        let syncedAt = Date()

        if let remoteId = sermon.remoteId, !remoteId.isEmpty {
            try await remoteGateway.updateRemoteSermon(remoteId: remoteId, data: syncData)
            try localRepository.markSermonSynced(sermon, remoteId: remoteId, syncedAt: syncedAt)
            return
        }

        do {
            let newRemoteId = try await remoteGateway.createRemoteSermon(data: syncData)
            guard !newRemoteId.isEmpty else {
                print("[SyncService] ❌ createRemoteSermon returned empty remoteId")
                throw SyncError.conflictResolution
            }

            try localRepository.markSermonSynced(sermon, remoteId: newRemoteId, syncedAt: syncedAt)
        } catch SyncError.remoteAlreadyExists {
            let resolvedRemoteId = try await resolveExistingRemoteId(for: sermon.id, userId: userId)
            try localRepository.markSermonSynced(sermon, remoteId: resolvedRemoteId, syncedAt: syncedAt)
        }
    }

    private func resolveExistingRemoteId(for localId: UUID, userId: UUID) async throws -> String {
        let remoteSermons = try await remoteGateway.fetchRemoteSermons(for: userId)
        guard let existingRemoteId = remoteSermons.first(where: { $0.localId == localId })?.id else {
            print("[SyncService] ❌ Unable to resolve remote sermon for localId \(localId)")
            throw SyncError.conflictResolution
        }

        print("[SyncService] ✅ Resolved existing remote sermon ID: \(existingRemoteId)")
        return existingRemoteId
    }

    private func pullCloudChanges(userId: UUID) async throws {
        let remoteSermons = try await remoteGateway.fetchRemoteSermons(for: userId)
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

@MainActor
class SyncService: ObservableObject, SyncServiceProtocol {
    private let authService: any SyncUserProviding
    private let engine: SermonSyncEngine

    @Published private var syncStatus: String = "idle"
    @Published private var syncError: Error?

    var syncStatusPublisher: AnyPublisher<String, Never> {
        $syncStatus.eraseToAnyPublisher()
    }

    var errorPublisher: AnyPublisher<Error?, Never> {
        $syncError.eraseToAnyPublisher()
    }

    init(
        modelContext: ModelContext,
        supabaseService: SupabaseServiceProtocol,
        authService: any SyncUserProviding,
        localRepository: SermonSyncLocalRepository? = nil,
        remoteGateway: SermonSyncRemoteGatewayProtocol? = nil,
        engine: SermonSyncEngine? = nil
    ) {
        self.authService = authService
        let resolvedLocalRepository = localRepository ?? SermonSyncLocalRepository(modelContext: modelContext)
        let resolvedRemoteGateway = remoteGateway ?? SermonSyncRemoteGateway(supabaseService: supabaseService)
        self.engine = engine ?? SermonSyncEngine(
            localRepository: resolvedLocalRepository,
            remoteGateway: resolvedRemoteGateway
        )
    }

    func deleteAllCloudData() async {
        guard let currentUser = authService.currentUser else { return }

        do {
            try await engine.deleteAllRemoteData(for: currentUser.id)
        } catch {
            syncError = error
        }
    }

    func updateLocalSermon(_ sermon: Sermon, with remoteData: RemoteSermonData) {
        engine.updateLocalSermon(sermon, with: remoteData)
    }

    func syncAllData() async {
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
            try await engine.sync(userId: currentUser.id)
            syncStatus = "synced"
            print("[SyncService] ✅ Sync completed successfully")
        } catch {
            syncStatus = "error"
            syncError = error
            print("[SyncService] ❌ Sync failed: \(error.localizedDescription)")
        }
    }
}
