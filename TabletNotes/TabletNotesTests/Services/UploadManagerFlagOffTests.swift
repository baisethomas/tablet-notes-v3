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
}
