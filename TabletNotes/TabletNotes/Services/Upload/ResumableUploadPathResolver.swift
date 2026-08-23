import Foundation

/// Decides whether a resumable upload reuses a persisted path or mints a new one.
/// Extracted so "resume skips mint" is unit-testable without hitting create-sermon.
enum ResumableUploadPathResolver {
    struct Plan: Equatable {
        var objectPath: String
        var upsert: Bool
        var didMint: Bool
    }

    /// When true, an in-flight background PATCH for this sermon may be adopted.
    /// When false, any live task must be cancelled and drained before uploading.
    static func shouldAdoptActiveBackgroundTask(
        record: UploadResumeRecord?,
        objectPath: String,
        localFile: URL,
        fileLength: Int64
    ) -> Bool {
        guard let record,
              record.objectPath == objectPath,
              record.uploadURL != nil else {
            return false
        }
        return record.matchesLocalFile(localFile, length: fileLength)
    }

    static func plan(
        sermonLocalId: UUID,
        localFile: URL,
        fileLength: Int64,
        resumeStore: UploadResumeStoring,
        mint: () async throws -> (path: String, upsert: Bool)
    ) async throws -> Plan {
        if let record = resumeStore.record(for: sermonLocalId),
           record.matchesLocalFile(localFile, length: fileLength) {
            return Plan(objectPath: record.objectPath, upsert: record.upsert, didMint: false)
        }
        // Stale record (different file bytes) must not reuse objectPath — mint fresh.
        if resumeStore.record(for: sermonLocalId) != nil {
            resumeStore.remove(sermonLocalId: sermonLocalId)
        }
        let minted = try await mint()
        let mtime = try? localFile.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate?.timeIntervalSince1970
        resumeStore.save(
            UploadResumeRecord(
                sermonLocalId: sermonLocalId,
                objectPath: minted.path,
                uploadURL: nil,
                uploadLength: fileLength,
                filePath: localFile.path,
                fileModificationTime: mtime,
                taskIdentifier: nil,
                startedUnderFlag: true,
                upsert: minted.upsert
            )
        )
        return Plan(objectPath: minted.path, upsert: minted.upsert, didMint: true)
    }
}
