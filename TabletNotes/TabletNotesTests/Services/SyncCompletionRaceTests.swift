import Foundation
import SwiftData
import Testing
@testable import TabletNotes

/// Regression tests for TAB-95: processing completed during the minutes-long
/// create push must not be lost. Three cooperating defects produced Sunday's
/// poisoned prod row: the create's ack blanket-cleared scopes dirtied while
/// the push was in flight, the create payload carried no `updatedAt` so the
/// server stamped a newer time, and the pull then walked local terminal
/// statuses back to the server's stale pre-completion values.
struct SyncCompletionRaceTests {

    @MainActor
    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([
            Sermon.self,
            Note.self,
            Transcript.self,
            Summary.self,
            ProcessingJob.self,
            TranscriptSegment.self,
            ChatMessage.self,
            User.self,
            UserNotificationSettings.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }

    /// Gateway double that runs a caller-supplied action while the create is
    /// suspended on the (in production, minutes-long) upload + POST.
    final class MutatingCreateGateway: SermonSyncRemoteGatewayProtocol {
        var onCreate: (() -> Void)?

        func fetchRemoteSermons(for userId: UUID) async throws -> [RemoteSermonData] { [] }

        func createRemoteSermon(data: SermonSyncData) async throws -> RemoteSermonCreateResult {
            onCreate?()
            return RemoteSermonCreateResult(remoteId: "remote-created", syncedScopes: .all)
        }

        func updateRemoteSermon(remoteId: String, data: SermonSyncData) async throws -> SermonSyncScopes { .all }
        func downloadAudioFile(from url: URL, remotePath: String?) async throws -> URL { url }
        func deleteRemoteSermon(remoteId: String) async throws {}
        func deleteAllRemoteData(for userId: UUID) async throws {}
    }

    // MARK: - Defect 1: the ack must not clear scopes dirtied mid-push

    /// The exact prod incident: transcription+summary completed while the
    /// create (audio upload included) was in flight and marked their scopes
    /// dirty; the returning ack wiped those flags, so complete/complete was
    /// never pushed. The ack must keep everything dirty when the sermon
    /// changed after the snapshot — over-pushing next sync is harmless,
    /// losing the completion is not.
    @MainActor
    @Test func createAckKeepsScopesDirtiedDuringPush() async throws {
        let modelContext = try makeModelContext()
        let repository = SermonSyncLocalRepository(modelContext: modelContext)

        let sermon = Sermon(
            title: "Sunday Sermon",
            audioFileName: "sunday.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: "pending",
            transcriptionStatus: "processing",
            summaryStatus: "pending",
            userId: UUID(),
            updatedAt: Date(),
            needsSync: true,
            metadataNeedsSync: true
        )
        modelContext.insert(sermon)
        try modelContext.save()

        let gateway = MutatingCreateGateway()
        gateway.onCreate = {
            // Transcription + summary finish while the push is suspended.
            sermon.transcriptionStatus = "complete"
            sermon.summaryStatus = "complete"
            sermon.markPendingSync(
                metadata: true,
                transcript: true,
                summary: true,
                updatedAt: Date().addingTimeInterval(1)
            )
            try? modelContext.save()
        }

        let engine = SermonSyncEngine(localRepository: repository, remoteGateway: gateway)
        _ = try await engine.sync(userId: UUID())

        // The remote row exists, so record its id — but nothing the mid-push
        // completion dirtied may be acked away.
        #expect(sermon.remoteId == "remote-created")
        #expect(sermon.metadataNeedsSync)
        #expect(sermon.transcriptNeedsSync)
        #expect(sermon.summaryNeedsSync)
        #expect(sermon.needsSync)
    }

    /// Control: when nothing changes mid-push, the ack clears the pushed
    /// scopes exactly as before.
    @MainActor
    @Test func createAckStillClearsScopesWhenNothingChangedMidPush() async throws {
        let modelContext = try makeModelContext()
        let repository = SermonSyncLocalRepository(modelContext: modelContext)

        let sermon = Sermon(
            title: "Quiet Sermon",
            audioFileName: "quiet.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: "pending",
            transcriptionStatus: "processing",
            summaryStatus: "pending",
            userId: UUID(),
            updatedAt: Date(),
            needsSync: true,
            metadataNeedsSync: true
        )
        modelContext.insert(sermon)
        try modelContext.save()

        let engine = SermonSyncEngine(
            localRepository: repository,
            remoteGateway: MutatingCreateGateway()
        )
        _ = try await engine.sync(userId: UUID())

        #expect(sermon.remoteId == "remote-created")
        #expect(!sermon.metadataNeedsSync)
        #expect(!sermon.needsSync)
        #expect(sermon.syncStatus == "synced")
    }

    // MARK: - Defect 2: the create payload must carry the snapshot timestamp

    /// Without `updatedAt` in the create body, `create-sermon.js` stamps
    /// server time at POST-completion — after the entire audio upload — and
    /// the next pull treats that stale row as newer than local state.
    @MainActor
    @Test func createPayloadCarriesSnapshotUpdatedAt() throws {
        // Non-zero fractional seconds on purpose: the default ISO8601
        // formatter silently truncates them, shifting the stored row up to
        // ~1s earlier than the snapshot (review round 1).
        let snapshotUpdatedAt = Date(timeIntervalSince1970: 1_787_000_000.625)
        let data = SermonSyncData(
            id: UUID(),
            title: "Payload Sermon",
            audioFileURL: URL(fileURLWithPath: "/tmp/payload.m4a"),
            date: Date(),
            serviceType: "Sunday Service",
            speaker: nil,
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            isArchived: false,
            userId: UUID(),
            updatedAt: snapshotUpdatedAt,
            notes: nil,
            transcript: nil,
            summary: nil,
            scopes: .all
        )

        let payload = SermonSyncRemoteGateway.createSermonPayload(
            data: data,
            audioFilePath: "user/payload.m4a",
            audioFileUrl: "https://example.com/payload.m4a",
            audioFileName: "payload.m4a",
            fileSize: 4096
        )

        let serialized = payload["updatedAt"] as? String
        #expect(serialized == SermonSyncRemoteGateway.updatedAtFormatter.string(from: snapshotUpdatedAt))
        #expect(serialized?.contains(".625") == true) // fractional seconds retained
        // Sanity: extraction kept the load-bearing fields intact.
        #expect(payload["localId"] as? String == data.id.uuidString)
        #expect(payload["audioFilePath"] as? String == "user/payload.m4a")
        #expect(payload["transcriptionStatus"] as? String == "pending")
    }

    // MARK: - Defect 3: the pull must not walk a local terminal status back

    private func makeRemoteSermon(
        for sermon: Sermon,
        transcriptionStatus: String,
        summaryStatus: String,
        title: String = "Title From Server"
    ) -> RemoteSermonData {
        RemoteSermonData(
            id: "remote-1",
            localId: sermon.id,
            title: title,
            audioFileURL: URL(string: "https://example.com/audio.m4a")!,
            audioFilePath: nil,
            date: sermon.date,
            serviceType: sermon.serviceType,
            speaker: nil,
            transcriptionStatus: transcriptionStatus,
            summaryStatus: summaryStatus,
            isArchived: false,
            userId: sermon.userId ?? UUID(),
            updatedAt: Date().addingTimeInterval(60),
            notes: nil,
            transcript: nil,
            summary: nil
        )
    }

    /// The stale server row (its statuses frozen at create time) arrives with
    /// a newer timestamp. Terminal local statuses must survive it; the rest
    /// of the metadata still applies.
    @MainActor
    @Test func pullKeepsLocalTerminalStatusOverStaleNonTerminal() async throws {
        let modelContext = try makeModelContext()
        let repository = SermonSyncLocalRepository(modelContext: modelContext)

        let sermon = Sermon(
            title: "Local Title",
            audioFileName: "done.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: "synced",
            transcriptionStatus: "complete",
            summaryStatus: "complete",
            userId: UUID(),
            remoteId: "remote-1",
            updatedAt: Date()
        )
        modelContext.insert(sermon)
        try modelContext.save()

        repository.updateLocalSermon(
            sermon,
            with: makeRemoteSermon(for: sermon, transcriptionStatus: "processing", summaryStatus: "pending")
        )

        #expect(sermon.transcriptionStatus == "complete")
        #expect(sermon.summaryStatus == "complete")
        #expect(sermon.title == "Title From Server") // metadata still applies
    }

    /// Forward transitions keep working: a remote terminal value replaces a
    /// local non-terminal one.
    @MainActor
    @Test func pullAppliesRemoteTerminalOverLocalNonTerminal() async throws {
        let modelContext = try makeModelContext()
        let repository = SermonSyncLocalRepository(modelContext: modelContext)

        let sermon = Sermon(
            title: "Local Title",
            audioFileName: "inflight.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: "synced",
            transcriptionStatus: "processing",
            summaryStatus: "pending",
            userId: UUID(),
            remoteId: "remote-1",
            updatedAt: Date()
        )
        modelContext.insert(sermon)
        try modelContext.save()

        repository.updateLocalSermon(
            sermon,
            with: makeRemoteSermon(for: sermon, transcriptionStatus: "complete", summaryStatus: "complete")
        )

        #expect(sermon.transcriptionStatus == "complete")
        #expect(sermon.summaryStatus == "complete")
    }

    /// TAB-91's revive flow must survive this guard: the server clears
    /// failed_permanent on a deliberate retry, and the pull is how the client
    /// learns about it. failed_permanent is NOT a protected local status.
    @MainActor
    @Test func pullClearsFailedPermanentWhenServerRevivesJob() async throws {
        let modelContext = try makeModelContext()
        let repository = SermonSyncLocalRepository(modelContext: modelContext)

        let sermon = Sermon(
            title: "Local Title",
            audioFileName: "revived.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: "synced",
            transcriptionStatus: "failed_permanent",
            summaryStatus: "pending",
            userId: UUID(),
            remoteId: "remote-1",
            updatedAt: Date()
        )
        modelContext.insert(sermon)
        try modelContext.save()

        repository.updateLocalSermon(
            sermon,
            with: makeRemoteSermon(for: sermon, transcriptionStatus: "processing", summaryStatus: "pending")
        )

        #expect(sermon.transcriptionStatus == "processing")
    }
}

/// Regression tests for TAB-98: the ack's staleness protection must key on
/// per-scope write epochs, not `updatedAt`. The witnessed incident (the
/// TAB-97 repair's write stranded on-device, 2026-08-31): `updatedAt` is
/// re-stamped by every scope write AND overwritten with remote values by the
/// pull, so overlapping sync cycles can walk it backward past the snapshot
/// anchor — the timestamp guard goes blind and the ack clears flags for data
/// that never left the device.
struct SyncScopeEpochRaceTests {

    @MainActor
    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([
            Sermon.self,
            Note.self,
            Transcript.self,
            Summary.self,
            ProcessingJob.self,
            TranscriptSegment.self,
            ChatMessage.self,
            User.self,
            UserNotificationSettings.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }

    final class MutatingCreateGateway: SermonSyncRemoteGatewayProtocol {
        var onCreate: (() -> Void)?

        func fetchRemoteSermons(for userId: UUID) async throws -> [RemoteSermonData] { [] }

        func createRemoteSermon(data: SermonSyncData) async throws -> RemoteSermonCreateResult {
            onCreate?()
            return RemoteSermonCreateResult(remoteId: "remote-created", syncedScopes: .all)
        }

        func updateRemoteSermon(remoteId: String, data: SermonSyncData) async throws -> SermonSyncScopes { .all }
        func downloadAudioFile(from url: URL, remotePath: String?) async throws -> URL { url }
        func deleteRemoteSermon(remoteId: String) async throws {}
        func deleteAllRemoteData(for userId: UUID) async throws {}
    }

    @MainActor
    private func makeDirtySermon(in modelContext: ModelContext) throws -> Sermon {
        let sermon = Sermon(
            title: "Epoch Sermon",
            audioFileName: "epoch.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: "pending",
            transcriptionStatus: "processing",
            summaryStatus: "pending",
            userId: UUID(),
            updatedAt: Date(),
            needsSync: true,
            metadataNeedsSync: true
        )
        modelContext.insert(sermon)
        try modelContext.save()
        return sermon
    }

    /// The witnessed hole: a scope write lands mid-push, and then the pull
    /// (running in an overlapping cycle) overwrites `updatedAt` with a stale
    /// remote value — older than the push snapshot's anchor. A timestamp
    /// guard sees "nothing changed" and acks the write away; the epoch guard
    /// must not.
    @MainActor
    @Test func ackKeepsAMidPushWriteWhoseTimestampWasWalkedBack() async throws {
        let modelContext = try makeModelContext()
        let repository = SermonSyncLocalRepository(modelContext: modelContext)
        let sermon = try makeDirtySermon(in: modelContext)

        let gateway = MutatingCreateGateway()
        gateway.onCreate = {
            // The racing local write (the TAB-97 repair in the incident).
            sermon.summaryStatus = "complete"
            sermon.markPendingSync(metadata: true, updatedAt: Date().addingTimeInterval(1))
            // The overlapping cycle's pull stomps updatedAt with the stale
            // remote row's value — exactly what updateLocalSermon does
            // (`sermon.updatedAt = remoteData.updatedAt`) regardless of
            // dirty flags.
            sermon.updatedAt = Date().addingTimeInterval(-3_600)
            try? modelContext.save()
        }

        let engine = SermonSyncEngine(localRepository: repository, remoteGateway: gateway)
        _ = try await engine.sync(userId: UUID())

        #expect(sermon.remoteId == "remote-created")
        #expect(sermon.metadataNeedsSync)
        #expect(sermon.needsSync)
    }

    /// Per-scope precision: a mid-push write to ONE scope keeps only that
    /// scope dirty; the scopes the push actually delivered, unchanged since
    /// the snapshot, are acked as synced. (TAB-95's all-or-nothing guard
    /// kept everything and re-pushed data that had already landed.)
    @MainActor
    @Test func ackClearsDeliveredScopesAndKeepsOnlyTheRacedOne() async throws {
        let modelContext = try makeModelContext()
        let repository = SermonSyncLocalRepository(modelContext: modelContext)
        let sermon = try makeDirtySermon(in: modelContext)

        let gateway = MutatingCreateGateway()
        gateway.onCreate = {
            // Only the notes scope is written mid-push.
            sermon.markPendingSync(notes: true, updatedAt: Date().addingTimeInterval(1))
            try? modelContext.save()
        }

        let engine = SermonSyncEngine(localRepository: repository, remoteGateway: gateway)
        _ = try await engine.sync(userId: UUID())

        #expect(sermon.remoteId == "remote-created")
        #expect(!sermon.metadataNeedsSync)
        #expect(sermon.notesNeedSync)
        #expect(sermon.needsSync)
    }
}
