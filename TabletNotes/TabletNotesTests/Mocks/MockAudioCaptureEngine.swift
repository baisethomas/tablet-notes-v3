import Foundation
@testable import TabletNotes

/// Mock for the `AudioCapturing` seam so `RecordingService` (the facade) is
/// testable without AVFoundation hardware — including restart failures,
/// interruptions, and finalization.
final class MockAudioCaptureEngine: AudioCapturing, @unchecked Sendable {
    private let lock = NSLock()

    var state: AudioCaptureEngine.State = .idle
    var onEvent: ((AudioCaptureEngine.Event) -> Void)?

    var stubbedDuration: TimeInterval = 0
    var startError: Error?
    var resumeError: Error?
    var stubbedFileName = "sermon_mock.m4a"

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var resumeCallCount = 0
    private(set) var finalizeCallCount = 0
    private(set) var lastStartedURL: URL?

    var recordedDuration: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return stubbedDuration
    }

    func start() throws -> AudioCaptureEngine.StartedCapture {
        lock.lock(); defer { lock.unlock() }
        startCallCount += 1
        if let startError { throw startError }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(stubbedFileName)
        lastStartedURL = url
        state = .recording
        return AudioCaptureEngine.StartedCapture(url: url, fileName: stubbedFileName)
    }

    func pause() {
        lock.lock(); defer { lock.unlock() }
        pauseCallCount += 1
        state = .paused
    }

    func resume() throws {
        lock.lock(); defer { lock.unlock() }
        resumeCallCount += 1
        if let resumeError { throw resumeError }
        state = .recording
    }

    @discardableResult
    func stop() -> URL? {
        lock.lock(); defer { lock.unlock() }
        stopCallCount += 1
        let url = state == .idle ? nil : lastStartedURL
        state = .idle
        return url
    }

    func finalizeForTermination() {
        lock.lock(); defer { lock.unlock() }
        finalizeCallCount += 1
        state = .idle
    }

    func makeCaptionStream() -> AsyncStream<AudioChunk> {
        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self)
        continuation.finish()
        return stream
    }

    /// Test driver: simulate an engine event (interruption, failed restart).
    func emit(_ event: AudioCaptureEngine.Event) {
        onEvent?(event)
    }
}
