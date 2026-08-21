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
            taskIdentifier: 7,
            startedUnderFlag: true,
            upsert: true
        )
        store.save(record)
        #expect(store.record(for: id) == record)

        store.remove(sermonLocalId: id)
        #expect(store.record(for: id) == nil)
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
