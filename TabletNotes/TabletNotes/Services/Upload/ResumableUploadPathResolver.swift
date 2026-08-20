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
        resumeStore: UploadResumeStoring,
        mint: () async throws -> (path: String, upsert: Bool)
    ) async throws -> Plan {
        if let record = resumeStore.record(for: sermonLocalId) {
            return Plan(objectPath: record.objectPath, upsert: record.upsert, didMint: false)
        }
        let minted = try await mint()
        return Plan(objectPath: minted.path, upsert: minted.upsert, didMint: true)
    }
}
