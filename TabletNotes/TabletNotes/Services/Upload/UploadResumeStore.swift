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
    var taskIdentifier: Int?
    var startedUnderFlag: Bool
    var upsert: Bool
}

protocol UploadResumeStoring: AnyObject {
    func record(for sermonLocalId: UUID) -> UploadResumeRecord?
    func save(_ record: UploadResumeRecord)
    func remove(sermonLocalId: UUID)
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

    func save(_ record: UploadResumeRecord) {
        var records = allRecords().filter { $0.sermonLocalId != record.sermonLocalId }
        records.append(record)
        write(records)
    }

    func remove(sermonLocalId: UUID) {
        write(allRecords().filter { $0.sermonLocalId != sermonLocalId })
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
