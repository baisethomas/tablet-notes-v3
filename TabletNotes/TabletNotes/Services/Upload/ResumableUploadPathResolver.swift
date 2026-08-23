import Foundation

/// Decides whether a resumable upload reuses a persisted path or mints a new one.
/// Extracted so "resume skips mint" is unit-testable without hitting create-sermon.
@MainActor
enum ResumableUploadPathResolver {
    struct Plan: Equatable {
        var objectPath: String
        var upsert: Bool
        var didMint: Bool
    }

    /// Coalesces concurrent `plan` calls for the same sermon across reentrant awaits.
    private static var inFlightPlans: [PlanCoalescingKey: Task<Plan, Error>] = [:]

    private struct PlanCoalescingKey: Hashable {
        let sermonLocalId: UUID
        let ownerUserId: UUID?
        let filePath: String
        let fileLength: Int64
        let fileModificationTime: TimeInterval?
    }

    private static func coalescingKey(
        sermonLocalId: UUID,
        localFile: URL,
        fileLength: Int64,
        ownerUserId: UUID?
    ) throws -> PlanCoalescingKey {
        let mtime = try localFile.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate?.timeIntervalSince1970
        return PlanCoalescingKey(
            sermonLocalId: sermonLocalId,
            ownerUserId: ownerUserId,
            filePath: localFile.path,
            fileLength: fileLength,
            fileModificationTime: mtime
        )
    }

    /// When true, an in-flight background PATCH for this sermon may be adopted.
    /// When false, any live task must be cancelled and drained before uploading.
    nonisolated static func shouldAdoptActiveBackgroundTask(
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
        ownerUserId: UUID?,
        resumeStore: UploadResumeStoring,
        mint: @escaping () async throws -> (path: String, upsert: Bool),
        mayPersistNewRecord: @escaping () -> Bool = { true },
        abandonStaleRecord: ((UploadResumeRecord) async throws -> Void)? = nil
    ) async throws -> Plan {
        let key = try coalescingKey(
            sermonLocalId: sermonLocalId,
            localFile: localFile,
            fileLength: fileLength,
            ownerUserId: ownerUserId
        )
        if let existing = inFlightPlans[key] {
            return try await existing.value
        }
        let mintWork = mint
        let mayPersist = mayPersistNewRecord
        let abandon = abandonStaleRecord
        let task = Task { @MainActor in
            defer { inFlightPlans[key] = nil }
            return try await planUncoalesced(
                sermonLocalId: sermonLocalId,
                localFile: localFile,
                fileLength: fileLength,
                ownerUserId: ownerUserId,
                resumeStore: resumeStore,
                mint: mintWork,
                mayPersistNewRecord: mayPersist,
                abandonStaleRecord: abandon
            )
        }
        inFlightPlans[key] = task
        return try await task.value
    }

    private static func planUncoalesced(
        sermonLocalId: UUID,
        localFile: URL,
        fileLength: Int64,
        ownerUserId: UUID?,
        resumeStore: UploadResumeStoring,
        mint: () async throws -> (path: String, upsert: Bool),
        mayPersistNewRecord: () -> Bool,
        abandonStaleRecord: ((UploadResumeRecord) async throws -> Void)?
    ) async throws -> Plan {
        if let record = resumeStore.record(for: sermonLocalId),
           record.ownerUserId == ownerUserId,
           record.matchesLocalFile(localFile, length: fileLength) {
            return Plan(objectPath: record.objectPath, upsert: record.upsert, didMint: false)
        }
        if let stale = resumeStore.record(for: sermonLocalId) {
            // Always drain via UploadManager (same-owner remint or foreign-owner
            // leftovers) before dropping the only sermon→task mapping.
            try await abandonStaleRecord?(stale)
            resumeStore.remove(sermonLocalId: sermonLocalId)
        }
        let minted = try await mint()
        if mayPersistNewRecord() {
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
                    ownerUserId: ownerUserId,
                    startedUnderFlag: true,
                    upsert: minted.upsert
                )
            )
        }
        return Plan(objectPath: minted.path, upsert: minted.upsert, didMint: true)
    }
}
