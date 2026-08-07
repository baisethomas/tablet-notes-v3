import Foundation
import Combine
import Testing
@testable import TabletNotes

/// Tests for the TAB-71 `RecordingService` facade over the `AudioCapturing`
/// seam: recovery-manifest semantics, engine-event mapping (including the
/// unrecoverable-restart path that must auto-stop-save the partial
/// recording), and state bookkeeping — all without AVFoundation hardware.
@MainActor
struct RecordingServiceFacadeTests {
    private func makeService() -> (RecordingService, MockAudioCaptureEngine) {
        InterruptedRecordingRecoveryStore.clear()
        let engine = MockAudioCaptureEngine()
        let mockAuthService = MockAuthService()
        mockAuthService.setAuthState(.authenticated(MockAuthService.createMockUser()))
        let authManager = AuthenticationManager(authService: mockAuthService)
        let service = RecordingService(captureEngine: engine, authManager: authManager)
        return (service, engine)
    }

    @discardableResult
    private func eventually(
        timeout: TimeInterval = 2.0,
        _ condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    @Test func startRecordingWritesRecoveryManifest() async throws {
        let (service, engine) = makeService()
        defer { InterruptedRecordingRecoveryStore.clear() }

        service.prepareRecoverySession(sessionId: "session-123")
        try await service.startRecording(serviceType: "Sunday Service")

        #expect(engine.startCallCount == 1)
        #expect(service.isRecording)

        let manifest = InterruptedRecordingRecoveryStore.load()
        #expect(manifest != nil)
        #expect(manifest?.sessionId == "session-123")
        #expect(manifest?.serviceType == "Sunday Service")
        #expect(manifest?.audioFileName == engine.stubbedFileName)
        #expect(manifest?.userId != nil)
    }

    @Test func startWithoutRecoverySessionWritesNoManifest() async throws {
        let (service, _) = makeService()
        defer { InterruptedRecordingRecoveryStore.clear() }

        // prepareRecoverySession deliberately not called.
        try await service.startRecording(serviceType: "Sunday Service")
        #expect(InterruptedRecordingRecoveryStore.load() == nil)
    }

    @Test func stopRecordingClearsManifestAndState() async throws {
        let (service, engine) = makeService()

        service.prepareRecoverySession(sessionId: "session-123")
        try await service.startRecording(serviceType: "Sunday Service")
        #expect(InterruptedRecordingRecoveryStore.load() != nil)

        let url = service.stopRecording()
        #expect(url == engine.lastStartedURL)
        #expect(engine.stopCallCount == 1)
        #expect(!service.isRecording)
        #expect(InterruptedRecordingRecoveryStore.load() == nil)
    }

    @Test func engineFailureAutoStopsAndEmitsStopEvent() async throws {
        let (service, engine) = makeService()
        defer { InterruptedRecordingRecoveryStore.clear() }

        service.prepareRecoverySession(sessionId: "session-123")
        try await service.startRecording(serviceType: "Sunday Service")
        let startedURL = engine.lastStartedURL

        // Collect the auto-stop event MainAppView's save owner listens for.
        final class StopCollector: @unchecked Sendable {
            private let lock = NSLock()
            private var _events: [(URL?, Bool)] = []
            var events: [(URL?, Bool)] {
                lock.lock(); defer { lock.unlock() }
                return _events
            }
            func append(_ event: (URL?, Bool)) {
                lock.lock(); defer { lock.unlock() }
                _events.append(event)
            }
        }
        let collector = StopCollector()
        let cancellable = service.recordingStoppedPublisher.sink { collector.append($0) }
        defer { cancellable.cancel() }

        // The engine reports an unrecoverable failure (foreground restart or
        // configuration change): the facade must auto-stop-save the partial
        // recording, never leave the UI claiming an active recording.
        engine.emit(.interruptionEndedResumeFailed("engine could not restart"))

        #expect(await eventually { collector.events.count == 1 })
        #expect(collector.events.first?.0 == startedURL)
        #expect(collector.events.first?.1 == true)
        #expect(!service.isRecording)
    }

    @Test func interruptionEventsTogglePausedState() async throws {
        let (service, engine) = makeService()
        defer { InterruptedRecordingRecoveryStore.clear() }

        try await service.startRecording(serviceType: "Sunday Service")

        engine.emit(.interruptionBegan)
        #expect(await eventually { service.isPaused })

        engine.emit(.interruptionEndedAndResumed)
        #expect(await eventually { !service.isPaused })
        #expect(service.isRecording)
    }

    @Test func resumeFailureThrowsResumeFailed() async throws {
        let (service, engine) = makeService()
        defer { InterruptedRecordingRecoveryStore.clear() }

        try await service.startRecording(serviceType: "Sunday Service")
        try service.pauseRecording()
        #expect(service.isPaused)

        engine.resumeError = NSError(domain: "Engine", code: 1)
        #expect(throws: (any Error).self) {
            try service.resumeRecording()
        }
        #expect(service.isPaused)
    }
}
