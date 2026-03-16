import Foundation
import SwiftData
import Testing
@testable import TabletNotes

@MainActor
struct SyncServiceMergeTests {
    final class MockSyncUserProvider: SyncUserProviding {
        var currentUser: User?

        init(currentUser: User?) {
            self.currentUser = currentUser
        }
    }

    final class CallRecorder {
        private(set) var events: [String] = []

        func record(_ event: String) {
            events.append(event)
        }
    }

    final class SyncLocalRepositorySpy: SermonSyncLocalRepositoryProtocol {
        private let recorder: CallRecorder
        private let syncDataBySermonId: [UUID: SermonSyncData]
        private(set) var sermonsToSync: [Sermon]
        private(set) var markedRemoteIds: [String] = []
        private(set) var markedScopes: [SermonSyncScopes] = []
        private var sermonsByRemoteId: [String: Sermon] = [:]

        init(
            recorder: CallRecorder,
            sermonsToSync: [Sermon],
            syncDataBySermonId: [UUID: SermonSyncData]
        ) {
            self.recorder = recorder
            self.sermonsToSync = sermonsToSync
            self.syncDataBySermonId = syncDataBySermonId
        }

        func sermonsNeedingSync() throws -> [Sermon] {
            recorder.record("local.sermonsNeedingSync")
            return sermonsToSync.filter(\.hasPendingSyncWork)
        }

        func syncData(for sermon: Sermon) -> SermonSyncData {
            recorder.record("local.syncData")
            guard let syncData = syncDataBySermonId[sermon.id] else {
                fatalError("Missing sync payload for sermon \(sermon.id)")
            }
            return syncData
        }

        func markSermonSynced(_ sermon: Sermon, remoteId: String?, syncedAt: Date, scopes: SermonSyncScopes) throws {
            recorder.record("local.markSermonSynced")
            markedScopes.append(scopes)
            sermon.lastSyncedAt = syncedAt
            sermon.clearPendingSync(
                metadata: scopes.metadata,
                notes: scopes.notes,
                transcript: scopes.transcript,
                summary: scopes.summary
            )
            sermon.refreshPendingSyncState()
            if let remoteId {
                sermon.remoteId = remoteId
                sermonsByRemoteId[remoteId] = sermon
                markedRemoteIds.append(remoteId)
            }
        }

        func findSermon(remoteId: String) throws -> Sermon? {
            recorder.record("local.findSermon")
            return sermonsByRemoteId[remoteId]
        }

        func refreshSermon(id: UUID) throws -> Sermon? {
            recorder.record("local.refreshSermon")
            return sermonsToSync.first(where: { $0.id == id }) ?? sermonsByRemoteId.values.first(where: { $0.id == id })
        }

        func markAudioDownloaded(fileName: String, for sermonId: UUID) throws {
            _ = fileName
            _ = sermonId
            recorder.record("local.markAudioDownloaded")
        }

        func updateLocalSermon(_ sermon: Sermon, with remoteData: RemoteSermonData) {
            _ = sermon
            _ = remoteData
            recorder.record("local.updateLocalSermon")
        }

        func createLocalSermon(from remoteData: RemoteSermonData, audioFileURL: URL) throws {
            _ = remoteData
            _ = audioFileURL
            recorder.record("local.createLocalSermon")
        }

        func resetCloudSyncState() throws {
            recorder.record("local.resetCloudSyncState")
        }

        func save() throws {
            recorder.record("local.save")
        }
    }

    final class SyncRemoteGatewaySpy: SermonSyncRemoteGatewayProtocol {
        private let recorder: CallRecorder
        private var fetchedRemoteSermonPages: [[RemoteSermonData]]
        private let createResult: Result<String, Error>
        private(set) var createCallCount = 0
        private(set) var fetchCallCount = 0
        private var blockedCreateContinuation: CheckedContinuation<Void, Never>?

        var shouldBlockCreate = false

        init(
            recorder: CallRecorder,
            createResult: Result<String, Error> = .success("remote-created"),
            fetchedRemoteSermonPages: [[RemoteSermonData]] = [[]]
        ) {
            self.recorder = recorder
            self.createResult = createResult
            self.fetchedRemoteSermonPages = fetchedRemoteSermonPages
        }

        func fetchRemoteSermons(for userId: UUID) async throws -> [RemoteSermonData] {
            _ = userId
            fetchCallCount += 1
            recorder.record("remote.fetch")

            guard !fetchedRemoteSermonPages.isEmpty else { return [] }
            return fetchedRemoteSermonPages.removeFirst()
        }

        func createRemoteSermon(data: SermonSyncData) async throws -> String {
            _ = data
            createCallCount += 1
            recorder.record("remote.create")

            if shouldBlockCreate {
                await withCheckedContinuation { continuation in
                    blockedCreateContinuation = continuation
                }
            }

            return try createResult.get()
        }

        func updateRemoteSermon(remoteId: String, data: SermonSyncData) async throws {
            _ = remoteId
            _ = data
            recorder.record("remote.update")
        }

        func downloadAudioFile(from url: URL, remotePath: String?) async throws -> URL {
            _ = remotePath
            recorder.record("remote.download")
            return url
        }

        func deleteAllRemoteData(for userId: UUID) async throws {
            _ = userId
            recorder.record("remote.deleteAllRemoteData")
        }

        func releaseBlockedCreate() {
            blockedCreateContinuation?.resume()
            blockedCreateContinuation = nil
            shouldBlockCreate = false
        }
    }

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

    private func makeSyncUser() -> User {
        User(email: "sync@example.com", name: "Sync User", subscriptionTier: "premium", subscriptionStatus: "active")
    }

    private func makeSyncService(modelContext: ModelContext) -> SyncService {
        SyncService(
            modelContext: modelContext,
            supabaseService: MockSupabaseService(),
            authService: MockSyncUserProvider(currentUser: makeSyncUser())
        )
    }

    private func makeSyncData(
        for sermon: Sermon,
        userId: UUID,
        scopes: SermonSyncScopes = .all
    ) -> SermonSyncData {
        SermonSyncData(
            id: sermon.id,
            title: sermon.title,
            audioFileURL: sermon.audioFileURL,
            date: sermon.date,
            serviceType: sermon.serviceType,
            speaker: sermon.speaker,
            transcriptionStatus: sermon.transcriptionStatus,
            summaryStatus: sermon.summaryStatus,
            isArchived: sermon.isArchived,
            userId: userId,
            updatedAt: sermon.updatedAt ?? Date(),
            notes: scopes.notes ? [] : nil,
            transcript: nil,
            summary: nil,
            scopes: scopes
        )
    }

    private func makeRemoteSermon(id: String, localId: UUID, userId: UUID, title: String = "Remote Sermon") -> RemoteSermonData {
        RemoteSermonData(
            id: id,
            localId: localId,
            title: title,
            audioFileURL: URL(fileURLWithPath: "/tmp/\(id).m4a"),
            audioFilePath: nil,
            date: Date(),
            serviceType: "Sunday Service",
            speaker: nil,
            transcriptionStatus: "complete",
            summaryStatus: "complete",
            isArchived: false,
            userId: userId,
            updatedAt: Date(),
            notes: nil,
            transcript: nil,
            summary: nil
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollIntervalNanoseconds: UInt64 = 25_000_000,
        condition: () -> Bool
    ) async -> Bool {
        var waited: UInt64 = 0

        while waited < timeoutNanoseconds {
            if condition() {
                return true
            }

            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            waited += pollIntervalNanoseconds
        }

        return condition()
    }

    @Test func updateLocalSermonPreservesDirtyLocalNotesWhileMergingRemoteNotes() throws {
        let modelContext = try makeModelContext()
        let syncService = makeSyncService(modelContext: modelContext)

        let sermon = Sermon(
            title: "Local Sermon",
            audioFileName: "local.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: "pending",
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            updatedAt: Date(),
            needsSync: true
        )
        modelContext.insert(sermon)

        let dirtyNoteId = UUID()
        let syncedNoteId = UUID()
        let remoteOnlyNoteId = UUID()

        let dirtyNote = Note(
            id: dirtyNoteId,
            text: "Local dirty note",
            timestamp: 12,
            remoteId: "remote-dirty-note",
            updatedAt: Date(),
            needsSync: true
        )
        dirtyNote.sermon = sermon
        modelContext.insert(dirtyNote)
        sermon.notes.append(dirtyNote)

        let syncedNote = Note(
            id: syncedNoteId,
            text: "Old synced note",
            timestamp: 24,
            remoteId: "remote-synced-note",
            updatedAt: Date().addingTimeInterval(-600),
            needsSync: false
        )
        syncedNote.sermon = sermon
        modelContext.insert(syncedNote)
        sermon.notes.append(syncedNote)

        let remoteSermon = RemoteSermonData(
            id: "remote-sermon",
            localId: sermon.id,
            title: "Remote Sermon",
            audioFileURL: URL(fileURLWithPath: "/tmp/remote.m4a"),
            audioFilePath: nil,
            date: sermon.date,
            serviceType: sermon.serviceType,
            speaker: nil,
            transcriptionStatus: "complete",
            summaryStatus: "complete",
            isArchived: false,
            userId: UUID(),
            updatedAt: Date().addingTimeInterval(300),
            notes: [
                RemoteNoteData(
                    id: "remote-dirty-note",
                    localId: dirtyNoteId,
                    text: "Remote dirty overwrite",
                    timestamp: 99
                ),
                RemoteNoteData(
                    id: "remote-synced-note",
                    localId: syncedNoteId,
                    text: "Remote synced note",
                    timestamp: 30
                ),
                RemoteNoteData(
                    id: "remote-new-note",
                    localId: remoteOnlyNoteId,
                    text: "Remote added note",
                    timestamp: 45
                )
            ],
            transcript: nil,
            summary: nil
        )

        syncService.updateLocalSermon(sermon, with: remoteSermon)

        #expect(sermon.notes.count == 3)

        guard let mergedDirtyNote = sermon.notes.first(where: { $0.id == dirtyNoteId }) else {
            Issue.record("Expected dirty local note to remain after merge")
            return
        }

        #expect(mergedDirtyNote.text == "Local dirty note")
        #expect(mergedDirtyNote.timestamp == 12)
        #expect(mergedDirtyNote.needsSync == true)

        guard let mergedSyncedNote = sermon.notes.first(where: { $0.id == syncedNoteId }) else {
            Issue.record("Expected synced note to remain after merge")
            return
        }

        #expect(mergedSyncedNote.text == "Remote synced note")
        #expect(mergedSyncedNote.timestamp == 30)
        #expect(mergedSyncedNote.needsSync == false)

        guard let remoteOnlyNote = sermon.notes.first(where: { $0.id == remoteOnlyNoteId }) else {
            Issue.record("Expected remote-only note to be added during merge")
            return
        }

        #expect(remoteOnlyNote.text == "Remote added note")
        #expect(remoteOnlyNote.remoteId == "remote-new-note")
    }

    @Test func updateLocalSermonPreservesDirtyLocalSummaryWhenRemoteParentIsNewer() throws {
        let modelContext = try makeModelContext()
        let syncService = makeSyncService(modelContext: modelContext)

        let sermon = Sermon(
            title: "Local Sermon",
            audioFileName: "local.m4a",
            date: Date(),
            serviceType: "Bible Study",
            syncStatus: "pending",
            transcriptionStatus: "complete",
            summaryStatus: "pending",
            updatedAt: Date(),
            needsSync: true
        )
        modelContext.insert(sermon)

        let localSummary = Summary(
            id: UUID(),
            title: "Local Summary Title",
            text: "Local summary body",
            type: "Bible Study",
            status: "complete",
            remoteId: "remote-summary",
            updatedAt: Date(),
            needsSync: true
        )
        modelContext.insert(localSummary)
        sermon.summary = localSummary
        sermon.summaryPreviewText = Sermon.makeSummaryPreview(from: localSummary.text)

        let remoteSermon = RemoteSermonData(
            id: "remote-sermon",
            localId: sermon.id,
            title: "Remote Sermon Title",
            audioFileURL: URL(fileURLWithPath: "/tmp/remote.m4a"),
            audioFilePath: nil,
            date: sermon.date,
            serviceType: sermon.serviceType,
            speaker: nil,
            transcriptionStatus: "complete",
            summaryStatus: "complete",
            isArchived: false,
            userId: UUID(),
            updatedAt: Date().addingTimeInterval(300),
            notes: nil,
            transcript: nil,
            summary: RemoteSummaryData(
                id: "remote-summary",
                localId: localSummary.id,
                title: "Remote Summary Title",
                text: "Remote summary body",
                type: "Bible Study",
                status: "complete"
            )
        )

        syncService.updateLocalSermon(sermon, with: remoteSermon)

        #expect(sermon.summary?.title == "Local Summary Title")
        #expect(sermon.summary?.text == "Local summary body")
        #expect(sermon.summary?.needsSync == true)
    }

    @Test func updateLocalSermonPreservesDirtyLocalMetadataWhenRemoteParentIsNewer() throws {
        let modelContext = try makeModelContext()
        let repository = SermonSyncLocalRepository(modelContext: modelContext)

        let sermon = Sermon(
            title: "Local Title",
            audioFileName: "local.m4a",
            date: Date(),
            serviceType: "Prayer Night",
            speaker: "Local Speaker",
            syncStatus: "pending",
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            isArchived: false,
            remoteId: "remote-sermon",
            updatedAt: Date(),
            needsSync: true,
            metadataNeedsSync: true
        )
        modelContext.insert(sermon)

        let remoteSermon = RemoteSermonData(
            id: "remote-sermon",
            localId: sermon.id,
            title: "Remote Title",
            audioFileURL: URL(fileURLWithPath: "/tmp/remote.m4a"),
            audioFilePath: nil,
            date: sermon.date,
            serviceType: "Sunday Service",
            speaker: "Remote Speaker",
            transcriptionStatus: "complete",
            summaryStatus: "complete",
            isArchived: true,
            userId: UUID(),
            updatedAt: Date().addingTimeInterval(300),
            notes: nil,
            transcript: nil,
            summary: nil
        )

        repository.updateLocalSermon(sermon, with: remoteSermon)

        #expect(sermon.title == "Local Title")
        #expect(sermon.serviceType == "Prayer Night")
        #expect(sermon.speaker == "Local Speaker")
        #expect(sermon.transcriptionStatus == "pending")
        #expect(sermon.summaryStatus == "pending")
        #expect(sermon.isArchived == false)
    }

    @Test func syncDataIncludesOnlyDirtyChildScopesForExistingRemoteSermon() throws {
        let modelContext = try makeModelContext()
        let repository = SermonSyncLocalRepository(modelContext: modelContext)

        let sermon = Sermon(
            title: "Scoped Sermon",
            audioFileName: "scoped.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: "pending",
            transcriptionStatus: "complete",
            summaryStatus: "complete",
            remoteId: "remote-sermon",
            updatedAt: Date()
        )
        modelContext.insert(sermon)

        let note = Note(text: "Synced note", timestamp: 10, remoteId: "remote-note", needsSync: false)
        note.sermon = sermon
        modelContext.insert(note)
        sermon.notes.append(note)

        let summary = Summary(
            title: "Local Summary",
            text: "Dirty summary body",
            type: "Sunday Service",
            status: "complete",
            remoteId: "remote-summary",
            updatedAt: Date(),
            needsSync: true
        )
        modelContext.insert(summary)
        sermon.summary = summary
        sermon.refreshPendingSyncState()

        let syncData = repository.syncData(for: sermon)

        #expect(syncData.scopes.metadata == false)
        #expect(syncData.scopes.notes == false)
        #expect(syncData.scopes.transcript == false)
        #expect(syncData.scopes.summary == true)
        #expect(syncData.notes == nil)
        #expect(syncData.transcript == nil)
        #expect(syncData.summary?.title == "Local Summary")
        #expect(syncData.summary?.text == "Dirty summary body")
    }

    @Test func markSermonSyncedClearsOnlyAcknowledgedScopes() throws {
        let modelContext = try makeModelContext()
        let repository = SermonSyncLocalRepository(modelContext: modelContext)
        let syncedAt = Date().addingTimeInterval(120)

        let sermon = Sermon(
            title: "Selective Sync Sermon",
            audioFileName: "selective.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: "pending",
            transcriptionStatus: "complete",
            summaryStatus: "complete",
            remoteId: "remote-sermon",
            updatedAt: Date(),
            needsSync: true,
            metadataNeedsSync: true,
            notesNeedSync: true,
            transcriptNeedsSync: true,
            summaryNeedsSync: true
        )
        modelContext.insert(sermon)

        let note = Note(text: "Dirty note", timestamp: 15, remoteId: "remote-note", updatedAt: Date(), needsSync: true)
        note.sermon = sermon
        modelContext.insert(note)
        sermon.notes.append(note)

        let transcript = Transcript(text: "Dirty transcript", updatedAt: Date(), needsSync: true)
        modelContext.insert(transcript)
        sermon.transcript = transcript

        let summary = Summary(
            title: "Dirty summary",
            text: "Dirty summary body",
            type: "Sunday Service",
            status: "complete",
            remoteId: "remote-summary",
            updatedAt: Date(),
            needsSync: true
        )
        modelContext.insert(summary)
        sermon.summary = summary
        sermon.refreshPendingSyncState()

        try repository.markSermonSynced(
            sermon,
            remoteId: "remote-sermon",
            syncedAt: syncedAt,
            scopes: SermonSyncScopes(metadata: false, notes: false, transcript: false, summary: true)
        )

        #expect(sermon.summaryNeedsSync == false)
        #expect(sermon.summary?.needsSync == false)
        #expect(sermon.summary?.updatedAt == syncedAt)
        #expect(sermon.metadataNeedsSync == true)
        #expect(sermon.notesNeedSync == true)
        #expect(sermon.transcriptNeedsSync == true)
        #expect(sermon.notes.first?.needsSync == true)
        #expect(sermon.transcript?.needsSync == true)
        #expect(sermon.hasPendingSyncWork == true)
    }

    @Test func syncEnginePushesLocalChangesBeforePullingCloudChanges() async throws {
        let user = makeSyncUser()
        let recorder = CallRecorder()
        let sermon = Sermon(
            title: "Local Sermon",
            audioFileName: "local.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: "pending",
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            updatedAt: Date(),
            needsSync: true
        )

        let localRepository = SyncLocalRepositorySpy(
            recorder: recorder,
            sermonsToSync: [sermon],
            syncDataBySermonId: [sermon.id: makeSyncData(for: sermon, userId: user.id)]
        )
        let remoteGateway = SyncRemoteGatewaySpy(recorder: recorder)
        let engine = SermonSyncEngine(localRepository: localRepository, remoteGateway: remoteGateway)

        try await engine.sync(userId: user.id)

        #expect(recorder.events == [
            "local.sermonsNeedingSync",
            "local.syncData",
            "remote.create",
            "local.markSermonSynced",
            "remote.fetch"
        ])
    }

    @Test func syncEngineResolvesCreateConflictsByMatchingLocalId() async throws {
        let user = makeSyncUser()
        let recorder = CallRecorder()
        let sermon = Sermon(
            title: "Conflict Sermon",
            audioFileName: "conflict.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: "pending",
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            updatedAt: Date(),
            needsSync: true
        )

        let localRepository = SyncLocalRepositorySpy(
            recorder: recorder,
            sermonsToSync: [sermon],
            syncDataBySermonId: [sermon.id: makeSyncData(for: sermon, userId: user.id)]
        )
        let remoteGateway = SyncRemoteGatewaySpy(
            recorder: recorder,
            createResult: .failure(SyncError.remoteAlreadyExists),
            fetchedRemoteSermonPages: [[makeRemoteSermon(id: "remote-existing", localId: sermon.id, userId: user.id)], []]
        )
        let engine = SermonSyncEngine(localRepository: localRepository, remoteGateway: remoteGateway)

        try await engine.sync(userId: user.id)

        #expect(localRepository.markedRemoteIds == ["remote-existing"])
        #expect(recorder.events == [
            "local.sermonsNeedingSync",
            "local.syncData",
            "remote.create",
            "remote.fetch",
            "local.markSermonSynced",
            "remote.fetch"
        ])
    }

    @Test func syncEngineCoalescesOverlappingRuns() async throws {
        let user = makeSyncUser()
        let recorder = CallRecorder()
        let sermon = Sermon(
            title: "Coalesced Sermon",
            audioFileName: "coalesced.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: "pending",
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            updatedAt: Date(),
            needsSync: true
        )

        let localRepository = SyncLocalRepositorySpy(
            recorder: recorder,
            sermonsToSync: [sermon],
            syncDataBySermonId: [sermon.id: makeSyncData(for: sermon, userId: user.id)]
        )
        let remoteGateway = SyncRemoteGatewaySpy(recorder: recorder)
        remoteGateway.shouldBlockCreate = true

        let engine = SermonSyncEngine(localRepository: localRepository, remoteGateway: remoteGateway)

        let firstRun = Task {
            try await engine.sync(userId: user.id)
        }

        let firstCreateStarted = await waitUntil {
            remoteGateway.createCallCount == 1
        }
        #expect(firstCreateStarted == true)

        let secondRun = Task {
            try await engine.sync(userId: user.id)
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(remoteGateway.createCallCount == 1)

        remoteGateway.releaseBlockedCreate()

        try await firstRun.value
        try await secondRun.value

        #expect(remoteGateway.createCallCount == 1)
        #expect(remoteGateway.fetchCallCount == 1)
        #expect(recorder.events == [
            "local.sermonsNeedingSync",
            "local.syncData",
            "remote.create",
            "local.markSermonSynced",
            "remote.fetch"
        ])
    }
}
