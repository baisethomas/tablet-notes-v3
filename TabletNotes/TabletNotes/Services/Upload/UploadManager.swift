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
    private let tokenProvider: () async throws -> String
    private let ephemeralSession: URLSession

    private var backgroundSession: URLSession!
    private var backgroundCompletionHandler: (() -> Void)?
    private let patchGate = PatchCompletionGate()
    /// Temp chunk files keyed by URLSession task id — deleted only after the
    /// task completes (or is cancelled), never while the system may still read.
    private var chunkFilesByTaskId: [Int: URL] = [:]
    /// Coalesce concurrent sync attempts for the same sermon into one upload op.
    private var inFlightUploads: [InFlightUploadKey: Task<Void, Error>] = [:]
    /// Incremented when resumable uploads are disabled; in-flight ops observe this.
    private var flagOffEpoch: UInt64 = 0
    /// While flag-off drain runs, reject newly admitted resumable uploads.
    private var resumableAdmissionClosed = false
    private var prepared = false

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
        try Task.checkCancellation()
    }

    /// Test seam — inject store / token / URLs without touching the real session.
    init(
        projectURL: URL = URL(string: SupabaseConfig.projectURL)!,
        anonKey: String = SupabaseConfig.anonKey,
        resumeStore: UploadResumeStoring = UploadResumeStore(),
        tokenProvider: (() async throws -> String)? = nil,
        createBackgroundSession: Bool = true
    ) {
        self.projectURL = projectURL
        self.anonKey = anonKey
        self.resumeStore = resumeStore
        self.tokenProvider = tokenProvider ?? {
            let session = try await SupabaseService.shared.client.auth.session
            return session.accessToken
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
        guard !resumableAdmissionClosed else {
            throw UploadManagerError.resumableCancelled
        }
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
                    startedUnderFlag: true,
                    upsert: upsert
                )
            )
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
                resumeStore.remove(sermonLocalId: sermonLocalId)
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
            startedUnderFlag: true,
            upsert: upsert
        )
        record.objectPath = objectPath
        record.uploadLength = fileLength
        record.filePath = localFile.path
        record.fileModificationTime = modificationTime
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
        resumableAdmissionClosed = true
        defer { resumableAdmissionClosed = false }
        flagOffEpoch &+= 1

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
                for id in sermonIds { resumeStore.remove(sermonLocalId: id) }
                if !paths.isEmpty {
                    print("[UploadManager] Cleared \(sermonIds.count) resumable upload(s) after flag-off (cancelled \(cancelledTaskIds.count) URLSession task(s))")
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

    private func awaitActiveUploadTaskIfAny(sermonLocalId: UUID) async throws {
        let tasks = await backgroundSession.tasks.1
        guard let task = tasks.first(where: { $0.taskDescription == sermonLocalId.uuidString }) else {
            return
        }
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

    private func drainUploadTask(_ task: URLSessionUploadTask) async throws {
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
        let token = try await tokenProvider()
        let chunkURL = try writeChunkFile(from: localFile, range: range)
        // Kept until didComplete / cancel — see chunkFilesByTaskId.

        let contentLength = range.upperBound - range.lowerBound
        var request = TusUploadClient.makePatchRequest(
            uploadURL: uploadURL,
            offset: range.lowerBound,
            contentLength: contentLength,
            accessToken: token,
            anonKey: anonKey
        )
        // Background upload task
        let task = backgroundSession.uploadTask(with: request, fromFile: chunkURL)
        task.taskDescription = sermonLocalId.uuidString
        chunkFilesByTaskId[task.taskIdentifier] = chunkURL

        // Persist task id before any await so relaunch can adopt the live task.
        if var existingRecord = resumeStore.record(for: sermonLocalId) {
            existingRecord.taskIdentifier = task.taskIdentifier
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
            startedUnderFlag: true,
            upsert: upsert
        )
        record.uploadURL = uploadURL
        record.taskIdentifier = task.taskIdentifier
        record.objectPath = objectPath
        resumeStore.save(record)

        // Register the waiter on this MainActor turn BEFORE resume so a short
        // final chunk cannot complete into a dropped finishPatch.
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

        if http.statusCode == 401 {
            // Refresh and re-HEAD rather than treating as success.
            _ = try await tokenProvider()
            return try await headOffset(uploadURL: uploadURL, fileLength: fileLength, sermonLocalId: sermonLocalId)
        }
        if http.statusCode == 409 {
            return try await headOffset(uploadURL: uploadURL, fileLength: fileLength, sermonLocalId: sermonLocalId)
        }
        guard http.statusCode == 204,
              let newOffset = TusUploadClient.parseUploadOffset(from: http),
              TusUploadClient.isValidOffset(newOffset, fileLength: fileLength) else {
            throw UploadManagerError.patchFailed(status: http.statusCode)
        }
        // TUS: successful PATCH advances Upload-Offset to the end of the chunk.
        guard newOffset == range.upperBound else {
            throw UploadManagerError.invalidOffset(offset: newOffset, length: fileLength)
        }
        return newOffset
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
        if let chunkURL = chunkFilesByTaskId.removeValue(forKey: taskId) {
            try? FileManager.default.removeItem(at: chunkURL)
        }
        patchGate.finish(taskId: taskId, result: result)
    }
    private func continueIncompleteBackgroundUploads() async {
        let records = resumeStore.allRecords().filter {
            $0.startedUnderFlag && $0.uploadURL != nil
        }
        for record in records {
            let localURL = URL(fileURLWithPath: record.filePath)
            guard record.matchesLocalFile(localURL, length: record.uploadLength) else { continue }
            do {
                try await uploadResumable(
                    localFile: localURL,
                    sermonLocalId: record.sermonLocalId,
                    objectPath: record.objectPath,
                    upsert: record.upsert
                )
            } catch {
                print("[UploadManager] Background upload continue failed: \(error.localizedDescription)")
            }
        }
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
            // Call the system handler promptly — do not await a full multi-chunk upload here.
            let handler = self.backgroundCompletionHandler
            self.backgroundCompletionHandler = nil
            handler?()
            Task { @MainActor in
                await self.continueIncompleteBackgroundUploads()
            }
        }
    }
}
