import Foundation
import Testing
@testable import TabletNotes

struct ResumableUploadPathResolverTests {
    @Test func firstAttemptMintsAPath() async throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "resolver")

        var mintCalls = 0
        let plan = try await ResumableUploadPathResolver.plan(
            sermonLocalId: UUID(),
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

    @Test func resumeSkipsMintWhenARecordExists() async throws {
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
                uploadLength: 10,
                filePath: "/tmp/a.m4a",
                taskIdentifier: 1,
                startedUnderFlag: true,
                upsert: true
            )
        )

        var mintCalls = 0
        let plan = try await ResumableUploadPathResolver.plan(
            sermonLocalId: id,
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
}
