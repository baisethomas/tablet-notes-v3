import Foundation
import Testing
@testable import TabletNotes

struct TusUploadClientTests {
    @Test func chunkSizeIsExactlySixMegabytes() {
        #expect(TusUploadClient.chunkSize == 6 * 1024 * 1024)
    }

    @Test func nextChunkRangeCoversFullChunksAndAShortTail() {
        let length: Int64 = TusUploadClient.chunkSize + 100
        let first = TusUploadClient.nextChunkRange(offset: 0, fileLength: length)
        #expect(first == 0..<TusUploadClient.chunkSize)

        let second = TusUploadClient.nextChunkRange(offset: TusUploadClient.chunkSize, fileLength: length)
        #expect(second == TusUploadClient.chunkSize..<length)

        #expect(TusUploadClient.nextChunkRange(offset: length, fileLength: length) == nil)
    }

    @Test func isUploadCompleteRequiresExactOffsetMatch() {
        #expect(TusUploadClient.isUploadComplete(offset: 10, fileLength: 10))
        #expect(!TusUploadClient.isUploadComplete(offset: 9, fileLength: 10))
        #expect(!TusUploadClient.isUploadComplete(offset: 11, fileLength: 10))
    }

    @Test func uploadMetadataIsBase64KeyedPairs() {
        let meta = TusUploadClient.encodeUploadMetadata(
            objectName: "user/sermon.m4a",
            contentType: "audio/m4a"
        )
        #expect(meta.contains("bucketName "))
        #expect(meta.contains("objectName "))
        #expect(meta.contains("contentType "))
        // objectName value
        let expected = Data("user/sermon.m4a".utf8).base64EncodedString()
        #expect(meta.contains("objectName \(expected)"))
    }

    @Test func createRequestSetsUpsertAndUploadLength() throws {
        let endpoint = URL(string: "https://example.supabase.co/storage/v1/upload/resumable")!
        let request = TusUploadClient.makeCreateRequest(
            endpoint: endpoint,
            fileLength: 42,
            objectPath: "abc/def.m4a",
            contentType: "audio/m4a",
            accessToken: "tok",
            anonKey: "anon",
            upsert: true
        )
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Upload-Length") == "42")
        #expect(request.value(forHTTPHeaderField: "x-upsert") == "true")
        #expect(request.value(forHTTPHeaderField: "Tus-Resumable") == "1.0.0")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon")
    }

    @Test func createRequestOmitsUpsertWhenFalse() {
        let endpoint = URL(string: "https://example.supabase.co/storage/v1/upload/resumable")!
        let request = TusUploadClient.makeCreateRequest(
            endpoint: endpoint,
            fileLength: 1,
            objectPath: "a/b.m4a",
            contentType: "audio/m4a",
            accessToken: "t",
            anonKey: "a",
            upsert: false
        )
        #expect(request.value(forHTTPHeaderField: "x-upsert") == nil)
    }

    @Test func shouldRestartOnGoneOrOverLengthOffset() {
        #expect(TusUploadClient.shouldRestartResume(httpStatus: 404, offset: 0, fileLength: 10))
        #expect(TusUploadClient.shouldRestartResume(httpStatus: 410, offset: 0, fileLength: 10))
        #expect(TusUploadClient.shouldRestartResume(httpStatus: 200, offset: 11, fileLength: 10))
        #expect(!TusUploadClient.shouldRestartResume(httpStatus: 200, offset: 5, fileLength: 10))
        // Transient statuses must NOT restart — keep the TUS Location.
        #expect(!TusUploadClient.shouldRestartResume(httpStatus: 401, offset: nil, fileLength: 10))
        #expect(!TusUploadClient.shouldRestartResume(httpStatus: 403, offset: nil, fileLength: 10))
        #expect(!TusUploadClient.shouldRestartResume(httpStatus: 500, offset: nil, fileLength: 10))
        #expect(!TusUploadClient.shouldRestartResume(httpStatus: 200, offset: nil, fileLength: 10))
        #expect(TusUploadClient.shouldRestartResume(httpStatus: 200, offset: -1, fileLength: 10))
        #expect(!TusUploadClient.isValidOffset(-1, fileLength: 10))
        #expect(TusUploadClient.isValidOffset(0, fileLength: 10))
        #expect(TusUploadClient.isValidOffset(10, fileLength: 10))
        #expect(TusUploadClient.nextChunkRange(offset: -1, fileLength: 10) == nil)
    }

    @Test func parseLocationResolvesRelativeUrls() throws {
        let endpoint = URL(string: "https://example.supabase.co/storage/v1/upload/resumable")!
        let response = HTTPURLResponse(
            url: endpoint,
            statusCode: 201,
            httpVersion: nil,
            headerFields: ["Location": "/storage/v1/upload/resumable/abc"]
        )!
        let location = TusUploadClient.parseLocation(from: response, endpoint: endpoint)
        #expect(location?.absoluteString.contains("/storage/v1/upload/resumable/abc") == true)
    }

    @Test func parseLocationRejectsUntrustedAbsoluteHost() {
        let endpoint = URL(string: "https://example.supabase.co/storage/v1/upload/resumable")!
        let response = HTTPURLResponse(
            url: endpoint,
            statusCode: 201,
            httpVersion: nil,
            headerFields: ["Location": "https://evil.example/upload/hijack"]
        )!
        #expect(TusUploadClient.parseLocation(from: response, endpoint: endpoint) == nil)
    }

    @Test func isTrustedUploadLocationAllowsSameOrigin() {
        let endpoint = URL(string: "https://example.supabase.co/storage/v1/upload/resumable")!
        let location = URL(string: "https://example.supabase.co/storage/v1/upload/resumable/abc")!
        #expect(TusUploadClient.isTrustedUploadLocation(location, endpoint: endpoint))
    }
}

@MainActor
struct PatchCompletionGateTests {
    @Test func deliversEarlyCompletionWhenFinishBeatsWaiterRegistration() async throws {
        let gate = PatchCompletionGate()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: ["Upload-Offset": "10"]
        )!
        gate.finish(taskId: 42, result: .success(response))
        let got = try await gate.wait(
            taskId: 42,
            timeoutNanoseconds: 5_000_000_000,
            timedOutError: UploadManagerError.timedOut
        )
        #expect(got.statusCode == 204)
    }

    @Test func timesOutWhenNoDelegateCompletionArrives() async {
        let gate = PatchCompletionGate()
        do {
            _ = try await gate.wait(
                taskId: 7,
                timeoutNanoseconds: 50_000_000,
                timedOutError: UploadManagerError.timedOut
            )
            Issue.record("expected timeout")
        } catch let error as UploadManagerError {
            #expect(error == .timedOut)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func discardsLateCompletionAfterTimeout() async throws {
        let gate = PatchCompletionGate()
        do {
            _ = try await gate.wait(
                taskId: 9,
                timeoutNanoseconds: 30_000_000,
                timedOutError: UploadManagerError.timedOut
            )
            Issue.record("expected timeout")
        } catch is UploadManagerError {
            // expected
        }
        let late = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!
        gate.finish(taskId: 9, result: .success(late))
        // A fresh wait on a new id still works; timed-out id must not poison early stash.
        gate.finish(taskId: 10, result: .success(late))
        let got = try await gate.wait(
            taskId: 10,
            timeoutNanoseconds: 1_000_000_000,
            timedOutError: UploadManagerError.timedOut
        )
        #expect(got.statusCode == 204)
    }

    @Test func successfulFinishCancelsTimeoutSoTaskIdCanBeReused() async throws {
        let gate = PatchCompletionGate()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!
        let first = Task {
            try await gate.wait(
                taskId: 11,
                timeoutNanoseconds: 200_000_000,
                timedOutError: UploadManagerError.timedOut,
                beforeWaiting: {
                    Task { @MainActor in
                        gate.finish(taskId: 11, result: .success(response))
                    }
                }
            )
        }
        let got = try await first.value
        #expect(got.statusCode == 204)
        // After the short timeout window, a reused task id must still accept finish.
        try await Task.sleep(nanoseconds: 250_000_000)
        gate.finish(taskId: 11, result: .success(response))
        let reused = try await gate.wait(
            taskId: 11,
            timeoutNanoseconds: 1_000_000_000,
            timedOutError: UploadManagerError.timedOut
        )
        #expect(reused.statusCode == 204)
    }

    @Test func finishBeforeTimeoutPreventsLateTimeoutResume() async throws {
        let gate = PatchCompletionGate()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!
        let waitTask = Task {
            try await gate.wait(
                taskId: 12,
                timeoutNanoseconds: 200_000_000,
                timedOutError: UploadManagerError.timedOut,
                beforeWaiting: {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 20_000_000)
                        gate.finish(taskId: 12, result: .success(response))
                    }
                }
            )
        }
        let got = try await waitTask.value
        #expect(got.statusCode == 204)
        try await Task.sleep(nanoseconds: 250_000_000)
        gate.finish(taskId: 12, result: .success(response))
        let reused = try await gate.wait(
            taskId: 12,
            timeoutNanoseconds: 1_000_000_000,
            timedOutError: UploadManagerError.timedOut
        )
        #expect(reused.statusCode == 204)
    }

    @Test func waitHonoursTaskCancellation() async {
        let gate = PatchCompletionGate()
        let waitTask = Task { @MainActor in
            try await gate.wait(
                taskId: 14,
                timeoutNanoseconds: 5_000_000_000,
                timedOutError: UploadManagerError.timedOut
            )
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        waitTask.cancel()
        do {
            _ = try await waitTask.value
            Issue.record("expected cancellation")
        } catch is CancellationError {
            // expected
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func newWaitAfterTimeoutAcceptsFinishOnceTimedOutStateCleared() async throws {
        let gate = PatchCompletionGate()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!
        do {
            _ = try await gate.wait(
                taskId: 13,
                timeoutNanoseconds: 30_000_000,
                timedOutError: UploadManagerError.timedOut
            )
            Issue.record("expected timeout")
        } catch is UploadManagerError {
            // expected
        }
        let waitTask = Task { @MainActor in
            try await gate.wait(
                taskId: 13,
                timeoutNanoseconds: 1_000_000_000,
                timedOutError: UploadManagerError.timedOut
            )
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        gate.finish(taskId: 13, result: .success(response))
        let reused = try await waitTask.value
        #expect(reused.statusCode == 204)
    }
}

struct UploadResumeStoreTests {
    @Test func roundTripsAndRemovesBySermonId() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UploadResumeStore(defaults: defaults, key: "test.records")

        let id = UUID()
        let record = UploadResumeRecord(
            sermonLocalId: id,
            objectPath: "user/\(id.uuidString.lowercased()).m4a",
            uploadURL: URL(string: "https://example.com/upload/1"),
            uploadLength: 100,
            filePath: "/tmp/a.m4a",
            fileModificationTime: 1_700_000_000,
            taskIdentifier: 7,
            startedUnderFlag: true,
            upsert: true
        )
        store.save(record)
        #expect(store.record(for: id) == record)

        store.remove(sermonLocalId: id)
        #expect(store.record(for: id) == nil)
    }

    @Test func matchesLocalFileRequiresPathLengthAndMtime() throws {
        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("tus-match-\(UUID().uuidString).m4a")
        try Data("abc".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let mtime = values.contentModificationDate!.timeIntervalSince1970
        let length = Int64(values.fileSize!)

        let matching = UploadResumeRecord(
            sermonLocalId: UUID(),
            objectPath: "user/x.m4a",
            uploadURL: nil,
            uploadLength: length,
            filePath: file.path,
            fileModificationTime: mtime,
            taskIdentifier: nil,
            startedUnderFlag: true,
            upsert: true
        )
        #expect(matching.matchesLocalFile(file, length: length))

        var wrongLength = matching
        wrongLength.uploadLength = length + 1
        #expect(!wrongLength.matchesLocalFile(file, length: length))

        var missingMtime = matching
        missingMtime.fileModificationTime = nil
        #expect(!missingMtime.matchesLocalFile(file, length: length))

        var wrongPath = matching
        wrongPath.filePath = file.path + ".other"
        #expect(!wrongPath.matchesLocalFile(file, length: length))
    }
}

@MainActor
struct ResumableUploadsFlagTests {
    @Test func resumableUploadsDefaultsOff() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let flags = FeatureFlags(defaults: defaults)
        #expect(flags.resumableUploads == false)
    }
}
