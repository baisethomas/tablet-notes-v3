import Foundation

enum UploadManagerError: LocalizedError {
    case fileMissing
    case createFailed(status: Int)
    case patchFailed(status: Int)
    case headFailed(status: Int)
    case incomplete(offset: Int64, length: Int64)
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
        case .headFailed(let status):
            return "Could not resume upload (\(status))."
        case .incomplete(let offset, let length):
            return "Upload incomplete (\(offset)/\(length) bytes)."
        case .timedOut:
            return "Upload timed out waiting for the system transfer."
        case .flagOffCancelTimedOut:
            return "Could not cancel in-flight uploads before switching modes."
        case .notConfigured:
            return "Upload manager is not configured."
        }
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
    private var patchContinuations: [Int: CheckedContinuation<HTTPURLResponse, Error>] = [:]
    private var prepared = false

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
        prepareBackgroundSessionIfNeeded()

        let fileLength = try fileByteLength(at: localFile)
        guard fileLength >= 0 else { throw UploadManagerError.fileMissing }

        // Adopt — never start a second writer to the same stable path.
        if let existing = resumeStore.record(for: sermonLocalId),
           existing.objectPath == objectPath,
           let uploadURL = existing.uploadURL {
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
            } catch UploadManagerError.headFailed {
                // Record discarded inside headOffset on 404/410 / over-length —
                // fall through to a fresh create.
            }
        }

        // Also adopt a live background task if the process died mid-continuation.
        let tasks = await backgroundSession.tasks.1 // uploadTasks
        if tasks.contains(where: { $0.taskDescription == sermonLocalId.uuidString }) {
            // Wait for the in-flight chunk; then re-enter via HEAD.
            if let task = tasks.first(where: { $0.taskDescription == sermonLocalId.uuidString }) {
                _ = try await awaitPatchTask(task, timeout: Self.chunkWaitTimeoutNanoseconds)
            }
            if let uploadURL = resumeStore.record(for: sermonLocalId)?.uploadURL {
                let offset = try await headOffset(uploadURL: uploadURL, fileLength: fileLength, sermonLocalId: sermonLocalId)
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
            }
        }

        var record = UploadResumeRecord(
            sermonLocalId: sermonLocalId,
            objectPath: objectPath,
            uploadURL: nil,
            uploadLength: fileLength,
            filePath: localFile.path,
            taskIdentifier: nil,
            startedUnderFlag: true,
            upsert: upsert
        )
        resumeStore.save(record)

        let uploadURL = try await createUpload(
            objectPath: objectPath,
            fileLength: fileLength,
            contentType: "audio/m4a",
            upsert: upsert
        )
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
        let flagged = resumeStore.allRecords().filter(\.startedUnderFlag)
        let paths = Set(flagged.map(\.objectPath))
        let sermonIds = Set(flagged.map(\.sermonLocalId))

        let uploadTasks = await backgroundSession.tasks.1
        for task in uploadTasks {
            if let desc = task.taskDescription,
               let id = UUID(uuidString: desc),
               sermonIds.contains(id) {
                task.cancel()
            }
        }

        let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            let remaining = await backgroundSession.tasks.1.filter { task in
                guard let desc = task.taskDescription,
                      let id = UUID(uuidString: desc) else { return false }
                return sermonIds.contains(id)
            }
            if remaining.isEmpty {
                for id in sermonIds { resumeStore.remove(sermonLocalId: id) }
                // paths retained only for clarity in logs
                if !paths.isEmpty {
                    print("[UploadManager] Cleared \(sermonIds.count) resumable upload(s) after flag-off")
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
        let (_, response) = try await ephemeralSession.data(for: request)
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
        let (_, response) = try await ephemeralSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UploadManagerError.headFailed(status: -1)
        }
        if TusUploadClient.shouldRestartResume(
            httpStatus: http.statusCode,
            offset: TusUploadClient.parseUploadOffset(from: http),
            fileLength: fileLength
        ) {
            resumeStore.remove(sermonLocalId: sermonLocalId)
            throw UploadManagerError.headFailed(status: http.statusCode)
        }
        guard (200...299).contains(http.statusCode),
              let offset = TusUploadClient.parseUploadOffset(from: http) else {
            throw UploadManagerError.headFailed(status: http.statusCode)
        }
        return offset
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
        // Do not delete until the background task finishes — the system may
        // read the file after this method returns.

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

        var record = resumeStore.record(for: sermonLocalId) ?? UploadResumeRecord(
            sermonLocalId: sermonLocalId,
            objectPath: objectPath,
            uploadURL: uploadURL,
            uploadLength: fileLength,
            filePath: localFile.path,
            taskIdentifier: task.taskIdentifier,
            startedUnderFlag: true,
            upsert: upsert
        )
        record.uploadURL = uploadURL
        record.taskIdentifier = task.taskIdentifier
        record.objectPath = objectPath
        resumeStore.save(record)

        task.resume()
        defer { try? FileManager.default.removeItem(at: chunkURL) }
        let http = try await awaitPatchTask(task, timeout: Self.chunkWaitTimeoutNanoseconds)

        if http.statusCode == 401 {
            // Refresh and re-HEAD rather than treating as success.
            _ = try await tokenProvider()
            return try await headOffset(uploadURL: uploadURL, fileLength: fileLength, sermonLocalId: sermonLocalId)
        }
        if http.statusCode == 409 {
            return try await headOffset(uploadURL: uploadURL, fileLength: fileLength, sermonLocalId: sermonLocalId)
        }
        guard http.statusCode == 204,
              let newOffset = TusUploadClient.parseUploadOffset(from: http) else {
            throw UploadManagerError.patchFailed(status: http.statusCode)
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

    private func awaitPatchTask(
        _ task: URLSessionUploadTask,
        timeout: UInt64
    ) async throws -> HTTPURLResponse {
        try await withThrowingTaskGroup(of: HTTPURLResponse.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HTTPURLResponse, Error>) in
                    self.patchContinuations[task.taskIdentifier] = cont
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeout)
                throw UploadManagerError.timedOut
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func finishPatch(taskId: Int, result: Result<HTTPURLResponse, Error>) {
        guard let cont = patchContinuations.removeValue(forKey: taskId) else { return }
        switch result {
        case .success(let response):
            cont.resume(returning: response)
        case .failure(let error):
            cont.resume(throwing: error)
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
            let handler = self.backgroundCompletionHandler
            self.backgroundCompletionHandler = nil
            handler?()
        }
    }
}
