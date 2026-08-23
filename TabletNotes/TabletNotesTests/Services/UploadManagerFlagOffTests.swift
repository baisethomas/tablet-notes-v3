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
}
