import Foundation
import Testing
@testable import TabletNotes

struct ResumableUploadPathResolverTests {
    private func makeTempAudioFile(named suffix: String = "") throws -> (url: URL, length: Int64, mtime: TimeInterval) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("resolver-\(suffix)-\(UUID().uuidString).m4a")
        try Data(repeating: 0xAB, count: 12).write(to: url)
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return (url, Int64(values.fileSize!), values.contentModificationDate!.timeIntervalSince1970)
    }

    @Test func firstAttemptMintsAPath() async throws {
        let file = try makeTempAudioFile(named: "mint")
        defer { try? FileManager.default.removeItem(at: file.url) }

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "resolver")
        let ownerId = UUID()

        var mintCalls = 0
        let plan = try await ResumableUploadPathResolver.plan(
            sermonLocalId: UUID(),
            localFile: file.url,
            fileLength: file.length,
            ownerUserId: ownerId,
            resumeStore: store,
            mint: {
                mintCalls += 1
                return ("user/abc.m4a", true)
            }
        )

        #expect(plan.didMint)
        #expect(plan.objectPath == "user/abc.m4a")
        #expect(plan.upsert)
        #expect(mintCalls == 1)
    }

    @Test func concurrentPlansForSameSermonCoalesceToOneMint() async throws {
        let file = try makeTempAudioFile(named: "coalesce")
        defer { try? FileManager.default.removeItem(at: file.url) }

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "resolver")
        let sermonId = UUID()
        let ownerId = UUID()

        var mintCalls = 0
        var releaseMint: CheckedContinuation<Void, Never>?
        let mint: () async throws -> (String, Bool) = {
            mintCalls += 1
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                releaseMint = cont
            }
            return ("user/coalesced.m4a", true)
        }

        async let first = ResumableUploadPathResolver.plan(
            sermonLocalId: sermonId,
            localFile: file.url,
            fileLength: file.length,
            ownerUserId: ownerId,
            resumeStore: store,
            mint: mint
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        async let second = ResumableUploadPathResolver.plan(
            sermonLocalId: sermonId,
            localFile: file.url,
            fileLength: file.length,
            ownerUserId: ownerId,
            resumeStore: store,
            mint: mint
        )
        try await Task.sleep(nanoseconds: 20_000_000)
        releaseMint?.resume()

        let planA = try await first
        let planB = try await second
        #expect(planA.objectPath == "user/coalesced.m4a")
        #expect(planB.objectPath == "user/coalesced.m4a")
        #expect(mintCalls == 1)
    }

    @Test func concurrentPlansForSameSermonWithDifferentFileIdentityDoNotCoalesce() async throws {
        let fileA = try makeTempAudioFile(named: "coalesce-a")
        let fileB = try makeTempAudioFile(named: "coalesce-b")
        defer {
            try? FileManager.default.removeItem(at: fileA.url)
            try? FileManager.default.removeItem(at: fileB.url)
        }

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "resolver")
        let sermonId = UUID()
        let ownerId = UUID()

        final class MintGate: @unchecked Sendable {
            private let lock = NSLock()
            private var waiters: [CheckedContinuation<Void, Never>] = []
            private(set) var mintCalls = 0

            func nextPathAndWait() async -> String {
                let path: String = {
                    lock.lock()
                    defer { lock.unlock() }
                    mintCalls += 1
                    return mintCalls == 1 ? "user/first.m4a" : "user/second.m4a"
                }()
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    lock.lock()
                    waiters.append(cont)
                    lock.unlock()
                }
                return path
            }

            func releaseOne() {
                lock.lock()
                let cont = waiters.isEmpty ? nil : waiters.removeFirst()
                lock.unlock()
                cont?.resume()
            }

            var callCount: Int {
                lock.lock()
                defer { lock.unlock() }
                return mintCalls
            }
        }

        let gate = MintGate()
        let mint: () async throws -> (String, Bool) = {
            let path = await gate.nextPathAndWait()
            return (path, true)
        }

        async let first = ResumableUploadPathResolver.plan(
            sermonLocalId: sermonId,
            localFile: fileA.url,
            fileLength: fileA.length,
            ownerUserId: ownerId,
            resumeStore: store,
            mint: mint
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        async let second = ResumableUploadPathResolver.plan(
            sermonLocalId: sermonId,
            localFile: fileB.url,
            fileLength: fileB.length,
            ownerUserId: ownerId,
            resumeStore: store,
            mint: mint
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(gate.callCount == 2)
        gate.releaseOne()
        gate.releaseOne()

        let planA = try await first
        let planB = try await second
        #expect(Set([planA.objectPath, planB.objectPath]) == Set(["user/first.m4a", "user/second.m4a"]))
        #expect(gate.callCount == 2)
    }

    @Test func resumeSkipsMintWhenARecordMatchesTheLocalFile() async throws {
        let file = try makeTempAudioFile(named: "resume")
        defer { try? FileManager.default.removeItem(at: file.url) }

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "resolver")
        let id = UUID()
        let ownerId = UUID()
        store.save(
            UploadResumeRecord(
                sermonLocalId: id,
                objectPath: "user/persisted.m4a",
                uploadURL: URL(string: "https://example.com/u"),
                uploadLength: file.length,
                filePath: file.url.path,
                fileModificationTime: file.mtime,
                taskIdentifier: 1,
                ownerUserId: ownerId,
                startedUnderFlag: true,
                upsert: true
            )
        )

        var mintCalls = 0
        let plan = try await ResumableUploadPathResolver.plan(
            sermonLocalId: id,
            localFile: file.url,
            fileLength: file.length,
            ownerUserId: ownerId,
            resumeStore: store,
            mint: {
                mintCalls += 1
                return ("user/should-not-use.m4a", false)
            }
        )

        #expect(!plan.didMint)
        #expect(plan.objectPath == "user/persisted.m4a")
        #expect(mintCalls == 0)
    }

    @Test func staleLocalFileRemintsAndDropsTheOldRecord() async throws {
        let file = try makeTempAudioFile(named: "stale")
        defer { try? FileManager.default.removeItem(at: file.url) }

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "resolver")
        let id = UUID()
        let ownerId = UUID()
        store.save(
            UploadResumeRecord(
                sermonLocalId: id,
                objectPath: "user/old.m4a",
                uploadURL: URL(string: "https://example.com/old"),
                uploadLength: file.length,
                filePath: file.url.path,
                fileModificationTime: file.mtime - 60,
                taskIdentifier: 1,
                ownerUserId: ownerId,
                startedUnderFlag: true,
                upsert: true
            )
        )

        var abandonCalls = 0
        var mintCalls = 0
        let plan = try await ResumableUploadPathResolver.plan(
            sermonLocalId: id,
            localFile: file.url,
            fileLength: file.length,
            ownerUserId: ownerId,
            resumeStore: store,
            mint: {
                mintCalls += 1
                return ("user/fresh.m4a", true)
            },
            abandonStaleRecord: { _ in
                abandonCalls += 1
            }
        )

        #expect(plan.didMint)
        #expect(plan.objectPath == "user/fresh.m4a")
        #expect(mintCalls == 1)
        #expect(abandonCalls == 1)
        #expect(store.record(for: id)?.objectPath == "user/fresh.m4a")
        #expect(store.record(for: id)?.uploadURL == nil)
    }

    @Test func mintPersistsPathAuthorityBeforeTusCreate() async throws {
        let file = try makeTempAudioFile(named: "persist")
        defer { try? FileManager.default.removeItem(at: file.url) }

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "resolver")
        let id = UUID()
        let ownerId = UUID()

        _ = try await ResumableUploadPathResolver.plan(
            sermonLocalId: id,
            localFile: file.url,
            fileLength: file.length,
            ownerUserId: ownerId,
            resumeStore: store,
            mint: { ("user/new.m4a", true) }
        )

        let saved = store.record(for: id)
        #expect(saved?.objectPath == "user/new.m4a")
        #expect(saved?.uploadURL == nil)
        #expect(saved?.matchesLocalFile(file.url, length: file.length) == true)
    }

    @Test func mintSkipsPersistWhenAdmissionClosed() async throws {
        let file = try makeTempAudioFile(named: "no-persist")
        defer { try? FileManager.default.removeItem(at: file.url) }

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "resolver")
        let id = UUID()
        let ownerId = UUID()

        let plan = try await ResumableUploadPathResolver.plan(
            sermonLocalId: id,
            localFile: file.url,
            fileLength: file.length,
            ownerUserId: ownerId,
            resumeStore: store,
            mint: { ("user/race.m4a", true) },
            mayPersistNewRecord: { false }
        )

        #expect(plan.didMint)
        #expect(plan.objectPath == "user/race.m4a")
        #expect(store.record(for: id) == nil)
    }

    @Test func differentOwnerRecordIsAbandonedBeforeRemint() async throws {
        let file = try makeTempAudioFile(named: "owner")
        defer { try? FileManager.default.removeItem(at: file.url) }

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "resolver")
        let id = UUID()
        let otherOwner = UUID()
        store.save(
            UploadResumeRecord(
                sermonLocalId: id,
                objectPath: "user/other.m4a",
                uploadURL: URL(string: "https://example.com/other"),
                uploadLength: file.length,
                filePath: file.url.path,
                fileModificationTime: file.mtime,
                taskIdentifier: 1,
                ownerUserId: otherOwner,
                startedUnderFlag: true,
                upsert: true
            )
        )

        var abandonCalls = 0
        let currentOwner = UUID()
        _ = try await ResumableUploadPathResolver.plan(
            sermonLocalId: id,
            localFile: file.url,
            fileLength: file.length,
            ownerUserId: currentOwner,
            resumeStore: store,
            mint: { ("user/new-owner.m4a", true) },
            abandonStaleRecord: { _ in abandonCalls += 1 }
        )

        #expect(abandonCalls == 1)
        #expect(store.record(for: id)?.ownerUserId == currentOwner)
    }

    @Test func staleFileRequiresCancelNotAdopt() throws {
        let file = try makeTempAudioFile(named: "policy")
        defer { try? FileManager.default.removeItem(at: file.url) }

        let stale = UploadResumeRecord(
            sermonLocalId: UUID(),
            objectPath: "user/old.m4a",
            uploadURL: URL(string: "https://example.com/old"),
            uploadLength: file.length,
            filePath: file.url.path,
            fileModificationTime: file.mtime - 120,
            taskIdentifier: 1,
            startedUnderFlag: true,
            upsert: true
        )
        #expect(
            !ResumableUploadPathResolver.shouldAdoptActiveBackgroundTask(
                record: stale,
                objectPath: "user/fresh.m4a",
                localFile: file.url,
                fileLength: file.length
            )
        )
    }

    @Test func matchingResumeWithUploadURLMayAdopt() throws {
        let file = try makeTempAudioFile(named: "adopt")
        defer { try? FileManager.default.removeItem(at: file.url) }

        let matching = UploadResumeRecord(
            sermonLocalId: UUID(),
            objectPath: "user/same.m4a",
            uploadURL: URL(string: "https://example.com/u"),
            uploadLength: file.length,
            filePath: file.url.path,
            fileModificationTime: file.mtime,
            taskIdentifier: 2,
            startedUnderFlag: true,
            upsert: true
        )
        #expect(
            ResumableUploadPathResolver.shouldAdoptActiveBackgroundTask(
                record: matching,
                objectPath: "user/same.m4a",
                localFile: file.url,
                fileLength: file.length
            )
        )
    }

    @Test func freshMintMustNotAdoptActiveTask() throws {
        let file = try makeTempAudioFile(named: "fresh")
        defer { try? FileManager.default.removeItem(at: file.url) }

        let pendingCreate = UploadResumeRecord(
            sermonLocalId: UUID(),
            objectPath: "user/new.m4a",
            uploadURL: nil,
            uploadLength: file.length,
            filePath: file.url.path,
            fileModificationTime: file.mtime,
            taskIdentifier: nil,
            startedUnderFlag: true,
            upsert: true
        )
        #expect(
            !ResumableUploadPathResolver.shouldAdoptActiveBackgroundTask(
                record: pendingCreate,
                objectPath: "user/new.m4a",
                localFile: file.url,
                fileLength: file.length
            )
        )
    }
}

/// TAB-73 review round 2: the gateway's resumable branch — resolver plan,
/// uploader hand-off, mint-vs-resume decisions — exercised end to end with a
/// capturing uploader. The uploader throws a sentinel after recording its
/// arguments, stopping `createRemoteSermon` before any network call.
@MainActor
struct GatewayResumableBranchTests {

    final class CapturingUploader: SermonAudioUploading {
        struct Sentinel: Error {}
        var uploadedObjectPaths: [String] = []
        var uploadedUpserts: [Bool] = []
        var abandonedRecords: [UploadResumeRecord] = []
        var acceptsResumableAdmission = true

        func uploadResumable(localFile: URL, sermonLocalId: UUID, objectPath: String, upsert: Bool) async throws {
            uploadedObjectPaths.append(objectPath)
            uploadedUpserts.append(upsert)
            throw Sentinel()
        }

        func cancelInFlightResumableUploads(timeoutNanoseconds: UInt64) async throws {}
        func clearPersistedResumeRecords() async {}
        func abandonStaleResumeRecord(_ record: UploadResumeRecord) async throws {
            abandonedRecords.append(record)
        }
    }

    private struct Harness {
        let gateway: SermonSyncRemoteGateway
        let uploader: CapturingUploader
        let store: UploadResumeStore
        let ownerId: UUID
        let file: URL
        let fileLength: Int64
        let modificationTime: TimeInterval
        let cleanup: () -> Void
    }

    private func makeHarness() throws -> Harness {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("gateway-resumable-\(UUID().uuidString).m4a")
        try Data(repeating: 0xEF, count: 16).write(to: file)
        let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let store = UploadResumeStore(defaults: defaults, key: "gateway-branch")
        let uploader = CapturingUploader()
        let ownerId = UUID()
        let gateway = SermonSyncRemoteGateway(
            supabaseService: MockSupabaseService(),
            audioUploader: uploader,
            resumeStore: store,
            isResumableUploadsEnabled: { true },
            authUserIdProvider: { ownerId }
        )

        return Harness(
            gateway: gateway,
            uploader: uploader,
            store: store,
            ownerId: ownerId,
            file: file,
            fileLength: Int64(values.fileSize!),
            modificationTime: values.contentModificationDate!.timeIntervalSince1970,
            cleanup: {
                try? FileManager.default.removeItem(at: file)
                defaults.removePersistentDomain(forName: suite)
            }
        )
    }

    private func makeSyncData(id: UUID, file: URL) -> SermonSyncData {
        SermonSyncData(
            id: id,
            title: "Gateway Branch Sermon",
            audioFileURL: file,
            date: Date(),
            serviceType: "Sunday Service",
            speaker: nil,
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            isArchived: false,
            userId: UUID(),
            updatedAt: Date(),
            notes: nil,
            transcript: nil,
            summary: nil,
            scopes: .all
        )
    }

    /// A persisted record matching the local file resumes: no mint, and the
    /// record's own objectPath (not a freshly minted one) reaches the uploader.
    @Test func matchingResumeRecordSkipsMintAndReusesPath() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let sermonId = UUID()
        let persistedPath = "custom/persisted-resume-path.m4a"

        harness.store.save(
            UploadResumeRecord(
                sermonLocalId: sermonId,
                objectPath: persistedPath,
                uploadURL: URL(string: "https://example.com/upload/resumable/xyz")!,
                uploadLength: harness.fileLength,
                filePath: harness.file.path,
                fileModificationTime: harness.modificationTime,
                taskIdentifier: nil,
                ownerUserId: harness.ownerId,
                startedUnderFlag: true,
                upsert: true
            )
        )

        await #expect(throws: CapturingUploader.Sentinel.self) {
            _ = try await harness.gateway.createRemoteSermon(
                data: makeSyncData(id: sermonId, file: harness.file)
            )
        }

        #expect(harness.uploader.uploadedObjectPaths == [persistedPath])
        #expect(harness.uploader.abandonedRecords.isEmpty)
    }

    /// A record for a DIFFERENT file (stale partial) is abandoned first, then
    /// a fresh path is minted and handed to the uploader, and the store holds
    /// the minted record.
    @Test func staleRecordIsAbandonedThenFreshPathMinted() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let sermonId = UUID()

        harness.store.save(
            UploadResumeRecord(
                sermonLocalId: sermonId,
                objectPath: "custom/stale-path.m4a",
                uploadURL: URL(string: "https://example.com/upload/resumable/old")!,
                uploadLength: 999, // does not match the real file
                filePath: "/tmp/some-other-file.m4a",
                fileModificationTime: 1,
                taskIdentifier: nil,
                ownerUserId: harness.ownerId,
                startedUnderFlag: true,
                upsert: true
            )
        )

        await #expect(throws: CapturingUploader.Sentinel.self) {
            _ = try await harness.gateway.createRemoteSermon(
                data: makeSyncData(id: sermonId, file: harness.file)
            )
        }

        let mintedPath = "mock-user/\(sermonId.uuidString.lowercased()).m4a"
        #expect(harness.uploader.abandonedRecords.map(\.objectPath) == ["custom/stale-path.m4a"])
        #expect(harness.uploader.uploadedObjectPaths == [mintedPath])
        #expect(harness.store.record(for: sermonId)?.objectPath == mintedPath)
    }
}
