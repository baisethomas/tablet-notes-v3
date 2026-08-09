import Foundation
import Testing
@testable import TabletNotes

/// Tests for the TAB-72 client pieces: the server-job model's terminal-state
/// semantics and the `POST /api/jobs` client's contract (idempotent replay,
/// auth failure, error mapping) — no network required.
/// `.serialized` because the stubbed `URLProtocol` communicates through static
/// state: the client calls suspend, and parallel cases would otherwise swap
/// each other's `responder`/`lastBody` mid-request.
@MainActor
@Suite(.serialized)
struct ProcessingJobTests {
    // MARK: - Terminal state semantics

    @Test func doneDeadAndFailedAreTerminal() {
        #expect(RemoteProcessingJob.Status.done.isTerminal)
        #expect(RemoteProcessingJob.Status.dead.isTerminal)
        #expect(RemoteProcessingJob.Status.failed.isTerminal)
    }

    @Test func inFlightStatesAreNotTerminal() {
        // The observer only reacts to terminal states; treating 'submitted' as
        // terminal would report a sermon complete while it is still processing.
        #expect(!RemoteProcessingJob.Status.queued.isTerminal)
        #expect(!RemoteProcessingJob.Status.submitted.isTerminal)
        #expect(!RemoteProcessingJob.Status.running.isTerminal)
    }

    // MARK: - Wire decoding

    @Test func decodesServerJobPayload() throws {
        let json = """
        {
          "id": "job-1",
          "sermon_local_id": "11111111-1111-1111-1111-111111111111",
          "kind": "transcription",
          "status": "done",
          "last_error": null
        }
        """
        let job = try JSONDecoder().decode(RemoteProcessingJob.self, from: Data(json.utf8))
        #expect(job.id == "job-1")
        #expect(job.kind == .transcription)
        #expect(job.status == .done)
        #expect(job.sermonLocalId == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(job.lastError == nil)
    }

    @Test func decodesDeadJobWithError() throws {
        let json = """
        {
          "id": "job-2",
          "sermon_local_id": "22222222-2222-2222-2222-222222222222",
          "kind": "summary",
          "status": "dead",
          "last_error": "transcript too short to summarize"
        }
        """
        let job = try JSONDecoder().decode(RemoteProcessingJob.self, from: Data(json.utf8))
        #expect(job.status == .dead)
        #expect(job.kind == .summary)
        #expect(job.lastError == "transcript too short to summarize")
    }

    // MARK: - ProcessingJobClient

    /// Drives ProcessingJobClient against a stubbed URLProtocol so the request
    /// shape and status-code handling are covered without a network.
    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var responder: ((URLRequest) -> (HTTPURLResponse, Data))?
        nonisolated(unsafe) static var lastBody: Data?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            // URLProtocol strips httpBody into a stream; capture it either way.
            if let body = request.httpBody {
                Self.lastBody = body
            } else if let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                let bufferSize = 1024
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { buffer.deallocate(); stream.close() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: bufferSize)
                    if read <= 0 { break }
                    data.append(buffer, count: read)
                }
                Self.lastBody = data
            }

            guard let responder = Self.responder else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            let (response, data) = responder(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    /// A session that actually routes through the stub. `URLSession.shared`
    /// does not consult globally registered protocol classes, so the stub has
    /// to be listed on this configuration.
    private static func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeClient() -> ProcessingJobClient {
        StubURLProtocol.lastBody = nil
        return ProcessingJobClient(
            baseURL: URL(string: "https://example.test")!,
            // NetworkMonitor.shared.isConnected starts false and only flips
            // once NWPathMonitor reports, so the real default would make these
            // cases fail on the offline guard depending on timing.
            isNetworkAvailable: { true },
            session: Self.makeStubSession(),
            tokenProvider: { "test-token" }
        )
    }

    private func envelope(status: String) -> Data {
        Data("""
        {"success": true, "data": {"job": {
            "id": "job-1",
            "sermon_local_id": "11111111-1111-1111-1111-111111111111",
            "kind": "transcription",
            "status": "\(status)",
            "last_error": null
        }, "reused": false}}
        """.utf8)
    }

    @Test func submitsSermonLocalIdAndFilePath() async throws {
        let client = makeClient()
        defer { StubURLProtocol.responder = nil }

        StubURLProtocol.responder = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!,
                self.envelope(status: "submitted")
            )
        }

        let sermonId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let job = try await client.requestTranscription(sermonLocalId: sermonId, filePath: "user-a/audio.m4a")

        #expect(job.status == .submitted)
        let body = try #require(StubURLProtocol.lastBody)
        let parsed = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(parsed["sermonLocalId"] as? String == sermonId.uuidString)
        #expect(parsed["filePath"] as? String == "user-a/audio.m4a")
        #expect(parsed["kind"] as? String == "transcription")
    }

    @Test func treats200AsAnIdempotentReplay() async throws {
        let client = makeClient()
        defer { StubURLProtocol.responder = nil }

        // The server returns 200 (not 202) when an existing job is reused —
        // a client retry after a lost response must succeed, not error.
        StubURLProtocol.responder = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                self.envelope(status: "running")
            )
        }

        let job = try await client.requestTranscription(sermonLocalId: UUID(), filePath: "user-a/audio.m4a")
        #expect(job.status == .running)
    }

    @Test func omitsFilePathWhenTheServerShouldResolveIt() async throws {
        let client = makeClient()
        defer { StubURLProtocol.responder = nil }

        StubURLProtocol.responder = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!,
                self.envelope(status: "queued")
            )
        }

        // The normal call shape after TAB-72 wiring: only the caller that just
        // uploaded knows a path, and it isn't the one asking on a retry.
        _ = try await client.requestTranscription(sermonLocalId: UUID())

        let body = try #require(StubURLProtocol.lastBody)
        let parsed = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(parsed["filePath"] == nil)
        #expect(parsed["sermonLocalId"] as? String != nil)
    }

    @Test func mapsAuthFailureToNotAuthenticated() async {
        let client = ProcessingJobClient(
            baseURL: URL(string: "https://example.test")!,
            // Must be online, or this would pass on `.offline` and prove
            // nothing about the token-failure mapping under test.
            isNetworkAvailable: { true },
            session: Self.makeStubSession(),
            tokenProvider: { throw URLError(.userAuthenticationRequired) }
        )

        await #expect(throws: ProcessingJobClientError.notAuthenticated) {
            _ = try await client.requestTranscription(sermonLocalId: UUID(), filePath: "user-a/audio.m4a")
        }
    }
}
