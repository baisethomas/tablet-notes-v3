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

        var mintCalls = 0
        let plan = try await ResumableUploadPathResolver.plan(
            sermonLocalId: UUID(),
            localFile: file.url,
            fileLength: file.length,
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

    @Test func resumeSkipsMintWhenARecordMatchesTheLocalFile() async throws {
        let file = try makeTempAudioFile(named: "resume")
        defer { try? FileManager.default.removeItem(at: file.url) }

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "resolver")
        let id = UUID()
        store.save(
            UploadResumeRecord(
                sermonLocalId: id,
                objectPath: "user/persisted.m4a",
                uploadURL: URL(string: "https://example.com/u"),
                uploadLength: file.length,
                filePath: file.url.path,
                fileModificationTime: file.mtime,
                taskIdentifier: 1,
                startedUnderFlag: true,
                upsert: true
            )
        )

        var mintCalls = 0
        let plan = try await ResumableUploadPathResolver.plan(
            sermonLocalId: id,
            localFile: file.url,
            fileLength: file.length,
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
        store.save(
            UploadResumeRecord(
                sermonLocalId: id,
                objectPath: "user/old.m4a",
                uploadURL: URL(string: "https://example.com/old"),
                uploadLength: file.length,
                filePath: file.url.path,
                fileModificationTime: file.mtime - 60,
                taskIdentifier: 1,
                startedUnderFlag: true,
                upsert: true
            )
        )

        var mintCalls = 0
        let plan = try await ResumableUploadPathResolver.plan(
            sermonLocalId: id,
            localFile: file.url,
            fileLength: file.length,
            resumeStore: store,
            mint: {
                mintCalls += 1
                return ("user/fresh.m4a", true)
            }
        )

        #expect(plan.didMint)
        #expect(plan.objectPath == "user/fresh.m4a")
        #expect(mintCalls == 1)
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

        _ = try await ResumableUploadPathResolver.plan(
            sermonLocalId: id,
            localFile: file.url,
            fileLength: file.length,
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

        let plan = try await ResumableUploadPathResolver.plan(
            sermonLocalId: id,
            localFile: file.url,
            fileLength: file.length,
            resumeStore: store,
            mint: { ("user/race.m4a", true) },
            mayPersistNewRecord: { false }
        )

        #expect(plan.didMint)
        #expect(plan.objectPath == "user/race.m4a")
        #expect(store.record(for: id) == nil)
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
