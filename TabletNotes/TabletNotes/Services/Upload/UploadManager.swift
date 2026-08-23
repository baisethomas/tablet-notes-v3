import Foundation

enum UploadManagerError: LocalizedError, Equatable {
    case fileMissing
    case createFailed(status: Int)
    case patchFailed(status: Int)
    /// HEAD said the TUS resource is gone / invalid — record cleared; restart create.
    case headRestart(status: Int)
    /// Transient HEAD failure — keep the resume record and surface the error.
    case headFailed(status: Int)
    case incomplete(offset: Int64, length: Int64)
    case invalidOffset(offset: Int64, length: Int64)
    case duplicatePatchWait
    case resumableCancelled
    case timedOut
    case flagOffCancelTimedOut
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            return "The recording file is missing."
        case .createFailed(let status):
            return "Could not start resumable upload (\(status))."
        case .patchFailed(let status):
            return "Resumable upload chunk failed (\(status))."
        case .headRestart(let status):
            return "Upload session expired (\(status)); restarting."
        case .headFailed(let status):
            return "Could not resume upload (\(status))."
        case .incomplete(let offset, let length):
            return "Upload incomplete (\(offset)/\(length) bytes)."
        case .invalidOffset(let offset, let length):
            return "Server returned an invalid upload offset (\(offset)/\(length))."
        case .duplicatePatchWait:
            return "An upload chunk is already waiting for completion."
        case .resumableCancelled:
            return "Resumable upload was cancelled."
        case .timedOut:
            return "Upload timed out waiting for the system transfer."
        case .flagOffCancelTimedOut:
            return "Could not cancel in-flight uploads before switching modes."
        case .notConfigured:
            return "Upload manager is not configured."
        }
    }
}

/// Coalescing identity — must include file bytes and path, not sermon ID alone.
struct InFlightUploadKey: Hashable, Sendable {
    let sermonLocalId: UUID
    let objectPath: String
    let filePath: String
    let fileLength: Int64
    let fileModificationTime: TimeInterval

    init(sermonLocalId: UUID, objectPath: String, localFile: URL, fileLength: Int64, fileModificationTime: TimeInterval) {
        self.sermonLocalId = sermonLocalId
        self.objectPath = objectPath
        self.filePath = localFile.path
        self.fileLength = fileLength
        self.fileModificationTime = fileModificationTime
    }
}

/// Performs a resumable TUS upload for one sermon audio file.
@MainActor
protocol SermonAudioUploading: AnyObject {
    func uploadResumable(
        localFile: URL,
        sermonLocalId: UUID,
        objectPath: String,
        upsert: Bool
    ) async throws

    /// Cancel background tasks started under the resumable flag and wait until
    /// `getAllTasks()` reports none left for those paths (bounded).
    func cancelInFlightResumableUploads(timeoutNanoseconds: UInt64) async throws

    /// False while flag-off drain runs — path mint must not persist resume records.
    var acceptsResumableAdmission: Bool { get }

    /// Drop all persisted TUS resume state (sign-out / account switch).
    func clearPersistedResumeRecords() async

    /// Cancel client work and delete a stale partial object before reminting.
    func abandonStaleResumeRecord(_ record: UploadResumeRecord) async throws
}

/// Process-wide owner of the background TUS session (TAB-73 Part B).
///
/// Must be constructed once at app launch — never from `MainAppView` /
/// `SyncService` init (those re-run and would collide on the session identifier).
@MainActor
final class UploadManager: NSObject, SermonAudioUploading {
    static let shared = UploadManager()
    static let sessionIdentifier = "com.tabletnotes.upload"

    /// How long sync will wait on a single background chunk before throwing
    /// (upload stays adopted via the resume record for the next sync).
    static let chunkWaitTimeoutNanoseconds: UInt64 = 15 * 60 * 1_000_000_000
    static let flagOffCancelTimeoutNanoseconds: UInt64 = 30 * 1_000_000_000

    private let projectURL: URL
    private let anonKey: String
    private let resumeStore: UploadResumeStoring
    private let featureFlags: FeatureFlags
    private let tokenProvider: () async throws -> String
    private let currentUserIdProvider: () -> UUID?
    private let storageObjectDeleter: (String) async throws -> Void
    private let ephemeralSession: URLSession

    private var backgroundSession: URLSession!
    private var backgroundCompletionHandler: (() -> Void)?
    private let patchGate = PatchCompletionGate()
    /// Temp chunk files keyed by URLSession task id — deleted only after the
    /// task completes (or is cancelled), never while the system may still read.
    private var chunkFilesByTaskId: [Int: URL] = [:]
    /// Coalesce concurrent sync attempts for the same sermon into one upload op.
    private var inFlightUploads: [InFlightUploadKey: Task<Void, Error>] = [:]
    /// Prevent duplicate background continuation schedules for the same sermon.
    private var backgroundContinuationsInFlight: Set<UUID> = []
    /// Incremented when resumable uploads are disabled; in-flight ops observe this.
    private var flagOffEpoch: UInt64 = 0
    /// While flag-off drain runs, reject newly admitted resumable uploads.
    private var resumableAdmissionClosed = false
    private var prepared = false

    /// Only await delegate completion for tasks the system may still deliver.
    static func shouldAwaitBackgroundUploadTask(state: URLSessionTask.State) -> Bool {
        switch state {
        case .running, .suspended, .canceling:
            return true
        default:
            return false
        }
    }

    var acceptsResumableAdmission: Bool {
        featureFlags.resumableUploads && !resumableAdmissionClosed
    }

    func clearPersistedResumeRecords() async {
        let drained = await cancelAllResumableBackgroundWorkForSignOut()
        guard drained else {
            // Keep sermon/task mappings so a later launch or background-session
            // event can finish cancelling still-running prior-account uploads.
            print("[UploadManager] Sign-out drain incomplete — retaining resume records for recovery")
            return
        }
        resumeStore.removeAll()
    }

    /// Cancels in-flight resumable work. Returns `true` only when every matching
    /// background task and in-flight op is confirmed gone.
    @discardableResult
    private func cancelAllResumableBackgroundWorkForSignOut() async -> Bool {
        if let signOutDrainSucceededOverride {
            return signOutDrainSucceededOverride
        }
        prepareBackgroundSessionIfNeeded()
        let records = resumeStore.allRecords()
        let sermonIds = Set(records.map(\.sermonLocalId))
        flagOffEpoch &+= 1

        for record in records {
            if let taskId = record.taskIdentifier {
                patchGate.cancelWait(taskId: taskId)
            }
        }
        for taskId in chunkFilesByTaskId.keys {
            patchGate.cancelWait(taskId: taskId)
        }

        let uploadTasks = await backgroundSession.tasks.1
        for task in uploadTasks {
            guard let desc = task.taskDescription,
                  let id = UUID(uuidString: desc),
                  sermonIds.contains(id) else { continue }
            patchGate.cancelWait(taskId: task.taskIdentifier)
            switch task.state {
            case .running, .suspended:
                task.cancel()
            default:
                break
            }
        }

        for operation in inFlightUploads.values {
            operation.cancel()
        }

        if sermonIds.isEmpty {
            return true
        }

        let deadline = ContinuousClock.now + .nanoseconds(Int64(Self.flagOffCancelTimeoutNanoseconds))
        while ContinuousClock.now < deadline {
            let remaining = await backgroundSession.tasks.1.filter { task in
                guard let desc = task.taskDescription,
                      let id = UUID(uuidString: desc),
                      sermonIds.contains(id) else { return false }
                switch task.state {
                case .running, .suspended, .canceling:
                    return true
                default:
                    return false
                }
            }
            if remaining.isEmpty && !inFlightSermonIds().contains(where: sermonIds.contains) {
                return true
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }

    func abandonStaleResumeRecord(_ record: UploadResumeRecord) async throws {
        try await cancelAndDrainUploadTasks(for: record.sermonLocalId)
        await abandonPartialStorageObject(at: record.objectPath)
        resumeStore.remove(sermonLocalId: record.sermonLocalId)
    }

    /// Which sermon IDs flag-off must tear down (flagged records ∪ active ops).
    static func sermonIdsAffectedByFlagOff(
        flaggedRecords: [UploadResumeRecord],
        inFlightSermonIds: some Sequence<UUID>
    ) -> Set<UUID> {
        Set(flaggedRecords.map(\.sermonLocalId)).union(inFlightSermonIds)
    }

    private func inFlightSermonIds() -> Set<UUID> {
        Set(inFlightUploads.keys.map(\.sermonLocalId))
    }

    private func throwIfResumableCancelled(epoch: UInt64) throws {
        if epoch != flagOffEpoch {
            throw UploadManagerError.resumableCancelled
        }
        guard featureFlags.resumableUploads, !resumableAdmissionClosed else {
            throw UploadManagerError.resumableCancelled
        }
        try Task.checkCancellation()
    }

    /// Test seam — override HEAD offset lookup without network I/O.
    internal var headOffsetOverride: ((URL, Int64, UUID) async throws -> Int64)?
    /// Test seam — fired once `task.resume()` runs for a scheduled relaunch chunk.
    internal var onPatchTaskScheduled: (() -> Void)?
    /// Test seam — force sign-out drain success/failure without waiting on URLSession.
    internal var signOutDrainSucceededOverride: Bool?

    /// Test seam — inject store / token / URLs without touching the real session.
    init(
        projectURL: URL = URL(string: SupabaseConfig.projectURL)!,
        anonKey: String = SupabaseConfig.anonKey,
        resumeStore: UploadResumeStoring = UploadResumeStore(),
        featureFlags: FeatureFlags = .shared,
        tokenProvider: (() async throws -> String)? = nil,
        currentUserIdProvider: (() -> UUID?)? = nil,
        storageObjectDeleter: ((String) async throws -> Void)? = nil,
        createBackgroundSession: Bool = true
    ) {
        self.projectURL = projectURL
        self.anonKey = anonKey
        self.resumeStore = resumeStore
        self.featureFlags = featureFlags
        self.tokenProvider = tokenProvider ?? {
            let session = try await SupabaseService.shared.client.auth.session
            return session.accessToken
        }
        self.currentUserIdProvider = currentUserIdProvider ?? {
            AuthenticationManager.shared.currentUser?.id
        }
        self.storageObjectDeleter = storageObjectDeleter ?? { objectPath in
            _ = try await SupabaseService.shared.client.storage
                .from(TusUploadClient.bucketName)
                .remove(paths: [objectPath])
        }
        self.ephemeralSession = URLSession(configuration: .ephemeral)
        super.init()
        if createBackgroundSession {
            prepareBackgroundSessionIfNeeded()
        }
    }

    func prepareBackgroundSessionIfNeeded() {
        guard !prepared else { return }
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 60 * 60 * 6
        backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        prepared = true
    }

    func handleBackgroundSessionEvents(identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == Self.sessionIdentifier else {
            completionHandler()
            return
        }
        prepareBackgroundSessionIfNeeded()
        backgroundCompletionHandler = completionHandler
    }

    func uploadResumable(
        localFile: URL,
        sermonLocalId: UUID,
        objectPath: String,
        upsert: Bool
    ) async throws {
        guard featureFlags.resumableUploads, !resumableAdmissionClosed else {
            throw UploadManagerError.resumableCancelled
        }
        await purgeResumeRecordsForOtherUsers()
        prepareBackgroundSessionIfNeeded()

        let fileLength = try fileByteLength(at: localFile)
        let modificationTime = try fileModificationTime(at: localFile)
        let key = InFlightUploadKey(
            sermonLocalId: sermonLocalId,
            objectPath: objectPath,
            localFile: localFile,
            fileLength: fileLength,
            fileModificationTime: modificationTime
        )

        if let existing = inFlightUploads[key] {
            try await existing.value
            return
        }

        let task = Task { @MainActor in
            try await self.uploadResumableOnce(
                localFile: localFile,
                sermonLocalId: sermonLocalId,
                objectPath: objectPath,
                upsert: upsert,
                flagEpoch: self.flagOffEpoch,
                fileLength: fileLength,
                modificationTime: modificationTime
            )
        }
        if let raced = inFlightUploads[key] {
            try await raced.value
            return
        }
        inFlightUploads[key] = task
        defer { inFlightUploads.removeValue(forKey: key) }
        try await task.value
    }

    private func uploadResumableOnce(
        localFile: URL,
        sermonLocalId: UUID,
        objectPath: String,
        upsert: Bool,
        flagEpoch: UInt64,
        fileLength: Int64,
        modificationTime: TimeInterval
    ) async throws {
        guard fileLength >= 0 else { throw UploadManagerError.fileMissing }
        try throwIfResumableCancelled(epoch: flagEpoch)

        // Path authority must survive any await (mint → create gap, relaunch).
        if resumeStore.record(for: sermonLocalId) == nil {
            resumeStore.save(
                UploadResumeRecord(
                    sermonLocalId: sermonLocalId,
                    objectPath: objectPath,
                    uploadURL: nil,
                    uploadLength: fileLength,
                    filePath: localFile.path,
                    fileModificationTime: modificationTime,
                    taskIdentifier: nil,
                    ownerUserId: currentUserIdProvider(),
                    startedUnderFlag: true,
                    upsert: upsert
                )
            )
        }

        if let existing = resumeStore.record(for: sermonLocalId) {
            try validateRecordOwnership(existing)
        }

        // Adopt a live PATCH only when resuming the same file + TUS resource.
        // Fresh mints and stale-file remints must tear down old writers first.
        let existingRecord = resumeStore.record(for: sermonLocalId)
        if ResumableUploadPathResolver.shouldAdoptActiveBackgroundTask(
            record: existingRecord,
            objectPath: objectPath,
            localFile: localFile,
            fileLength: fileLength
        ) {
            try await awaitActiveUploadTaskIfAny(sermonLocalId: sermonLocalId)
        } else {
            try await cancelAndDrainUploadTasks(for: sermonLocalId)
        }
        try throwIfResumableCancelled(epoch: flagEpoch)

        if let existing = resumeStore.record(for: sermonLocalId),
           existing.objectPath == objectPath {
            if !existing.matchesLocalFile(localFile, length: fileLength) {
                try await abandonStaleResumeRecord(existing)
            } else if let uploadURL = existing.uploadURL {
                do {
                    let offset = try await headOffset(
                        uploadURL: uploadURL,
                        fileLength: fileLength,
                        sermonLocalId: sermonLocalId
                    )
                    if TusUploadClient.isUploadComplete(offset: offset, fileLength: fileLength) {
                        resumeStore.remove(sermonLocalId: sermonLocalId)
                        return
                    }
                    try await patchUntilComplete(
                        localFile: localFile,
                        sermonLocalId: sermonLocalId,
                        objectPath: objectPath,
                        uploadURL: uploadURL,
                        startOffset: offset,
                        fileLength: fileLength,
                        upsert: upsert
                    )
                    return
                } catch UploadManagerError.headRestart {
                    // Record discarded inside headOffset — drain before fresh CREATE.
                    try await cancelAndDrainUploadTasks(for: sermonLocalId)
                }
            }
        }

        try await cancelAndDrainUploadTasks(for: sermonLocalId, cancelRunning: false)

        var record = resumeStore.record(for: sermonLocalId) ?? UploadResumeRecord(
            sermonLocalId: sermonLocalId,
            objectPath: objectPath,
            uploadURL: nil,
            uploadLength: fileLength,
            filePath: localFile.path,
            fileModificationTime: modificationTime,
            taskIdentifier: nil,
            ownerUserId: currentUserIdProvider(),
            startedUnderFlag: true,
            upsert: upsert
        )
        record.objectPath = objectPath
        record.uploadLength = fileLength
        record.filePath = localFile.path
        record.fileModificationTime = modificationTime
        record.ownerUserId = currentUserIdProvider()
        record.upsert = upsert
        resumeStore.save(record)

        let uploadURL = try await createUpload(
            objectPath: objectPath,
            fileLength: fileLength,
            contentType: "audio/m4a",
            upsert: upsert
        )
        try throwIfResumableCancelled(epoch: flagEpoch)
        record.uploadURL = uploadURL
        resumeStore.save(record)

        try await patchUntilComplete(
            localFile: localFile,
            sermonLocalId: sermonLocalId,
            objectPath: objectPath,
            uploadURL: uploadURL,
            startOffset: 0,
            fileLength: fileLength,
            upsert: upsert
        )
    }

    func cancelInFlightResumableUploads(
        timeoutNanoseconds: UInt64 = UploadManager.flagOffCancelTimeoutNanoseconds
    ) async throws {
        prepareBackgroundSessionIfNeeded()
        // Stay closed after a successful drain so a mint/path-plan suspended while
        // the flag was on cannot admit a new TUS task before Settings commits off.
        resumableAdmissionClosed = true
        flagOffEpoch &+= 1

        do {
            try await drainResumableUploadsForFlagOff(timeoutNanoseconds: timeoutNanoseconds)
        } catch {
            // Flag stays on when drain fails — reopen so the user can retry or sync.
            resumableAdmissionClosed = false
            throw error
        }
    }

    /// Call after Settings commits `resumableUploads = true`.
    func reopenResumableAdmission() {
        guard featureFlags.resumableUploads else { return }
        resumableAdmissionClosed = false
    }

    private func drainResumableUploadsForFlagOff(timeoutNanoseconds: UInt64) async throws {
        let flagged = resumeStore.allRecords().filter(\.startedUnderFlag)
        let paths = Set(flagged.map(\.objectPath))
        let sermonIds = Self.sermonIdsAffectedByFlagOff(
            flaggedRecords: flagged,
            inFlightSermonIds: inFlightSermonIds()
        )

        for record in flagged where sermonIds.contains(record.sermonLocalId) {
            if let taskId = record.taskIdentifier {
                patchGate.cancelWait(taskId: taskId)
            }
        }
        for taskId in chunkFilesByTaskId.keys {
            patchGate.cancelWait(taskId: taskId)
        }

        let uploadTasks = await backgroundSession.tasks.1
        var cancelledTaskIds: Set<Int> = []
        for task in uploadTasks {
            guard let desc = task.taskDescription,
                  let id = UUID(uuidString: desc),
                  sermonIds.contains(id) else { continue }
            patchGate.cancelWait(taskId: task.taskIdentifier)
            switch task.state {
            case .running, .suspended:
                task.cancel()
                cancelledTaskIds.insert(task.taskIdentifier)
            default:
                break
            }
        }

        let operations = Array(inFlightUploads.values)
        for operation in operations {
            operation.cancel()
        }

        let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            let remainingSession = await backgroundSession.tasks.1.filter { task in
                guard let desc = task.taskDescription,
                      let id = UUID(uuidString: desc) else { return false }
                guard sermonIds.contains(id) else { return false }
                switch task.state {
                case .running, .suspended, .canceling:
                    return true
                default:
                    return false
                }
            }
            let remainingOps = inFlightSermonIds().contains(where: sermonIds.contains)
            if remainingSession.isEmpty && !remainingOps {
                removeAllFlaggedResumeRecords()
                if !paths.isEmpty {
                    print("[UploadManager] Cleared flagged resumable upload(s) after flag-off (cancelled \(cancelledTaskIds.count) URLSession task(s))")
                }
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw UploadManagerError.flagOffCancelTimedOut
    }

    // MARK: - Private

    private func fileByteLength(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize else {
            throw UploadManagerError.fileMissing
        }
        return Int64(size)
    }

    private func fileModificationTime(at url: URL) throws -> TimeInterval {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
        guard values.isRegularFile == true, let date = values.contentModificationDate else {
            throw UploadManagerError.fileMissing
        }
        return date.timeIntervalSince1970
    }

    private func cancelAndDrainUploadTasks(
        for sermonLocalId: UUID,
        timeoutNanoseconds: UInt64 = UploadManager.flagOffCancelTimeoutNanoseconds,
        cancelRunning: Bool = true
    ) async throws {
        let description = sermonLocalId.uuidString
        if cancelRunning {
            let uploadTasks = await backgroundSession.tasks.1
            for task in uploadTasks where task.taskDescription == description {
                switch task.state {
                case .running, .suspended:
                    task.cancel()
                default:
                    break
                }
            }
        }

        let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            let remaining = await backgroundSession.tasks.1.filter { task in
                guard task.taskDescription == description else { return false }
                switch task.state {
                case .running, .suspended, .canceling:
                    return true
                default:
                    return false
                }
            }
            if remaining.isEmpty { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw UploadManagerError.flagOffCancelTimedOut
    }

    private func createUpload(
        objectPath: String,
        fileLength: Int64,
        contentType: String,
        upsert: Bool
    ) async throws -> URL {
        let token = try await tokenProvider()
        let endpoint = TusUploadClient.resumableEndpoint(projectURL: projectURL)
        let request = TusUploadClient.makeCreateRequest(
            endpoint: endpoint,
            fileLength: fileLength,
            objectPath: objectPath,
            contentType: contentType,
            accessToken: token,
            anonKey: anonKey,
            upsert: upsert
        )
        let (_, response) = try await withTaskCancellationHandler {
            try await ephemeralSession.data(for: request)
        } onCancel: {}
        guard let http = response as? HTTPURLResponse else {
            throw UploadManagerError.createFailed(status: -1)
        }
        // 201 Created is the usual TUS success; some stacks return 200.
        guard (200...299).contains(http.statusCode),
              let location = TusUploadClient.parseLocation(from: http, endpoint: endpoint) else {
            throw UploadManagerError.createFailed(status: http.statusCode)
        }
        return location
    }

    private func headOffset(
        uploadURL: URL,
        fileLength: Int64,
        sermonLocalId: UUID
    ) async throws -> Int64 {
        if let headOffsetOverride {
            return try await headOffsetOverride(uploadURL, fileLength, sermonLocalId)
        }
        let token = try await tokenProvider()
        let request = TusUploadClient.makeHeadRequest(
            uploadURL: uploadURL,
            accessToken: token,
            anonKey: anonKey
        )
        let (_, response) = try await withTaskCancellationHandler {
            try await ephemeralSession.data(for: request)
        } onCancel: {}
        guard let http = response as? HTTPURLResponse else {
            throw UploadManagerError.headFailed(status: -1)
        }
        if TusUploadClient.shouldRestartResume(
            httpStatus: http.statusCode,
            offset: TusUploadClient.parseUploadOffset(from: http),
            fileLength: fileLength
        ) {
            resumeStore.remove(sermonLocalId: sermonLocalId)
            throw UploadManagerError.headRestart(status: http.statusCode)
        }
        guard (200...299).contains(http.statusCode),
              let offset = TusUploadClient.parseUploadOffset(from: http) else {
            // Keep the resume record — transient auth/server failures must not
            // abandon a valid TUS Location and restart from byte zero.
            throw UploadManagerError.headFailed(status: http.statusCode)
        }
        guard TusUploadClient.isValidOffset(offset, fileLength: fileLength) else {
            resumeStore.remove(sermonLocalId: sermonLocalId)
            throw UploadManagerError.headRestart(status: http.statusCode)
        }
        return offset
    }

    private func removeAllFlaggedResumeRecords() {
        for record in resumeStore.allRecords().filter(\.startedUnderFlag) {
            resumeStore.remove(sermonLocalId: record.sermonLocalId)
        }
    }

    private func purgeResumeRecordsForOtherUsers() async {
        guard let current = currentUserIdProvider() else { return }
        let foreign = resumeStore.allRecords().filter { record in
            record.ownerUserId != current
        }
        guard !foreign.isEmpty else { return }

        prepareBackgroundSessionIfNeeded()
        let sermonIds = Set(foreign.map(\.sermonLocalId))

        for record in foreign {
            if let taskId = record.taskIdentifier {
                patchGate.cancelWait(taskId: taskId)
            }
        }
        for taskId in chunkFilesByTaskId.keys {
            patchGate.cancelWait(taskId: taskId)
        }

        let uploadTasks = await backgroundSession.tasks.1
        for task in uploadTasks {
            guard let desc = task.taskDescription,
                  let id = UUID(uuidString: desc),
                  sermonIds.contains(id) else { continue }
            patchGate.cancelWait(taskId: task.taskIdentifier)
            switch task.state {
            case .running, .suspended:
                task.cancel()
            default:
                break
            }
        }

        for key in inFlightUploads.keys where sermonIds.contains(key.sermonLocalId) {
            inFlightUploads[key]?.cancel()
        }

        let deadline = ContinuousClock.now + .nanoseconds(Int64(Self.flagOffCancelTimeoutNanoseconds))
        while ContinuousClock.now < deadline {
            let remaining = await backgroundSession.tasks.1.filter { task in
                guard let desc = task.taskDescription,
                      let id = UUID(uuidString: desc),
                      sermonIds.contains(id) else { return false }
                switch task.state {
                case .running, .suspended, .canceling:
                    return true
                default:
                    return false
                }
            }
            let remainingOps = inFlightSermonIds().contains(where: sermonIds.contains)
            if remaining.isEmpty && !remainingOps {
                for record in foreign {
                    resumeStore.remove(sermonLocalId: record.sermonLocalId)
                }
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        // Drain incomplete — keep foreign records so a later pass can finish cancel.
        print("[UploadManager] Cross-account resume purge drain incomplete — retaining \(foreign.count) record(s)")
    }

    private func validateRecordOwnership(_ record: UploadResumeRecord) throws {
        // Do not delete mappings while unsigned-in — cancel/drain first via launch recovery.
        guard let current = currentUserIdProvider() else {
            throw UploadManagerError.notConfigured
        }
        guard record.ownerUserId == current else {
            resumeStore.remove(sermonLocalId: record.sermonLocalId)
            throw UploadManagerError.resumableCancelled
        }
    }

    private func abandonPartialStorageObject(at objectPath: String) async {
        do {
            try await storageObjectDeleter(objectPath)
        } catch {
            print("[UploadManager] Could not delete abandoned partial at \(objectPath): \(error.localizedDescription)")
        }
    }

    private func rehydrateChunkMapping(for task: URLSessionTask, sermonLocalId: UUID) {
        if chunkFilesByTaskId[task.taskIdentifier] != nil { return }
        if let record = resumeStore.record(for: sermonLocalId),
           let path = record.chunkFilePath {
            chunkFilesByTaskId[task.taskIdentifier] = URL(fileURLWithPath: path)
        }
    }

    private func awaitActiveUploadTaskIfAny(sermonLocalId: UUID) async throws {
        let tasks = await backgroundSession.tasks.1
        guard let task = tasks.first(where: { $0.taskDescription == sermonLocalId.uuidString }),
              Self.shouldAwaitBackgroundUploadTask(state: task.state) else {
            return
        }
        rehydrateChunkMapping(for: task, sermonLocalId: sermonLocalId)
        do {
            _ = try await waitForPatchCompletion(
                taskId: task.taskIdentifier,
                timeout: Self.chunkWaitTimeoutNanoseconds
            )
        } catch {
            if (error as? UploadManagerError) == .timedOut {
                task.cancel()
                try await drainUploadTask(task)
            }
            throw error
        }
    }

    private func drainUploadTask(_ task: URLSessionTask) async throws {
        let deadline = ContinuousClock.now + .nanoseconds(Int64(Self.flagOffCancelTimeoutNanoseconds))
        while ContinuousClock.now < deadline {
            let tasks = await backgroundSession.tasks.1
            if !tasks.contains(where: { $0.taskIdentifier == task.taskIdentifier }) {
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw UploadManagerError.flagOffCancelTimedOut
    }

    private func patchUntilComplete(
        localFile: URL,
        sermonLocalId: UUID,
        objectPath: String,
        uploadURL: URL,
        startOffset: Int64,
        fileLength: Int64,
        upsert: Bool
    ) async throws {
        var offset = startOffset
        while !TusUploadClient.isUploadComplete(offset: offset, fileLength: fileLength) {
            guard let range = TusUploadClient.nextChunkRange(offset: offset, fileLength: fileLength) else {
                throw UploadManagerError.incomplete(offset: offset, length: fileLength)
            }
            offset = try await patchChunk(
                localFile: localFile,
                sermonLocalId: sermonLocalId,
                objectPath: objectPath,
                uploadURL: uploadURL,
                range: range,
                fileLength: fileLength,
                upsert: upsert
            )
        }
        resumeStore.remove(sermonLocalId: sermonLocalId)
    }

    private func patchChunk(
        localFile: URL,
        sermonLocalId: UUID,
        objectPath: String,
        uploadURL: URL,
        range: Range<Int64>,
        fileLength: Int64,
        upsert: Bool
    ) async throws -> Int64 {
        let task = try await preparePatchUploadTask(
            localFile: localFile,
            sermonLocalId: sermonLocalId,
            objectPath: objectPath,
            uploadURL: uploadURL,
            range: range,
            fileLength: fileLength,
            upsert: upsert
        )
        let http: HTTPURLResponse
        do {
            http = try await patchGate.wait(
                taskId: task.taskIdentifier,
                timeoutNanoseconds: Self.chunkWaitTimeoutNanoseconds,
                timedOutError: UploadManagerError.timedOut,
                beforeWaiting: { task.resume() }
            )
        } catch {
            if (error as? UploadManagerError) == .timedOut {
                task.cancel()
                try await drainUploadTask(task)
            }
            throw error
        }
        return try await interpretPatchResponse(
            http: http,
            uploadURL: uploadURL,
            range: range,
            fileLength: fileLength,
            sermonLocalId: sermonLocalId
        )
    }

    private func preparePatchUploadTask(
        localFile: URL,
        sermonLocalId: UUID,
        objectPath: String,
        uploadURL: URL,
        range: Range<Int64>,
        fileLength: Int64,
        upsert: Bool
    ) async throws -> URLSessionUploadTask {
        let token = try await tokenProvider()
        let chunkURL = try writeChunkFile(from: localFile, range: range)

        let contentLength = range.upperBound - range.lowerBound
        let request = TusUploadClient.makePatchRequest(
            uploadURL: uploadURL,
            offset: range.lowerBound,
            contentLength: contentLength,
            accessToken: token,
            anonKey: anonKey
        )
        let task = backgroundSession.uploadTask(with: request, fromFile: chunkURL)
        task.taskDescription = sermonLocalId.uuidString
        chunkFilesByTaskId[task.taskIdentifier] = chunkURL

        if var existingRecord = resumeStore.record(for: sermonLocalId) {
            if let oldPath = existingRecord.chunkFilePath,
               oldPath != chunkURL.path,
               !(await isChunkFileInUse(path: oldPath, taskIdentifier: existingRecord.taskIdentifier)) {
                try? FileManager.default.removeItem(atPath: oldPath)
            }
            existingRecord.taskIdentifier = task.taskIdentifier
            existingRecord.chunkFilePath = chunkURL.path
            existingRecord.uploadURL = uploadURL
            existingRecord.objectPath = objectPath
            resumeStore.save(existingRecord)
        }

        var record = resumeStore.record(for: sermonLocalId) ?? UploadResumeRecord(
            sermonLocalId: sermonLocalId,
            objectPath: objectPath,
            uploadURL: uploadURL,
            uploadLength: fileLength,
            filePath: localFile.path,
            fileModificationTime: try? fileModificationTime(at: localFile),
            taskIdentifier: task.taskIdentifier,
            chunkFilePath: chunkURL.path,
            ownerUserId: currentUserIdProvider(),
            startedUnderFlag: true,
            upsert: upsert
        )
        record.uploadURL = uploadURL
        record.taskIdentifier = task.taskIdentifier
        record.chunkFilePath = chunkURL.path
        record.ownerUserId = currentUserIdProvider()
        record.objectPath = objectPath
        resumeStore.save(record)
        return task
    }

    private func isChunkFileInUse(path: String, taskIdentifier: Int?) async -> Bool {
        if let taskIdentifier, chunkFilesByTaskId[taskIdentifier]?.path == path {
            return true
        }
        guard let taskIdentifier else { return false }
        let tasks = await backgroundSession.tasks.1
        return tasks.contains {
            $0.taskIdentifier == taskIdentifier
                && Self.shouldAwaitBackgroundUploadTask(state: $0.state)
        }
    }

    private func interpretPatchResponse(
        http: HTTPURLResponse,
        uploadURL: URL,
        range: Range<Int64>,
        fileLength: Int64,
        sermonLocalId: UUID
    ) async throws -> Int64 {
        if http.statusCode == 401 {
            _ = try await tokenProvider()
            return try await headOffset(
                uploadURL: uploadURL,
                fileLength: fileLength,
                sermonLocalId: sermonLocalId
            )
        }
        if http.statusCode == 409 {
            return try await headOffset(
                uploadURL: uploadURL,
                fileLength: fileLength,
                sermonLocalId: sermonLocalId
            )
        }
        guard http.statusCode == 204,
              let newOffset = TusUploadClient.parseUploadOffset(from: http),
              TusUploadClient.isValidOffset(newOffset, fileLength: fileLength) else {
            throw UploadManagerError.patchFailed(status: http.statusCode)
        }
        guard newOffset == range.upperBound else {
            throw UploadManagerError.invalidOffset(offset: newOffset, length: fileLength)
        }
        return newOffset
    }

    private func schedulePatchChunkAndContinue(
        localFile: URL,
        sermonLocalId: UUID,
        objectPath: String,
        uploadURL: URL,
        range: Range<Int64>,
        fileLength: Int64,
        upsert: Bool
    ) async throws {
        let task = try await preparePatchUploadTask(
            localFile: localFile,
            sermonLocalId: sermonLocalId,
            objectPath: objectPath,
            uploadURL: uploadURL,
            range: range,
            fileLength: fileLength,
            upsert: upsert
        )

        await withCheckedContinuation { (scheduled: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                do {
                    let http = try await self.patchGate.wait(
                        taskId: task.taskIdentifier,
                        timeoutNanoseconds: Self.chunkWaitTimeoutNanoseconds,
                        timedOutError: UploadManagerError.timedOut,
                        beforeWaiting: {
                            task.resume()
                            scheduled.resume()
                            self.onPatchTaskScheduled?()
                        }
                    )
                    let newOffset = try await self.interpretPatchResponse(
                        http: http,
                        uploadURL: uploadURL,
                        range: range,
                        fileLength: fileLength,
                        sermonLocalId: sermonLocalId
                    )
                    try await self.patchUntilComplete(
                        localFile: localFile,
                        sermonLocalId: sermonLocalId,
                        objectPath: objectPath,
                        uploadURL: uploadURL,
                        startOffset: newOffset,
                        fileLength: fileLength,
                        upsert: upsert
                    )
                } catch {
                    if (error as? UploadManagerError) == .timedOut {
                        task.cancel()
                        try? await self.drainUploadTask(task)
                    }
                    print("[UploadManager] Background chunk continuation failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func writeChunkFile(from file: URL, range: Range<Int64>) throws -> URL {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(range.lowerBound))
        let count = Int(range.upperBound - range.lowerBound)
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw UploadManagerError.fileMissing
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tus-chunk-\(UUID().uuidString)")
        try data.write(to: temp, options: .atomic)
        return temp
    }

    private func waitForPatchCompletion(taskId: Int, timeout: UInt64) async throws -> HTTPURLResponse {
        try await patchGate.wait(
            taskId: taskId,
            timeoutNanoseconds: timeout,
            timedOutError: UploadManagerError.timedOut
        )
    }

    private func finishPatch(taskId: Int, result: Result<HTTPURLResponse, Error>) {
        removeChunkFile(forTaskId: taskId)
        patchGate.finish(taskId: taskId, result: result)
    }

    private func removeChunkFile(forTaskId taskId: Int) {
        if let chunkURL = chunkFilesByTaskId.removeValue(forKey: taskId) {
            try? FileManager.default.removeItem(at: chunkURL)
            clearPersistedChunkReference(forTaskId: taskId)
            return
        }
        guard var record = resumeStore.record(forTaskIdentifier: taskId),
              let path = record.chunkFilePath else {
            return
        }
        try? FileManager.default.removeItem(atPath: path)
        record.chunkFilePath = nil
        if record.taskIdentifier == taskId {
            record.taskIdentifier = nil
        }
        resumeStore.save(record)
    }

    private func clearPersistedChunkReference(forTaskId taskId: Int) {
        guard var record = resumeStore.record(forTaskIdentifier: taskId) else { return }
        record.chunkFilePath = nil
        if record.taskIdentifier == taskId {
            record.taskIdentifier = nil
        }
        resumeStore.save(record)
    }

    private func reconcileOrphanedChunkFiles() async {
        let activeTaskIds = Set(
            (await backgroundSession.tasks.1)
                .filter { Self.shouldAwaitBackgroundUploadTask(state: $0.state) }
                .map(\.taskIdentifier)
        )
        for var record in resumeStore.allRecords() {
            guard let path = record.chunkFilePath else { continue }
            let taskActive = record.taskIdentifier.map { activeTaskIds.contains($0) } ?? false
            guard !taskActive else { continue }
            try? FileManager.default.removeItem(atPath: path)
            record.chunkFilePath = nil
            record.taskIdentifier = nil
            resumeStore.save(record)
        }
        let protectedPaths = Set(
            resumeStore.allRecords().compactMap { record -> String? in
                guard let path = record.chunkFilePath,
                      let taskId = record.taskIdentifier,
                      activeTaskIds.contains(taskId) else {
                    return nil
                }
                return path
            }
        )
        let tempDir = FileManager.default.temporaryDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in entries where url.lastPathComponent.hasPrefix("tus-chunk-") {
            guard !protectedPaths.contains(url.path) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Test seam — relaunch cleanup when the in-memory chunk map is empty.
    internal func finishPatchForTesting(taskId: Int) {
        finishPatch(
            taskId: taskId,
            result: .failure(UploadManagerError.patchFailed(status: -1))
        )
    }

    func scheduleIncompleteBackgroundUploadContinuations() async {
        // Auth may still be restoring on cold launch — a nil user here is not
        // confirmed sign-out. Sign-out itself drains via clearPersistedResumeRecords().
        guard currentUserIdProvider() != nil else { return }
        guard featureFlags.resumableUploads else {
            let flagged = resumeStore.allRecords().filter(\.startedUnderFlag)
            for record in flagged {
                resumeStore.remove(sermonLocalId: record.sermonLocalId)
            }
            return
        }
        prepareBackgroundSessionIfNeeded()
        await purgeResumeRecordsForOtherUsers()
        await reconcileOrphanedChunkFiles()
        let records = resumeStore.allRecords().filter {
            $0.startedUnderFlag && $0.uploadURL != nil
        }
        for record in records {
            do {
                try await scheduleUploadContinuation(for: record)
            } catch {
                print("[UploadManager] Background upload schedule failed: \(error.localizedDescription)")
            }
        }
    }

    func continueIncompleteBackgroundUploads() async {
        await scheduleIncompleteBackgroundUploadContinuations()
    }

    private func scheduleUploadContinuation(for record: UploadResumeRecord) async throws {
        let sermonLocalId = record.sermonLocalId
        guard backgroundContinuationsInFlight.insert(sermonLocalId).inserted else {
            return
        }
        defer { backgroundContinuationsInFlight.remove(sermonLocalId) }

        let localURL = URL(fileURLWithPath: record.filePath)
        guard let uploadURL = record.uploadURL else {
            return
        }
        guard record.matchesLocalFile(localURL, length: record.uploadLength) else {
            try await abandonStaleResumeRecord(record)
            return
        }
        try validateRecordOwnership(record)

        if try await adoptPersistedBackgroundTaskIfAny(
            record: record,
            localURL: localURL,
            uploadURL: uploadURL
        ) {
            return
        }

        let fileLength = record.uploadLength
        let offset = try await headOffset(
            uploadURL: uploadURL,
            fileLength: fileLength,
            sermonLocalId: sermonLocalId
        )
        if TusUploadClient.isUploadComplete(offset: offset, fileLength: fileLength) {
            resumeStore.remove(sermonLocalId: sermonLocalId)
            return
        }
        guard let range = TusUploadClient.nextChunkRange(offset: offset, fileLength: fileLength) else {
            throw UploadManagerError.incomplete(offset: offset, length: fileLength)
        }

        try await schedulePatchChunkAndContinue(
            localFile: localURL,
            sermonLocalId: sermonLocalId,
            objectPath: record.objectPath,
            uploadURL: uploadURL,
            range: range,
            fileLength: fileLength,
            upsert: record.upsert
        )
    }

    /// Wait for a relaunch-persisted background PATCH instead of scheduling a duplicate.
    private func adoptPersistedBackgroundTaskIfAny(
        record: UploadResumeRecord,
        localURL: URL,
        uploadURL: URL
    ) async throws -> Bool {
        let tasks = await backgroundSession.tasks.1
        guard let active = tasks.first(where: { $0.taskDescription == record.sermonLocalId.uuidString }),
              Self.shouldAwaitBackgroundUploadTask(state: active.state) else {
            return false
        }

        rehydrateChunkMapping(for: active, sermonLocalId: record.sermonLocalId)
        if var updated = resumeStore.record(for: record.sermonLocalId) {
            updated.taskIdentifier = active.taskIdentifier
            resumeStore.save(updated)
        }

        await withCheckedContinuation { (adopted: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                var didSignal = false
                let signalAdopted = {
                    guard !didSignal else { return }
                    didSignal = true
                    adopted.resume()
                    self.onPatchTaskScheduled?()
                }
                // Acknowledge adoption before waiting so an early PATCH completion
                // that skips/races beforeWaiting cannot hang background scheduling.
                if active.state == .suspended {
                    active.resume()
                }
                signalAdopted()
                do {
                    _ = try await self.patchGate.wait(
                        taskId: active.taskIdentifier,
                        timeoutNanoseconds: Self.chunkWaitTimeoutNanoseconds,
                        timedOutError: UploadManagerError.timedOut,
                        beforeWaiting: signalAdopted
                    )
                    let fileLength = record.uploadLength
                    let offset = try await self.headOffset(
                        uploadURL: uploadURL,
                        fileLength: fileLength,
                        sermonLocalId: record.sermonLocalId
                    )
                    if TusUploadClient.isUploadComplete(offset: offset, fileLength: fileLength) {
                        self.resumeStore.remove(sermonLocalId: record.sermonLocalId)
                        return
                    }
                    try await self.patchUntilComplete(
                        localFile: localURL,
                        sermonLocalId: record.sermonLocalId,
                        objectPath: record.objectPath,
                        uploadURL: uploadURL,
                        startOffset: offset,
                        fileLength: fileLength,
                        upsert: record.upsert
                    )
                } catch {
                    if (error as? UploadManagerError) == .timedOut {
                        active.cancel()
                        try? await self.drainUploadTask(active)
                    }
                    print("[UploadManager] Adopted background task failed: \(error.localizedDescription)")
                }
            }
        }
        return true
    }

    /// Mirrors `urlSessionDidFinishEvents` for tests — schedule work, then ack iOS.
    func finishBackgroundSessionEventsForTesting() async {
        await scheduleIncompleteBackgroundUploadContinuations()
        let handler = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        handler?()
    }
}

extension UploadManager: URLSessionTaskDelegate, URLSessionDataDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let taskId = task.taskIdentifier
        let response = task.response as? HTTPURLResponse
        Task { @MainActor in
            if let error {
                self.finishPatch(taskId: taskId, result: .failure(error))
                return
            }
            guard let response else {
                self.finishPatch(
                    taskId: taskId,
                    result: .failure(UploadManagerError.patchFailed(status: -1))
                )
                return
            }
            // Caller applies the strict success predicate (204 + offset).
            self.finishPatch(taskId: taskId, result: .success(response))
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            await self.scheduleIncompleteBackgroundUploadContinuations()
            let handler = self.backgroundCompletionHandler
            self.backgroundCompletionHandler = nil
            handler?()
        }
    }
}
