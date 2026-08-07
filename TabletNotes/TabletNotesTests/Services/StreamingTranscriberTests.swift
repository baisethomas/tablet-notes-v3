import Foundation
import Testing
@testable import TabletNotes

/// Tests for the TAB-71 live-caption engine: connection state machine,
/// transcript accumulation, generation-based staleness (the structural
/// replacement for the old service's seven hand-written identity checks),
/// reconnect behavior, and token decoding.
@MainActor
struct StreamingTranscriberTests {
    // MARK: - Test doubles

    final class MockTokenProvider: LiveSessionTokenProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var _shouldFail = false
        private var _fetchCount = 0

        var fetchCount: Int {
            lock.lock(); defer { lock.unlock() }
            return _fetchCount
        }

        func setShouldFail(_ fail: Bool) {
            lock.lock(); defer { lock.unlock() }
            _shouldFail = fail
        }

        func fetchSessionToken() async throws -> String {
            lock.lock()
            _fetchCount += 1
            let fail = _shouldFail
            lock.unlock()
            if fail {
                throw NSError(domain: "TokenError", code: 403)
            }
            return "test-token"
        }
    }

    final class ScriptedSocket: TranscriberSocket, @unchecked Sendable {
        private let lock = NSLock()
        private var queuedMessages: [URLSessionWebSocketTask.Message] = []
        private var pendingReceives: [CheckedContinuation<URLSessionWebSocketTask.Message, Error>] = []
        private var terminalError: Error?
        private var _sentData: [Data] = []
        private var _cancelled = false

        var sentData: [Data] {
            lock.lock(); defer { lock.unlock() }
            return _sentData
        }

        var cancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return _cancelled
        }

        func resume() {}

        func send(_ data: Data) async throws {
            lock.lock(); defer { lock.unlock() }
            if _cancelled { throw NSError(domain: "SocketCancelled", code: 1) }
            _sentData.append(data)
        }

        func receive() async throws -> URLSessionWebSocketTask.Message {
            lock.lock()
            if let error = terminalError {
                lock.unlock()
                throw error
            }
            if !queuedMessages.isEmpty {
                let message = queuedMessages.removeFirst()
                lock.unlock()
                return message
            }
            return try await withCheckedThrowingContinuation { continuation in
                pendingReceives.append(continuation)
                lock.unlock()
            }
        }

        func cancel() {
            lock.lock()
            _cancelled = true
            let pending = pendingReceives
            pendingReceives = []
            lock.unlock()
            for continuation in pending {
                continuation.resume(throwing: CancellationError())
            }
        }

        // Test drivers

        func deliver(_ json: String) {
            lock.lock()
            if pendingReceives.isEmpty {
                queuedMessages.append(.string(json))
                lock.unlock()
            } else {
                let continuation = pendingReceives.removeFirst()
                lock.unlock()
                continuation.resume(returning: .string(json))
            }
        }

        func failConnection(_ error: Error = NSError(domain: "SocketDropped", code: 57)) {
            lock.lock()
            terminalError = error
            let pending = pendingReceives
            pendingReceives = []
            lock.unlock()
            for continuation in pending {
                continuation.resume(throwing: error)
            }
        }
    }

    final class ScriptedSocketFactory: TranscriberSocketFactory, @unchecked Sendable {
        private let lock = NSLock()
        private var _sockets: [ScriptedSocket] = []

        var sockets: [ScriptedSocket] {
            lock.lock(); defer { lock.unlock() }
            return _sockets
        }

        func makeSocket(url: URL) -> any TranscriberSocket {
            let socket = ScriptedSocket()
            lock.lock()
            _sockets.append(socket)
            lock.unlock()
            return socket
        }
    }

    /// Collects transcript updates for assertion.
    final class UpdateCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var _updates: [String] = []

        var updates: [String] {
            lock.lock(); defer { lock.unlock() }
            return _updates
        }

        func append(_ update: String) {
            lock.lock(); defer { lock.unlock() }
            _updates.append(update)
        }
    }

    // MARK: - Helpers

    private func makeTranscriber(
        tokenProvider: MockTokenProvider = MockTokenProvider()
    ) -> (StreamingTranscriber, ScriptedSocketFactory, MockTokenProvider) {
        let factory = ScriptedSocketFactory()
        let transcriber = StreamingTranscriber(
            tokenProvider: tokenProvider,
            socketFactory: factory,
            reconnectBaseDelay: 0.01,
            maxReconnectDelay: 0.05,
            isNetworkAvailable: { true }
        )
        return (transcriber, factory, tokenProvider)
    }

    private func makeChunkStream() -> (AsyncStream<AudioChunk>, AsyncStream<AudioChunk>.Continuation) {
        AsyncStream.makeStream(of: AudioChunk.self)
    }

    /// Polls until `condition` is true or the timeout elapses.
    @discardableResult
    private func eventually(
        timeout: TimeInterval = 2.0,
        _ condition: @escaping () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return await condition()
    }

    private func beginMessage() -> String {
        #"{"type": "Begin", "id": "session-1"}"#
    }

    private func turnMessage(_ text: String, endOfTurn: Bool) -> String {
        #"{"type": "Turn", "transcript": "\#(text)", "end_of_turn": \#(endOfTurn)}"#
    }

    // MARK: - Tests

    @Test func firstConnectTokenFailureThrowsAndStaysIdle() async throws {
        let tokenProvider = MockTokenProvider()
        tokenProvider.setShouldFail(true)
        let (transcriber, factory, _) = makeTranscriber(tokenProvider: tokenProvider)
        let (chunks, continuation) = makeChunkStream()
        defer { continuation.finish() }

        await #expect(throws: (any Error).self) {
            try await transcriber.start(chunks: chunks, sampleRate: 16000)
        }
        #expect(await transcriber.isActive == false)
        #expect(factory.sockets.isEmpty)
    }

    @Test func beginStartsStreamingAndTurnsAccumulate() async throws {
        let (transcriber, factory, _) = makeTranscriber()
        let (chunks, continuation) = makeChunkStream()
        defer { continuation.finish() }

        let collector = UpdateCollector()
        let updates = await transcriber.transcriptUpdates()
        let collectTask = Task {
            for await update in updates { collector.append(update) }
        }
        defer { collectTask.cancel() }

        try await transcriber.start(chunks: chunks, sampleRate: 16000)
        let socket = factory.sockets[0]

        socket.deliver(beginMessage())
        #expect(await eventually { await transcriber.connectionState == .streaming })

        socket.deliver(turnMessage("grace is", endOfTurn: false))
        #expect(await eventually { collector.updates.contains("grace is") })

        socket.deliver(turnMessage("grace is unearned", endOfTurn: true))
        #expect(await eventually { collector.updates.contains("grace is unearned") })

        // The next turn appends to the finalized transcript.
        socket.deliver(turnMessage("come as you are", endOfTurn: true))
        #expect(await eventually { collector.updates.contains("grace is unearned come as you are") })
    }

    @Test func chunksAreForwardedOnlyWhileStreaming() async throws {
        let (transcriber, factory, _) = makeTranscriber()
        let (chunks, continuation) = makeChunkStream()

        try await transcriber.start(chunks: chunks, sampleRate: 16000)
        let socket = factory.sockets[0]

        // Before Begin: connecting, not streaming — the chunk must be dropped.
        continuation.yield(AudioChunk(data: Data([0x01]), sampleRate: 16000))
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(socket.sentData.isEmpty)

        socket.deliver(beginMessage())
        #expect(await eventually { await transcriber.connectionState == .streaming })

        continuation.yield(AudioChunk(data: Data([0x02]), sampleRate: 16000))
        #expect(await eventually { socket.sentData.contains(Data([0x02])) })
        #expect(!socket.sentData.contains(Data([0x01])))
        continuation.finish()
    }

    @Test func socketFailureReconnectsAndPreservesTranscript() async throws {
        let (transcriber, factory, tokenProvider) = makeTranscriber()
        let (chunks, continuation) = makeChunkStream()
        defer { continuation.finish() }

        let collector = UpdateCollector()
        let updates = await transcriber.transcriptUpdates()
        let collectTask = Task {
            for await update in updates { collector.append(update) }
        }
        defer { collectTask.cancel() }

        try await transcriber.start(chunks: chunks, sampleRate: 16000)
        let firstSocket = factory.sockets[0]
        firstSocket.deliver(beginMessage())
        firstSocket.deliver(turnMessage("part one", endOfTurn: true))
        #expect(await eventually { collector.updates.contains("part one") })

        // Drop the connection: the transcriber degrades, then reconnects with
        // a fresh token on a fresh socket.
        firstSocket.failConnection()
        #expect(await eventually { factory.sockets.count == 2 })
        #expect(tokenProvider.fetchCount == 2)

        let secondSocket = factory.sockets[1]
        secondSocket.deliver(beginMessage())
        #expect(await eventually { await transcriber.connectionState == .streaming })

        // The accumulated transcript survives the reconnect.
        secondSocket.deliver(turnMessage("part two", endOfTurn: true))
        #expect(await eventually { collector.updates.contains("part one part two") })
    }

    @Test func staleSocketMessagesAreIgnoredAfterReconnect() async throws {
        let (transcriber, factory, _) = makeTranscriber()
        let (chunks, continuation) = makeChunkStream()
        defer { continuation.finish() }

        let collector = UpdateCollector()
        let updates = await transcriber.transcriptUpdates()
        let collectTask = Task {
            for await update in updates { collector.append(update) }
        }
        defer { collectTask.cancel() }

        try await transcriber.start(chunks: chunks, sampleRate: 16000)
        let firstSocket = factory.sockets[0]
        firstSocket.deliver(beginMessage())

        // Server-side termination triggers a reconnect (generation bump).
        firstSocket.deliver(#"{"type": "Termination"}"#)
        #expect(await eventually { factory.sockets.count == 2 })
        let secondSocket = factory.sockets[1]
        secondSocket.deliver(beginMessage())
        #expect(await eventually { await transcriber.connectionState == .streaming })

        // A message the OLD socket still delivers is from a stale generation
        // and must not corrupt the live session's transcript.
        firstSocket.deliver(turnMessage("stale ghost text", endOfTurn: true))
        secondSocket.deliver(turnMessage("live text", endOfTurn: true))
        #expect(await eventually { collector.updates.contains("live text") })
        #expect(!collector.updates.contains { $0.contains("stale ghost text") })
    }

    @Test func serverErrorMessageTriggersReconnect() async throws {
        let (transcriber, factory, _) = makeTranscriber()
        let (chunks, continuation) = makeChunkStream()
        defer { continuation.finish() }

        try await transcriber.start(chunks: chunks, sampleRate: 16000)
        let firstSocket = factory.sockets[0]
        firstSocket.deliver(beginMessage())
        #expect(await eventually { await transcriber.connectionState == .streaming })

        // A server-declared error must enter the degraded → reconnect flow,
        // not silently keep feeding a dead session (PR #36 review).
        firstSocket.deliver(#"{"type": "Error", "error": "session exploded"}"#)
        #expect(await eventually { factory.sockets.count == 2 })

        factory.sockets[1].deliver(beginMessage())
        #expect(await eventually { await transcriber.connectionState == .streaming })
    }

    @Test func stopCancelsSocketAndBecomesInactive() async throws {
        let (transcriber, factory, _) = makeTranscriber()
        let (chunks, continuation) = makeChunkStream()
        defer { continuation.finish() }

        try await transcriber.start(chunks: chunks, sampleRate: 16000)
        let socket = factory.sockets[0]
        socket.deliver(beginMessage())
        #expect(await eventually { await transcriber.connectionState == .streaming })

        await transcriber.stop()
        #expect(await transcriber.isActive == false)
        #expect(socket.cancelled)
    }

    @Test func endedChunkStreamStopsTheSession() async throws {
        let (transcriber, factory, _) = makeTranscriber()
        let (chunks, continuation) = makeChunkStream()

        try await transcriber.start(chunks: chunks, sampleRate: 16000)
        factory.sockets[0].deliver(beginMessage())
        #expect(await eventually { await transcriber.connectionState == .streaming })

        // Capture ended: the engine finishes the caption stream, and the
        // caption session must wind down with it.
        continuation.finish()
        #expect(await eventually { await transcriber.isActive == false })
        #expect(factory.sockets[0].cancelled)
    }

    @Test func startIsReentrantWhileActive() async throws {
        let (transcriber, factory, _) = makeTranscriber()
        let (chunks, continuation) = makeChunkStream()
        defer { continuation.finish() }

        try await transcriber.start(chunks: chunks, sampleRate: 16000)
        factory.sockets[0].deliver(beginMessage())
        #expect(await eventually { await transcriber.connectionState == .streaming })

        // RecordingView's .onAppear re-triggers start when returning to an
        // active recording — it must be a no-op, not a second connection.
        let (secondChunks, secondContinuation) = makeChunkStream()
        defer { secondContinuation.finish() }
        try await transcriber.start(chunks: secondChunks, sampleRate: 16000)
        #expect(factory.sockets.count == 1)
    }

    // MARK: - Token decoding

    @Test func decodesEnvelopeTokenResponse() throws {
        let data = Data(#"{"success": true, "data": {"sessionToken": "abc123"}}"#.utf8)
        #expect(try NetlifyLiveSessionTokenProvider.decodeSessionToken(from: data) == "abc123")
    }

    @Test func decodesLegacyTokenResponse() throws {
        let data = Data(#"{"sessionToken": "legacy456"}"#.utf8)
        #expect(try NetlifyLiveSessionTokenProvider.decodeSessionToken(from: data) == "legacy456")
    }

    @Test func rejectsUnrecognizedTokenResponse() {
        let data = Data(#"{"nope": true}"#.utf8)
        #expect(throws: (any Error).self) {
            _ = try NetlifyLiveSessionTokenProvider.decodeSessionToken(from: data)
        }
    }
}
