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
    /// Returns whether the pull phase restored every remote sermon without a
    /// per-item failure — so callers (cloud restore) only treat the sync as
    /// fully successful when the local copy actually matches the cloud.
    private var currentSyncTask: Task<Bool, Error>?
    private var lastPullFailureCount = 0
    /// Whether the most recent sync's push phase failed (e.g. upload rate limit).
    /// Recorded for visibility; it does NOT gate the restore-success signal —
    /// restore completeness is about the pull (TAB-55).
    private(set) var lastPushFailed = false

    /// Set when the upload endpoint 429s. Sync runs every 60s (BackgroundSyncManager);
    /// without this, a single rate-limit hit would retry the same doomed upload every
    /// tick until the server's window resets. Push is skipped entirely until this time.
    private var pushBlockedUntil: Date?

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

    /// Returns true only if the sync completed AND the pull restored every remote
    /// sermon without a per-item failure.
    @discardableResult
    func sync(userId: UUID) async throws -> Bool {
        if let currentSyncTask {
            return try await currentSyncTask.value
        }

        let task = Task { @MainActor () throws -> Bool in
            try await self.runSyncPhases(userId: userId)
            return self.lastPullFailureCount == 0
        }

        currentSyncTask = task
        defer { currentSyncTask = nil }

        return try await task.value
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
        lastPullFailureCount = 0
        lastPushFailed = false

        // Push and pull are independent. A push failure (e.g. the upload rate
        // limit returning 429) must NOT abort the pull — otherwise a restore can
        // never complete, because the remaining cloud sermons never come down
        // (TAB-55). Unpushed local changes stay marked dirty and retry next sync.
        print(SyncPhase.pushLocalChanges.logMessage)
        do {
            try await pushLocalChanges(userId: userId)
        } catch {
            lastPushFailed = true
            print("[SyncService] ⚠️ Push phase failed; pulling anyway (local changes stay queued for retry): \(error.localizedDescription)")
        }

        print(SyncPhase.pullCloudChanges.logMessage)
        // A pull-fetch failure is a real sync failure and still propagates.
        try await pullCloudChanges(userId: userId)
    }

    private func pushLocalChanges(userId: UUID) async throws {
        if let blockedUntil = pushBlockedUntil, Date() < blockedUntil {
            print("[SyncService] ⏳ Skipping push phase — rate limited until \(blockedUntil)")
            throw SyncError.rateLimited(retryAfter: blockedUntil.timeIntervalSinceNow)
        }
        pushBlockedUntil = nil

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
            do {
                try await pushSermonToCloud(sermon, userId: userId)
            } catch SyncError.rateLimited(let retryAfter) {
                // Every remaining sermon would hit the same per-user window —
                // stop this cycle and suppress retries until it resets.
                pushBlockedUntil = Date().addingTimeInterval(retryAfter)
                print("[SyncService] ⚠️ Upload rate limited; pausing push until \(pushBlockedUntil!)")
                throw SyncError.rateLimited(retryAfter: retryAfter)
            }
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
            let createResult = try await remoteGateway.createRemoteSermon(data: syncData)
            guard !createResult.remoteId.isEmpty else {
                print("[SyncService] ❌ createRemoteSermon returned empty remoteId")
                throw SyncError.conflictResolution
            }

            // Clear only the scopes the backend acknowledged — a failed child
            // insert stays dirty and is re-pushed via update (TAB-34).
            try markSermonSyncedIfStillPresent(
                sermonId: sermonId,
                remoteId: createResult.remoteId,
                syncedAt: syncedAt,
                scopes: createResult.syncedScopes
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

        // Isolate failures per sermon: restoring a large library (e.g. after a
        // store reset) must not be aborted by a single bad audio download or row
        // (TAB-53). Skipped sermons are retried on the next sync.
        var failures = 0
        for remoteSermon in remoteSermons {
            guard !deletedRemoteIds.contains(remoteSermon.id) else {
                print("[SyncService] ⏭️ Skipping remote sermon deleted this session: \(remoteSermon.id)")
                continue
            }
            print("[SyncService] Syncing remote sermon: \(remoteSermon.title)")
            do {
                try await pullSermonFromCloud(remoteSermon)
            } catch {
                failures += 1
                print("[SyncService] ⚠️ Failed to pull sermon \(remoteSermon.id) (\(remoteSermon.title)), continuing: \(error.localizedDescription)")
            }
        }
        lastPullFailureCount = failures
        if failures > 0 {
            print("[SyncService] ⚠️ Pull completed with \(failures)/\(remoteSermons.count) sermon(s) skipped; will retry next sync")
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
        // Create the metadata row first so the sermon is restored (and visible)
        // even if the audio download is slow or fails — the audio is fetched next
        // and any miss is re-tried by mergeRemoteSermon on a later sync (TAB-53).
        // This also lets a large library populate quickly instead of one row per
        // completed audio download.
        try localRepository.createLocalSermon(from: remoteSermon, audioFileURL: remoteSermon.audioFileURL)
        do {
            let localAudioURL = try await remoteGateway.downloadAudioFile(
                from: remoteSermon.audioFileURL,
                remotePath: remoteSermon.audioFilePath
            )
            try localRepository.markAudioDownloaded(
                fileName: localAudioURL.lastPathComponent,
                for: remoteSermon.localId
            )
        } catch {
            print("[SyncService] ⚠️ Audio download failed for new sermon \(remoteSermon.id); metadata kept, will retry next sync: \(error.localizedDescription)")
        }
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
        await syncAllDataReportingSuccess()
    }

    @discardableResult
    func syncAllDataReportingSuccess() async -> Bool {
        print("[SyncService] 🔄 Starting full sync...")

        guard let currentUser = authService.currentUser else {
            print("[SyncService] ❌ No current user - cannot sync")
            syncError = SyncError.subscriptionRequired
            return false
        }

        print("[SyncService] Current user: \(currentUser.email), canSync: \(currentUser.canSync)")

        guard currentUser.canSync else {
            print("[SyncService] ❌ User cannot sync (requires Premium subscription)")
            syncError = SyncError.subscriptionRequired
            return false
        }

        syncStatus = "syncing"
        syncError = nil

        do {
            // Fully successful only if the pull restored every remote sermon —
            // per-item pull failures must not be reported as success, or cloud
            // restore would clear its recovery flags on an incomplete restore.
            let fullySucceeded = try await engine.sync(userId: currentUser.id)
            syncStatus = fullySucceeded ? "synced" : "error"
            print("[SyncService] \(fullySucceeded ? "✅ Sync completed successfully" : "⚠️ Sync completed with skipped sermons")")
            return fullySucceeded
        } catch {
            syncStatus = "error"
            syncError = error
            print("[SyncService] ❌ Sync failed: \(error.localizedDescription)")
            return false
        }
    }
}
