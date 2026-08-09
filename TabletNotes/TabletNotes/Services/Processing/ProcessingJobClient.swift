import Foundation

/// A server-side `processing_jobs` row (TAB-72).
struct RemoteProcessingJob: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case transcription
        case summary
    }

    /// Mirrors the table's CHECK constraint. `dead` is terminal-after-retries:
    /// the pipeline gave up, and the UI must say so rather than spin forever.
    enum Status: String, Codable, Sendable {
        case queued
        case submitted
        case running
        case done
        case failed
        case dead

        var isTerminal: Bool {
            switch self {
            case .done, .dead, .failed: return true
            case .queued, .submitted, .running: return false
            }
        }
    }

    let id: String
    let sermonLocalId: UUID
    let kind: Kind
    let status: Status
    let lastError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sermonLocalId = "sermon_local_id"
        case kind
        case status
        case lastError = "last_error"
    }
}

enum ProcessingJobClientError: LocalizedError, Equatable {
    case notAuthenticated
    case offline
    case requestFailed(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You need to be signed in to process recordings."
        case .offline:
            return "You're offline. Processing will start automatically when you reconnect."
        case .requestFailed(let status, _):
            return "Could not start processing (HTTP \(status)). It will be retried automatically."
        }
    }
}

protocol ProcessingJobRequesting: Sendable {
    /// Registers server-side work for a sermon. Idempotent: calling twice for
    /// the same sermon returns the same job rather than billing a second
    /// provider transcription.
    ///
    /// `filePath` is optional and normally omitted: the server resolves the
    /// audio location from the sermon row it wrote itself. Only the caller that
    /// just performed the upload has a reason to pass one.
    func requestTranscription(sermonLocalId: UUID, filePath: String?) async throws -> RemoteProcessingJob
}

/// Thin client for `POST /api/jobs`.
///
/// The client's only job in the v2 pipeline is to *request* work and *observe*
/// results — it never supervises. Once this returns, the device can be killed
/// with no consequence: the job is durable in Postgres and completion arrives
/// via the AssemblyAI webhook and Supabase Realtime.
struct ProcessingJobClient: ProcessingJobRequesting {
    private let baseURL: URL
    private let tokenProvider: @Sendable () async throws -> String
    private let isNetworkAvailable: @Sendable () -> Bool
    /// Injected so tests can drive a stubbed `URLProtocol`. `URLSession.shared`
    /// ignores `URLProtocol.registerClass`, so a stub is only reachable through
    /// a session whose configuration lists it.
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://comfy-daffodil-7ecc55.netlify.app")!,
        isNetworkAvailable: @escaping @Sendable () -> Bool = { NetworkMonitor.shared.isConnected },
        session: URLSession = .shared,
        tokenProvider: (@Sendable () async throws -> String)? = nil
    ) {
        self.baseURL = baseURL
        self.isNetworkAvailable = isNetworkAvailable
        self.session = session
        self.tokenProvider = tokenProvider ?? {
            do {
                return try await SupabaseService.shared.client.auth.session.accessToken
            } catch {
                let refreshed = try await SupabaseService.shared.client.auth.refreshSession()
                return refreshed.accessToken
            }
        }
    }

    func requestTranscription(sermonLocalId: UUID, filePath: String? = nil) async throws -> RemoteProcessingJob {
        // House rule: check connectivity before starting network-dependent work
        // (a known-offline call would otherwise burn a token refresh and three
        // backoff attempts). Not proof of success — only a cheap early exit.
        guard isNetworkAvailable() else {
            throw ProcessingJobClientError.offline
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/jobs"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let token: String
        do {
            token = try await tokenProvider()
        } catch {
            throw ProcessingJobClientError.notAuthenticated
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "sermonLocalId": sermonLocalId.uuidString,
            "kind": RemoteProcessingJob.Kind.transcription.rawValue
        ]
        if let filePath {
            body["filePath"] = filePath
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await NetworkRetry.withExponentialBackoff(maxAttempts: 3) {
            try await session.data(for: request)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProcessingJobClientError.requestFailed(status: -1, body: "invalid response")
        }
        // 200 = an existing job was reused (idempotent replay); 202 = newly submitted.
        guard http.statusCode == 200 || http.statusCode == 202 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProcessingJobClientError.requestFailed(status: http.statusCode, body: body)
        }

        struct Envelope: Decodable {
            struct Payload: Decodable { let job: RemoteProcessingJob }
            let data: Payload
        }
        return try JSONDecoder().decode(Envelope.self, from: data).data.job
    }
}
