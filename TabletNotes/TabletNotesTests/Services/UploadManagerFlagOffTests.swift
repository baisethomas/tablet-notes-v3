import Foundation
import Testing
@testable import TabletNotes

@MainActor
struct UploadManagerFlagOffTests {
    @Test func flagOffTargetsInFlightAndFlaggedSermons() {
        let id1 = UUID()
        let id2 = UUID()
        let flagged = [
            UploadResumeRecord(
                sermonLocalId: id1,
                objectPath: "user/a.m4a",
                uploadURL: URL(string: "https://example.com/a")!,
                uploadLength: 10,
                filePath: "/tmp/a.m4a",
                fileModificationTime: 1,
                taskIdentifier: 1,
                startedUnderFlag: true,
                upsert: true
            ),
            UploadResumeRecord(
                sermonLocalId: id2,
                objectPath: "user/b.m4a",
                uploadURL: nil,
                uploadLength: 20,
                filePath: "/tmp/b.m4a",
                fileModificationTime: 2,
                taskIdentifier: nil,
                startedUnderFlag: true,
                upsert: false
            )
        ]
        let affected = UploadManager.sermonIdsAffectedByFlagOff(
            flaggedRecords: flagged,
            inFlightSermonIds: [id2]
        )
        #expect(affected == Set([id1, id2]))
    }

    @Test func coalescingKeyDiffersWhenFileIdentityChanges() throws {
        let sermonId = UUID()
        let fileA = FileManager.default.temporaryDirectory.appendingPathComponent("a-\(UUID().uuidString).m4a")
        let fileB = FileManager.default.temporaryDirectory.appendingPathComponent("b-\(UUID().uuidString).m4a")
        try Data([1, 2, 3]).write(to: fileA)
        try Data([1, 2, 3, 4]).write(to: fileB)
        defer {
            try? FileManager.default.removeItem(at: fileA)
            try? FileManager.default.removeItem(at: fileB)
        }
        let valuesA = try fileA.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let valuesB = try fileB.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])

        let keyA = InFlightUploadKey(
            sermonLocalId: sermonId,
            objectPath: "user/a.m4a",
            localFile: fileA,
            fileLength: Int64(valuesA.fileSize!),
            fileModificationTime: valuesA.contentModificationDate!.timeIntervalSince1970
        )
        let keyB = InFlightUploadKey(
            sermonLocalId: sermonId,
            objectPath: "user/b.m4a",
            localFile: fileB,
            fileLength: Int64(valuesB.fileSize!),
            fileModificationTime: valuesB.contentModificationDate!.timeIntervalSince1970
        )
        #expect(keyA != keyB)
    }

    @Test func backgroundContinuationClearsRecordsWhenFlagOff() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("flag-off-continue-\(UUID().uuidString).m4a")
        try Data(repeating: 0xCD, count: 8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let length = Int64(values.fileSize!)
        let mtime = values.contentModificationDate!.timeIntervalSince1970

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "flag-off-continue")
        let flags = FeatureFlags(defaults: defaults)
        #expect(flags.resumableUploads == false)

        let sermonId = UUID()
        store.save(
            UploadResumeRecord(
                sermonLocalId: sermonId,
                objectPath: "user/\(sermonId.uuidString.lowercased()).m4a",
                uploadURL: URL(string: "https://example.com/upload/resumable/abc")!,
                uploadLength: length,
                filePath: file.path,
                fileModificationTime: mtime,
                taskIdentifier: 42,
                startedUnderFlag: true,
                upsert: true
            )
        )

        var tokenCalls = 0
        let manager = UploadManager(
            resumeStore: store,
            featureFlags: flags,
            tokenProvider: {
                tokenCalls += 1
                return "token"
            },
            createBackgroundSession: false
        )

        await manager.continueIncompleteBackgroundUploads()

        #expect(tokenCalls == 0)
        #expect(store.allRecords().isEmpty)
    }

    @Test func backgroundSessionHandlerRunsAfterNextChunkScheduled() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("relaunch-schedule-\(UUID().uuidString).m4a")
        try Data(repeating: 0xAB, count: 64).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let length = Int64(values.fileSize!)
        let mtime = values.contentModificationDate!.timeIntervalSince1970

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "relaunch-schedule")
        let flags = FeatureFlags(defaults: defaults)
        flags.setEnabled(true, for: .resumableUploads)

        let sermonId = UUID()
        store.save(
            UploadResumeRecord(
                sermonLocalId: sermonId,
                objectPath: "user/\(sermonId.uuidString.lowercased()).m4a",
                uploadURL: URL(string: "https://example.com/upload/resumable/abc")!,
                uploadLength: length,
                filePath: file.path,
                fileModificationTime: mtime,
                taskIdentifier: 42,
                startedUnderFlag: true,
                upsert: true
            )
        )

        var order: [String] = []
        let manager = UploadManager(
            resumeStore: store,
            featureFlags: flags,
            tokenProvider: { "token" },
            createBackgroundSession: true
        )
        manager.headOffsetOverride = { _, _, _ in 0 }
        manager.onPatchTaskScheduled = { order.append("scheduled") }
        manager.handleBackgroundSessionEvents(identifier: UploadManager.sessionIdentifier) {
            order.append("handler")
        }

        await manager.finishBackgroundSessionEventsForTesting()

        #expect(order == ["scheduled", "handler"])
    }
}
