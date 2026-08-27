import Foundation
import Testing
@testable import TabletNotes

/// Scripted TUS server for UploadManager loop tests (TAB-73 review). Each
/// rule answers the next request with a matching HTTP method; the body is
/// ignored (TUS control flow lives in status codes and headers). Injected
/// into BOTH manager sessions via URLSessionConfiguration.protocolClasses,
/// so the real loop runs end to end — including the PATCH path, whose
/// completion arrives through the manager's own URLSession delegate and
/// resolves `patchGate.wait` exactly as in production.
final class TusStubURLProtocol: URLProtocol {
    struct Rule {
        let method: String
        let status: Int
        let headers: [String: String]
    }

    nonisolated(unsafe) private static var script: [Rule] = []
    nonisolated(unsafe) private(set) static var seenMethods: [String] = []
    private static let lock = NSLock()

    static func install(script: [Rule]) {
        lock.lock()
        defer { lock.unlock() }
        Self.script = script
        Self.seenMethods = []
    }

    static func recordedMethods() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return seenMethods
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "?"
        Self.lock.lock()
        Self.seenMethods.append(method)
        let rule: Rule?
        if let index = Self.script.firstIndex(where: { $0.method == method }) {
            rule = Self.script.remove(at: index)
        } else {
            rule = nil
        }
        Self.lock.unlock()

        guard let rule else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://stub.invalid")!,
            statusCode: rule.status,
            httpVersion: "HTTP/1.1",
            headerFields: rule.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// TAB-73 review: the core TUS orchestration (create → head → patch →
/// interpret → completion) was untested. These tests drive the REAL loop —
/// stubbed only at the HTTP boundary — through success, restart, and
/// recovery branches.
@MainActor
struct UploadManagerLoopTests {

    private struct Harness {
        let manager: UploadManager
        let store: UploadResumeStore
        let file: URL
        let fileLength: Int64
        let modificationTime: TimeInterval
        let userId: UUID
        let tokenCalls: () -> Int
        let cleanup: () -> Void
    }

    private func makeHarness(fileBytes: Int = 8) throws -> Harness {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("tus-loop-\(UUID().uuidString).m4a")
        try Data(repeating: 0xAB, count: fileBytes).write(to: file)
        let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: FeatureFlags.Key.resumableUploads.rawValue)
        let store = UploadResumeStore(defaults: defaults, key: "loop-tests")
        let flags = FeatureFlags(defaults: defaults)

        let stubConfiguration = URLSessionConfiguration.ephemeral
        stubConfiguration.protocolClasses = [TusStubURLProtocol.self]
        // The delegate-driven "background" session needs its own configuration
        // instance, also routed through the stub.
        let delegateConfiguration = URLSessionConfiguration.ephemeral
        delegateConfiguration.protocolClasses = [TusStubURLProtocol.self]

        var tokenCallCount = 0
        let userId = UUID()
        let manager = UploadManager(
            projectURL: URL(string: "https://stub.supabase.co")!,
            anonKey: "anon-key",
            resumeStore: store,
            featureFlags: flags,
            tokenProvider: {
                tokenCallCount += 1
                return "token-\(tokenCallCount)"
            },
            currentUserIdProvider: { userId },
            storageObjectDeleter: { _ in },
            createBackgroundSession: true,
            ephemeralSessionConfiguration: stubConfiguration,
            backgroundSessionConfigurationOverride: delegateConfiguration
        )

        return Harness(
            manager: manager,
            store: store,
            file: file,
            fileLength: Int64(values.fileSize!),
            modificationTime: values.contentModificationDate!.timeIntervalSince1970,
            userId: userId,
            tokenCalls: { tokenCallCount },
            cleanup: {
                try? FileManager.default.removeItem(at: file)
                defaults.removePersistentDomain(forName: suite)
            }
        )
    }

    private let uploadURLString = "https://stub.supabase.co/storage/v1/upload/resumable/abc123"

    /// Happy path: CREATE mints the TUS resource, one PATCH carries the whole
    /// file, the delegate completion resolves the gate, and the resume record
    /// is cleared. (Scenario 1 + 5 from the review.)
    @Test func fullUploadSuccessClearsResumeRecord() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        TusStubURLProtocol.install(script: [
            .init(method: "POST", status: 201, headers: ["Location": uploadURLString]),
            .init(method: "PATCH", status: 204, headers: ["Upload-Offset": "\(harness.fileLength)"])
        ])

        try await harness.manager.uploadResumable(
            localFile: harness.file,
            sermonLocalId: UUID(),
            objectPath: "\(harness.userId.uuidString.lowercased())/audio.m4a",
            upsert: true
        )

        #expect(TusStubURLProtocol.recordedMethods() == ["POST", "PATCH"])
        #expect(harness.store.allRecords().isEmpty)
    }

    /// A persisted resume record whose TUS resource is gone: HEAD answers 404,
    /// the record is discarded, and the upload restarts with a fresh CREATE
    /// from byte zero. (Scenario 2.)
    @Test func headGoneRestartsWithFreshCreate() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let sermonId = UUID()
        let objectPath = "\(harness.userId.uuidString.lowercased())/audio.m4a"

        harness.store.save(
            UploadResumeRecord(
                sermonLocalId: sermonId,
                objectPath: objectPath,
                uploadURL: URL(string: uploadURLString)!,
                uploadLength: harness.fileLength,
                filePath: harness.file.path,
                fileModificationTime: harness.modificationTime,
                taskIdentifier: nil,
                ownerUserId: harness.userId,
                startedUnderFlag: true,
                upsert: true
            )
        )

        TusStubURLProtocol.install(script: [
            .init(method: "HEAD", status: 404, headers: [:]),
            .init(method: "POST", status: 201, headers: ["Location": uploadURLString]),
            .init(method: "PATCH", status: 204, headers: ["Upload-Offset": "\(harness.fileLength)"])
        ])

        try await harness.manager.uploadResumable(
            localFile: harness.file,
            sermonLocalId: sermonId,
            objectPath: objectPath,
            upsert: true
        )

        #expect(TusStubURLProtocol.recordedMethods() == ["HEAD", "POST", "PATCH"])
        #expect(harness.store.allRecords().isEmpty)
    }

    /// A PATCH rejected with 401 refreshes the token and recovers the offset
    /// via HEAD instead of abandoning the resource; the next PATCH finishes
    /// the upload. (Scenario 3.)
    @Test func patch401RecoversOffsetViaHead() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        TusStubURLProtocol.install(script: [
            .init(method: "POST", status: 201, headers: ["Location": uploadURLString]),
            .init(method: "PATCH", status: 401, headers: [:]),
            .init(method: "HEAD", status: 200, headers: ["Upload-Offset": "0"]),
            .init(method: "PATCH", status: 204, headers: ["Upload-Offset": "\(harness.fileLength)"])
        ])
        let tokenCallsBefore = harness.tokenCalls()

        try await harness.manager.uploadResumable(
            localFile: harness.file,
            sermonLocalId: UUID(),
            objectPath: "\(harness.userId.uuidString.lowercased())/audio.m4a",
            upsert: true
        )

        #expect(TusStubURLProtocol.recordedMethods() == ["POST", "PATCH", "HEAD", "PATCH"])
        #expect(harness.store.allRecords().isEmpty)
        // The 401 branch explicitly refreshes the token before the HEAD.
        #expect(harness.tokenCalls() > tokenCallsBefore + 2)
    }

    /// A 204 whose Upload-Offset does not match the sent range is a protocol
    /// violation: the upload fails with invalidOffset and the resume record is
    /// KEPT so the next sync resumes rather than restarting. (Scenario 4.)
    @Test func patchOffsetMismatchFailsAndKeepsResumeRecord() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let sermonId = UUID()

        TusStubURLProtocol.install(script: [
            .init(method: "POST", status: 201, headers: ["Location": uploadURLString]),
            .init(method: "PATCH", status: 204, headers: ["Upload-Offset": "3"]) // != fileLength 8
        ])

        await #expect(throws: UploadManagerError.invalidOffset(offset: 3, length: harness.fileLength)) {
            try await harness.manager.uploadResumable(
                localFile: harness.file,
                sermonLocalId: sermonId,
                objectPath: "\(harness.userId.uuidString.lowercased())/audio.m4a",
                upsert: true
            )
        }

        let record = harness.store.record(for: sermonId)
        #expect(record != nil)
        #expect(record?.uploadURL?.absoluteString == uploadURLString)
    }
}
