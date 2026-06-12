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

    /// Remote IDs deleted this session. A pull whose fetch snapshot predates a
    /// delete would otherwise recreate the sermon locally (ghost resurrection).
    private var deletedRemoteIds: Set<String> = []

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

    func deleteRemoteSermon(remoteId: String) async throws {
        // Wait for any in-flight sync: its pull phase may hold a fetch snapshot
        // that still contains this sermon and would recreate it locally.
        if let currentSyncTask {
            try? await currentSyncTask.value
        }

        // Tombstone before the network call so a sync that starts while the
        // delete is in flight skips this sermon during pull.
        deletedRemoteIds.insert(remoteId)
        do {
            try await remoteGateway.deleteRemoteSermon(remoteId: remoteId)
        } catch {
            // Delete failed — the remote row still exists and the local row is
            // kept, so resume syncing it normally.
            deletedRemoteIds.remove(remoteId)
            throw error
        }
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
        // Capture IDs only — holding live Sermon models across the awaits below
        // crashes if a sermon is deleted while a push is in flight (TAB-21).
        let sermonIdsToSync = try localRepository.sermonsNeedingSync().map(\.id)
        print("[SyncService] Found \(sermonIdsToSync.count) sermons marked for sync")

        for sermonId in sermonIdsToSync {
            guard let sermon = try localRepository.refreshSermon(id: sermonId) else {
                print("[SyncService] ⚠️ Sermon \(sermonId) disappeared before push, skipping")
                continue
            }
            print("[SyncService] Syncing sermon: \(sermon.title)")
            try await pushSermonToCloud(sermon, userId: userId)
        }
    }

    private func pushSermonToCloud(_ sermon: Sermon, userId: UUID) async throws {
        let sermonId = sermon.id
        let syncData = localRepository.syncData(for: sermon)
        let syncedAt = Date()
        let existingRemoteId = sermon.remoteId

        if let remoteId = existingRemoteId, !remoteId.isEmpty {
            try await remoteGateway.updateRemoteSermon(remoteId: remoteId, data: syncData)
            try markSermonSyncedIfStillPresent(
                sermonId: sermonId,
                remoteId: remoteId,
                syncedAt: syncedAt,
                scopes: syncData.scopes
            )
            return
        }

        do {
            let newRemoteId = try await remoteGateway.createRemoteSermon(data: syncData)
            guard !newRemoteId.isEmpty else {
                print("[SyncService] ❌ createRemoteSermon returned empty remoteId")
                throw SyncError.conflictResolution
            }

            try markSermonSyncedIfStillPresent(
                sermonId: sermonId,
                remoteId: newRemoteId,
                syncedAt: syncedAt,
                scopes: .all
            )
        } catch SyncError.remoteAlreadyExists {
            let resolvedRemoteId = try await resolveExistingRemoteId(for: sermonId, userId: userId)
            try markSermonSyncedIfStillPresent(
                sermonId: sermonId,
                remoteId: resolvedRemoteId,
                syncedAt: syncedAt,
                scopes: syncData.scopes
            )
        }
    }

    /// Re-fetches the sermon after a remote call so we never mutate a model that
    /// was deleted (or had children invalidated) while the network call was suspended.
    private func markSermonSyncedIfStillPresent(
        sermonId: UUID,
        remoteId: String?,
        syncedAt: Date,
        scopes: SermonSyncScopes
    ) throws {
        guard let sermon = try localRepository.refreshSermon(id: sermonId) else {
            print("[SyncService] ⚠️ Sermon \(sermonId) deleted during push, skipping sync bookkeeping")
            return
        }

        try localRepository.markSermonSynced(
            sermon,
            remoteId: remoteId,
            syncedAt: syncedAt,
            scopes: scopes
        )
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
            guard !deletedRemoteIds.contains(remoteSermon.id) else {
                print("[SyncService] ⏭️ Skipping remote sermon deleted this session: \(remoteSermon.id)")
                continue
            }
            print("[SyncService] Syncing remote sermon: \(remoteSermon.title)")
            try await pullSermonFromCloud(remoteSermon)
        }
    }

    private func pullSermonFromCloud(_ remoteSermon: RemoteSermonData) async throws {
        print("[SyncService] 📥 Syncing sermon from cloud: \(remoteSermon.title)")

        if let initialSermon = try localRepository.findSermon(remoteId: remoteSermon.id) {
            print("[SyncService] Found existing local sermon with remoteId: \(remoteSermon.id)")
            try await mergeRemoteSermon(remoteSermon, into: initialSermon)
            return
        }

        // A local row can share the localId without a remoteId yet (failed
        // push, race with create, restored backup). Creating a new row would
        // collide on the same id — link the remote row onto the existing one
        // instead, mirroring the push-side 409 resolution (TAB-35).
        if let unlinkedSermon = try localRepository.refreshSermon(id: remoteSermon.localId) {
            guard unlinkedSermon.remoteId?.isEmpty != false else {
                print("[SyncService] ⚠️ Local sermon \(remoteSermon.localId) is already linked to remote \(unlinkedSermon.remoteId ?? ""); skipping conflicting remote sermon \(remoteSermon.id)")
                return
            }

            print("[SyncService] 🔗 Linking remote sermon \(remoteSermon.id) to existing local sermon \(remoteSermon.localId)")
            // Full sync bookkeeping, not just remoteId: a row left with
            // syncStatus == "localOnly" would get re-marked for a full push
            // (e.g. by MigrationSafety) and overwrite the remote copy.
            try localRepository.markSermonSynced(
                unlinkedSermon,
                remoteId: remoteSermon.id,
                syncedAt: Date(),
                scopes: .none
            )
            try await mergeRemoteSermon(remoteSermon, into: unlinkedSermon)
            return
        }

        print("[SyncService] No existing local sermon found, creating new one")
        let localAudioURL = try await remoteGateway.downloadAudioFile(
            from: remoteSermon.audioFileURL,
            remotePath: remoteSermon.audioFilePath
        )
        try localRepository.createLocalSermon(from: remoteSermon, audioFileURL: localAudioURL)
    }

    private func mergeRemoteSermon(_ remoteSermon: RemoteSermonData, into initialSermon: Sermon) async throws {
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
    }
}

@MainActor
final class SyncService: SyncServiceProtocol {
    private let authService: any SyncUserProviding
    private let engine: SermonSyncEngine

    private var syncStatus: String = "idle"
    private var syncError: Error?

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

    func deleteRemoteSermon(remoteId: String) async throws {
        try await engine.deleteRemoteSermon(remoteId: remoteId)
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
