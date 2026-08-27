import Foundation

/// Persisted in-flight TUS upload for one sermon (TAB-73 Part B).
///
/// Path authority on resume: if this record exists, sync skips `generate-upload-url`
/// and continues from `objectPath` / `uploadURL` so a mint 429 cannot strand a
/// nearly-finished transfer.
struct UploadResumeRecord: Codable, Equatable, Sendable {
    var sermonLocalId: UUID
    var objectPath: String
    var uploadURL: URL?
    var uploadLength: Int64
    var filePath: String
    /// `contentModificationDate` at the moment upload began. Optional so older
    /// persisted blobs still decode; a missing value never matches (forces restart).
    var fileModificationTime: TimeInterval? = nil
    var taskIdentifier: Int?
    /// Temp PATCH source file — survives relaunch so completed tasks can delete it.
    var chunkFilePath: String? = nil
    /// Authenticated user who started this upload — prevents cross-account resume.
    var ownerUserId: UUID? = nil
    var startedUnderFlag: Bool
    var upsert: Bool

    /// True only when the on-disk recording is the same bytes we started uploading.
    func matchesLocalFile(_ localFile: URL, length: Int64) -> Bool {
        guard filePath == localFile.path,
              uploadLength == length,
              let stored = fileModificationTime else {
            return false
        }
        guard let values = try? localFile.resourceValues(forKeys: [.contentModificationDateKey]),
              let date = values.contentModificationDate else {
            return false
        }
        return date.timeIntervalSince1970 == stored
    }
}

protocol UploadResumeStoring: AnyObject {
    func record(for sermonLocalId: UUID) -> UploadResumeRecord?
    func record(forTaskIdentifier taskIdentifier: Int) -> UploadResumeRecord?
    func save(_ record: UploadResumeRecord)
    func remove(sermonLocalId: UUID)
    func removeAll(notOwnedBy ownerUserId: UUID)
    func allRecords() -> [UploadResumeRecord]
    func removeAll()
}

/// JSON blob in UserDefaults — small, testable with an injected suite.
final class UploadResumeStore: UploadResumeStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "upload.resumeRecords.v1") {
        self.defaults = defaults
        self.key = key
    }

    func record(for sermonLocalId: UUID) -> UploadResumeRecord? {
        allRecords().first { $0.sermonLocalId == sermonLocalId }
    }

    func record(forTaskIdentifier taskIdentifier: Int) -> UploadResumeRecord? {
        allRecords().first { $0.taskIdentifier == taskIdentifier }
    }

    func save(_ record: UploadResumeRecord) {
        var records = allRecords().filter { $0.sermonLocalId != record.sermonLocalId }
        records.append(record)
        write(records)
    }

    func remove(sermonLocalId: UUID) {
        write(allRecords().filter { $0.sermonLocalId != sermonLocalId })
    }

    func removeAll(notOwnedBy ownerUserId: UUID) {
        write(allRecords().filter { $0.ownerUserId == ownerUserId })
    }

    func allRecords() -> [UploadResumeRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([UploadResumeRecord].self, from: data)) ?? []
    }

    func removeAll() {
        defaults.removeObject(forKey: key)
    }

    private func write(_ records: [UploadResumeRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}
