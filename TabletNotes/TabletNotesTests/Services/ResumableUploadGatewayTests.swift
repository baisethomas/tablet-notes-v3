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
        #expect(store.record(for: id) == nil)
    }
}
