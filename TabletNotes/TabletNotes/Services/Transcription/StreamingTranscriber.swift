import Foundation

// MARK: - Injection seams (protocol + mock per house rule)

/// Fetches a short-lived AssemblyAI session token. Tokens gate CONNECTION
/// establishment only — an established streaming session lives up to the
/// server-configured max session duration regardless of token expiry — so the
/// transcriber fetches a fresh token per connection attempt and never
/// schedules renewals. (The old service misread this contract and tore down a
/// healthy WebSocket every 8 minutes to "renew", dropping captions each time.)
protocol LiveSessionTokenProviding: Sendable {
    func fetchSessionToken() async throws -> String
}

/// Minimal WebSocket seam so the transcriber's state machine is unit-testable
/// without a network.
protocol TranscriberSocket: AnyObject, Sendable {
    func resume()
    func send(_ data: Data) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func cancel()
}

protocol TranscriberSocketFactory: Sendable {
    func makeSocket(url: URL) -> any TranscriberSocket
}

// MARK: - StreamingTranscriber

/// Live-caption engine (TAB-71 rewrite). Consumes `AudioChunk`s from
/// `AudioCaptureEngine`'s caption stream and owns the AssemblyAI v3 WebSocket.
/// It never touches audio hardware: if this actor dies, recording is
/// completely unaffected — and vice versa.
///
/// Staleness is handled structurally with a generation counter: every
/// connection increments `generation`, every connection-scoped task carries
/// the generation it was created under, and all state mutations happen on the
/// actor guarded by a single `generation == current` check. This replaces the
/// seven hand-written stale-WebSocket identity checks the old service needed
/// (its state was mutated from four different execution contexts).
///
/// Reconnection is the normal path, not an emergency: network drops, socket
/// failures, and unexpected session terminations all funnel into the same
/// backoff loop while the state surfaces as `.degraded` — captions can be
/// down and recover while the recording continues untouched.
actor StreamingTranscriber {
    enum ConnectionState: Equatable {
        case idle
        case connecting
        case streaming
        case degraded(reason: String)
    }

    private let tokenProvider: any LiveSessionTokenProviding
    private let socketFactory: any TranscriberSocketFactory
    private let reconnectBaseDelay: TimeInterval
    private let maxReconnectDelay: TimeInterval
    /// Injectable network probe so tests don't depend on NWPathMonitor.
    private let isNetworkAvailable: @Sendable () -> Bool

    private(set) var connectionState: ConnectionState = .idle
    private var generation = 0
    private var socket: (any TranscriberSocket)?
    private var receiveTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var fullTranscript = ""
    private var sampleRate: Double = 16000

    private var updatesContinuation: AsyncStream<String>.Continuation?

    init(
        tokenProvider: any LiveSessionTokenProviding = NetlifyLiveSessionTokenProvider(),
        socketFactory: any TranscriberSocketFactory = URLSessionTranscriberSocketFactory(),
        reconnectBaseDelay: TimeInterval = 1.0,
        maxReconnectDelay: TimeInterval = 30.0,
        isNetworkAvailable: @escaping @Sendable () -> Bool = { NetworkMonitor.shared.isConnected }
    ) {
        self.tokenProvider = tokenProvider
        self.socketFactory = socketFactory
        self.reconnectBaseDelay = reconnectBaseDelay
        self.maxReconnectDelay = maxReconnectDelay
        self.isNetworkAvailable = isNetworkAvailable
    }

    /// Whether a session is live in any form (connecting, streaming, or
    /// degraded-and-reconnecting). Callers use this to make `start` re-entry
    /// a no-op — RecordingView's `.onAppear` legitimately re-triggers starts
    /// when returning to an active recording.
    var isActive: Bool {
        switch connectionState {
        case .idle: return false
        case .connecting, .streaming, .degraded: return true
        }
    }

    /// The transcript feed: emits the full accumulated transcript (finalized
    /// turns plus the current partial) on every update.
    func transcriptUpdates() -> AsyncStream<String> {
        let (stream, continuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(1))
        updatesContinuation?.finish()
        updatesContinuation = continuation
        return stream
    }

    // MARK: - Lifecycle

    /// Starts a caption session over `chunks`. Throws only if the FIRST
    /// connection cannot be established (so the UI can show its "captions
    /// unavailable" banner); after that the session self-heals via reconnect.
    func start(chunks: AsyncStream<AudioChunk>, sampleRate: Double) async throws {
        guard !isActive else { return }

        fullTranscript = ""
        self.sampleRate = sampleRate
        connectionState = .connecting

        do {
            try await connect()
        } catch {
            connectionState = .idle
            throw error
        }

        startSendLoop(chunks: chunks)
    }

    func stop() {
        // Invalidate every connection-scoped task in one move.
        generation += 1
        receiveTask?.cancel()
        receiveTask = nil
        sendTask?.cancel()
        sendTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        socket?.cancel()
        socket = nil
        connectionState = .idle
        updatesContinuation?.finish()
        updatesContinuation = nil
    }

    // MARK: - Connection

    private func connect() async throws {
        generation += 1
        let gen = generation

        // Fresh token per connection attempt; never renewed mid-session.
        let token = try await tokenProvider.fetchSessionToken()

        // The await above is a suspension point: stop() or a newer connect
        // may have run. A stale connect must not install a socket.
        guard gen == generation else { return }

        var components = URLComponents(string: "wss://streaming.assemblyai.com/v3/ws")!
        components.queryItems = [
            URLQueryItem(name: "sample_rate", value: String(Int(sampleRate))),
            URLQueryItem(name: "encoding", value: "pcm_s16le"),
            URLQueryItem(name: "token", value: token)
        ]
        guard let url = components.url else {
            throw NSError(domain: "InvalidWebSocketURL", code: 1)
        }

        socket?.cancel()
        let newSocket = socketFactory.makeSocket(url: url)
        socket = newSocket
        newSocket.resume()
        print("[StreamingTranscriber] Connecting (generation \(gen), \(Int(sampleRate))Hz)")

        startReceiveLoop(on: newSocket, generation: gen)
    }

    private func startReceiveLoop(on socket: any TranscriberSocket, generation gen: Int) {
        receiveTask?.cancel()
        receiveTask = Task {
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    guard await self.handleIfCurrent(message, generation: gen) else { return }
                } catch {
                    await self.handleDisconnect(generation: gen, error: error)
                    return
                }
            }
        }
    }

    /// Returns false when the message belonged to a stale generation (loop exits).
    private func handleIfCurrent(_ message: URLSessionWebSocketTask.Message, generation gen: Int) -> Bool {
        guard gen == generation else { return false }
        handleMessage(message)
        return true
    }

    private func handleDisconnect(generation gen: Int, error: Error) {
        // A failure from a replaced connection must not touch the live one.
        guard gen == generation else { return }
        print("[StreamingTranscriber] Connection lost: \(error.localizedDescription)")
        socket?.cancel()
        socket = nil
        connectionState = .degraded(reason: error.localizedDescription)
        scheduleReconnect(attempt: 1)
    }

    private func scheduleReconnect(attempt: Int) {
        reconnectTask?.cancel()
        let gen = generation
        reconnectTask = Task {
            // Exponential backoff with jitter, capped; wait out network loss.
            let backoff = min(reconnectBaseDelay * pow(2.0, Double(attempt - 1)), maxReconnectDelay)
            let jittered = backoff * Double.random(in: 0.8...1.2)
            try? await Task.sleep(nanoseconds: UInt64(jittered * 1_000_000_000))

            while !Task.isCancelled && !isNetworkAvailable() {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            await self.attemptReconnect(previousGeneration: gen, attempt: attempt)
        }
    }

    private func attemptReconnect(previousGeneration: Int, attempt: Int) async {
        // Only the reconnect armed for the CURRENT generation may proceed —
        // stop() or a completed reconnect bumps the generation.
        guard previousGeneration == generation else { return }
        print("[StreamingTranscriber] Reconnect attempt \(attempt)")
        connectionState = .connecting
        do {
            try await connect()
            // State flips to .streaming when the new session's Begin arrives.
        } catch {
            guard previousGeneration + 1 == generation || previousGeneration == generation else { return }
            print("[StreamingTranscriber] Reconnect attempt \(attempt) failed: \(error.localizedDescription)")
            connectionState = .degraded(reason: error.localizedDescription)
            scheduleReconnect(attempt: attempt + 1)
        }
    }

    // MARK: - Sending

    private func startSendLoop(chunks: AsyncStream<AudioChunk>) {
        sendTask?.cancel()
        sendTask = Task {
            for await chunk in chunks {
                guard !Task.isCancelled else { return }
                await self.forward(chunk)
            }
            // The chunk stream ends when capture stops (or the engine replaced
            // the consumer): the caption session is over.
            await self.handleChunksEnded()
        }
    }

    private func forward(_ chunk: AudioChunk) async {
        guard connectionState == .streaming, let socket else { return }
        do {
            try await socket.send(chunk.data)
        } catch {
            // The receive loop observes the same failure and drives the
            // reconnect; dropping this chunk is fine (captions, not audio).
        }
    }

    private func handleChunksEnded() {
        guard isActive else { return }
        print("[StreamingTranscriber] Audio stream ended — stopping caption session")
        stop()
    }

    // MARK: - Message handling

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message else { return }
        guard let data = text.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "Begin":
            print("[StreamingTranscriber] ✅ Session began")
            connectionState = .streaming

        case "Turn":
            guard let turnText = json["transcript"] as? String, !turnText.isEmpty else { return }
            let isEndOfTurn = json["end_of_turn"] as? Bool ?? false
            if isEndOfTurn {
                fullTranscript = fullTranscript.isEmpty ? turnText : fullTranscript + " " + turnText
                updatesContinuation?.yield(fullTranscript)
            } else {
                let combined = fullTranscript.isEmpty ? turnText : fullTranscript + " " + turnText
                updatesContinuation?.yield(combined)
            }

        case "Termination":
            // Expected only at max session duration or server-side close. The
            // recording may still be running — treat like any other drop and
            // let the reconnect loop start a fresh session.
            print("[StreamingTranscriber] Session terminated by server")
            let gen = generation
            handleDisconnect(generation: gen, error: NSError(
                domain: "StreamingTranscriber",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "session terminated by server"]
            ))

        case "Error":
            // A server-declared error means this session is done for — staying
            // in .streaming would keep feeding a dead session while captions
            // fall silent (PR #36 review). Route through the same degraded →
            // reconnect flow as terminations and socket failures.
            let reason = json["error"] as? String ?? "unknown server error"
            print("[StreamingTranscriber] Server error message: \(reason)")
            let gen = generation
            handleDisconnect(generation: gen, error: NSError(
                domain: "StreamingTranscriber",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: reason]
            ))

        default:
            break
        }
    }
}

// MARK: - Default token provider (Netlify)

/// Fetches a session token from the backend token endpoint, which enforces
/// the paid-tier gate server-side. There is intentionally NO direct-key
/// fallback: a bundled AssemblyAI key would ship in the IPA and bypass the
/// subscription check (TAB-45 / TAB-37).
struct NetlifyLiveSessionTokenProvider: LiveSessionTokenProviding {
    private static let endpoint = URL(string: "https://comfy-daffodil-7ecc55.netlify.app/.netlify/functions/assemblyai-live-token")!

    func fetchSessionToken() async throws -> String {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        // Attach a fresh Supabase bearer token, refreshing if needed.
        do {
            let session = try await SupabaseService.shared.client.auth.session
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        } catch {
            do {
                let refreshed = try await SupabaseService.shared.client.auth.refreshSession()
                request.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")
            } catch {
                throw NSError(
                    domain: "AuthError",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "Authentication required. Please sign in to use live transcription."]
                )
            }
        }

        let (data, response) = try await NetworkRetry.withExponentialBackoff(maxAttempts: 2) {
            try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "InvalidResponse", code: 1)
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw NSError(
                domain: "TokenError",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get session token: \(body)"]
            )
        }

        return try Self.decodeSessionToken(from: data)
    }

    /// Accepts both the standardized envelope ({ data: { sessionToken } })
    /// and the legacy top-level shape ({ sessionToken }) the endpoint mirrors.
    static func decodeSessionToken(from data: Data) throws -> String {
        struct SessionTokenResponse: Codable { let sessionToken: String }
        struct SessionTokenEnvelopeResponse: Codable {
            let success: Bool?
            let data: SessionTokenResponse?
        }

        let decoder = JSONDecoder()
        if let wrapped = try? decoder.decode(SessionTokenEnvelopeResponse.self, from: data),
           let token = wrapped.data?.sessionToken, !token.isEmpty {
            return token
        }
        if let legacy = try? decoder.decode(SessionTokenResponse.self, from: data),
           !legacy.sessionToken.isEmpty {
            return legacy.sessionToken
        }
        throw NSError(
            domain: "TokenDecodeError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to decode session token"]
        )
    }
}

// MARK: - Default socket (URLSession)

final class URLSessionTranscriberSocket: TranscriberSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func resume() {
        task.resume()
    }

    func send(_ data: Data) async throws {
        try await task.send(.data(data))
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await task.receive()
    }

    func cancel() {
        task.cancel(with: .goingAway, reason: nil)
    }
}

struct URLSessionTranscriberSocketFactory: TranscriberSocketFactory {
    func makeSocket(url: URL) -> any TranscriberSocket {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)
        return URLSessionTranscriberSocket(task: session.webSocketTask(with: url))
    }
}
