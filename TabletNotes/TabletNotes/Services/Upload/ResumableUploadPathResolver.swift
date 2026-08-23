import Foundation

/// Decides whether a resumable upload reuses a persisted path or mints a new one.
/// Extracted so "resume skips mint" is unit-testable without hitting create-sermon.
enum ResumableUploadPathResolver {
    struct Plan: Equatable {
        var objectPath: String
        var upsert: Bool
        var didMint: Bool
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
        return Plan(objectPath: minted.path, upsert: minted.upsert, didMint: true)
    }
}
