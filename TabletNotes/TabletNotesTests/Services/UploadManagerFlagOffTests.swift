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

        let ownerId = UUID()
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
                ownerUserId: ownerId,
                startedUnderFlag: true,
                upsert: true
            )
        )

        var order: [String] = []
        let manager = UploadManager(
            resumeStore: store,
            featureFlags: flags,
            tokenProvider: { "token" },
            currentUserIdProvider: { ownerId },
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

    @Test func onlyAwaitsTransferableBackgroundTaskStates() {
        #expect(UploadManager.shouldAwaitBackgroundUploadTask(state: .running))
        #expect(UploadManager.shouldAwaitBackgroundUploadTask(state: .suspended))
        #expect(UploadManager.shouldAwaitBackgroundUploadTask(state: .canceling))
        #expect(!UploadManager.shouldAwaitBackgroundUploadTask(state: .completed))
    }

    @Test func launchRecoverySchedulesPersistedUploadWithoutActiveTask() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("launch-recovery-\(UUID().uuidString).m4a")
        try Data(repeating: 0xEF, count: 32).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let length = Int64(values.fileSize!)
        let mtime = values.contentModificationDate!.timeIntervalSince1970

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "launch-recovery")
        let flags = FeatureFlags(defaults: defaults)
        flags.setEnabled(true, for: .resumableUploads)

        let ownerId = UUID()
        let sermonId = UUID()
        store.save(
            UploadResumeRecord(
                sermonLocalId: sermonId,
                objectPath: "user/\(sermonId.uuidString.lowercased()).m4a",
                uploadURL: URL(string: "https://example.com/upload/resumable/abc")!,
                uploadLength: length,
                filePath: file.path,
                fileModificationTime: mtime,
                taskIdentifier: nil,
                ownerUserId: ownerId,
                startedUnderFlag: true,
                upsert: true
            )
        )

        var scheduled = false
        let manager = UploadManager(
            resumeStore: store,
            featureFlags: flags,
            tokenProvider: { "token" },
            currentUserIdProvider: { ownerId },
            createBackgroundSession: true
        )
        manager.headOffsetOverride = { _, _, _ in 0 }
        manager.onPatchTaskScheduled = { scheduled = true }

        await manager.continueIncompleteBackgroundUploads()

        #expect(scheduled)
    }

    @Test func relaunchFinishPatchRemovesPersistedChunkFile() async throws {
        let chunk = FileManager.default.temporaryDirectory
            .appendingPathComponent("tus-chunk-\(UUID().uuidString)")
        try Data(repeating: 0x11, count: 16).write(to: chunk)

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "chunk-cleanup")
        let flags = FeatureFlags(defaults: defaults)
        flags.setEnabled(true, for: .resumableUploads)

        let sermonId = UUID()
        store.save(
            UploadResumeRecord(
                sermonLocalId: sermonId,
                objectPath: "user/test.m4a",
                uploadURL: URL(string: "https://example.com/upload/resumable/abc")!,
                uploadLength: 16,
                filePath: "/tmp/test.m4a",
                fileModificationTime: 1,
                taskIdentifier: 77,
                chunkFilePath: chunk.path,
                startedUnderFlag: true,
                upsert: true
            )
        )

        let manager = UploadManager(
            resumeStore: store,
            featureFlags: flags,
            tokenProvider: { "token" },
            createBackgroundSession: false
        )
        manager.finishPatchForTesting(taskId: 77)

        #expect(!FileManager.default.fileExists(atPath: chunk.path))
        #expect(store.record(for: sermonId)?.chunkFilePath == nil)
        #expect(store.record(for: sermonId)?.taskIdentifier == nil)
    }

    @Test func clearPersistedResumeRecordsEmptiesStore() async {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "sign-out-clear")
        store.save(
            UploadResumeRecord(
                sermonLocalId: UUID(),
                objectPath: "user/a.m4a",
                uploadURL: URL(string: "https://example.com/a")!,
                uploadLength: 1,
                filePath: "/tmp/a.m4a",
                fileModificationTime: 1,
                taskIdentifier: 1,
                startedUnderFlag: true,
                upsert: true
            )
        )
        let manager = UploadManager(
            resumeStore: store,
            createBackgroundSession: false
        )
        await manager.clearPersistedResumeRecords()
        #expect(store.allRecords().isEmpty)
    }

    @Test func signOutRetainsResumeRecordsWhenDrainIncomplete() async {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "sign-out-retain")
        let sermonId = UUID()
        store.save(
            UploadResumeRecord(
                sermonLocalId: sermonId,
                objectPath: "user/a.m4a",
                uploadURL: URL(string: "https://example.com/a")!,
                uploadLength: 1,
                filePath: "/tmp/a.m4a",
                fileModificationTime: 1,
                taskIdentifier: 99,
                startedUnderFlag: true,
                upsert: true
            )
        )
        let manager = UploadManager(
            resumeStore: store,
            createBackgroundSession: false
        )
        manager.signOutDrainSucceededOverride = false
        await manager.clearPersistedResumeRecords()
        #expect(store.record(for: sermonId) != nil)
    }

    @Test func crossAccountPurgeRemovesForeignRecordsAfterDrain() async {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "cross-account-purge")
        let flags = FeatureFlags(defaults: defaults)
        flags.setEnabled(true, for: .resumableUploads)

        let foreignOwner = UUID()
        let currentOwner = UUID()
        let sermonId = UUID()
        store.save(
            UploadResumeRecord(
                sermonLocalId: sermonId,
                objectPath: "user/foreign.m4a",
                uploadURL: URL(string: "https://example.com/foreign")!,
                uploadLength: 8,
                filePath: "/tmp/foreign.m4a",
                fileModificationTime: 1,
                taskIdentifier: 3,
                ownerUserId: foreignOwner,
                startedUnderFlag: true,
                upsert: true
            )
        )

        let manager = UploadManager(
            resumeStore: store,
            featureFlags: flags,
            tokenProvider: { "token" },
            currentUserIdProvider: { currentOwner },
            createBackgroundSession: false
        )
        await manager.continueIncompleteBackgroundUploads()
        #expect(store.record(for: sermonId) == nil)
    }

    @Test func successfulFlagOffKeepsAdmissionClosedUntilReopen() async throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "flag-off-admission")
        let flags = FeatureFlags(defaults: defaults)
        flags.setEnabled(true, for: .resumableUploads)

        let ownerId = UUID()
        let manager = UploadManager(
            resumeStore: store,
            featureFlags: flags,
            tokenProvider: { "token" },
            currentUserIdProvider: { ownerId },
            createBackgroundSession: false
        )
        #expect(manager.acceptsResumableAdmission)

        try await manager.cancelInFlightResumableUploads()
        // Settings has not committed the flag off yet — admission must stay closed.
        #expect(flags.resumableUploads)
        #expect(!manager.acceptsResumableAdmission)

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("post-drain-\(UUID().uuidString).m4a")
        try Data(repeating: 0xAB, count: 8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        do {
            try await manager.uploadResumable(
                localFile: file,
                sermonLocalId: UUID(),
                objectPath: "user/post-drain.m4a",
                upsert: true
            )
            Issue.record("expected resumableCancelled after drain")
        } catch let error as UploadManagerError {
            #expect(error == .resumableCancelled)
        }

        flags.setEnabled(false, for: .resumableUploads)
        manager.reopenResumableAdmission()
        #expect(!manager.acceptsResumableAdmission)

        flags.setEnabled(true, for: .resumableUploads)
        manager.reopenResumableAdmission()
        #expect(manager.acceptsResumableAdmission)
    }
}
