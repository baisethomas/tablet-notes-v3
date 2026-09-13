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
    /// Swift Testing builds a fresh suite instance per test, so each case gets
    /// its own recovery store and never shares the manifest key — see
    /// IsolatedRecoveryStore for why that used to bite.
    private let isolated = IsolatedRecoveryStore()

    private func makeService() -> (RecordingService, MockAudioCaptureEngine) {
        let engine = MockAudioCaptureEngine()
        let mockAuthService = MockAuthService()
        mockAuthService.setAuthState(.authenticated(MockAuthService.createMockUser()))
        let authManager = AuthenticationManager(authService: mockAuthService)
        let service = RecordingService(
            captureEngine: engine,
            authManager: authManager,
            recoveryStore: isolated.store
        )
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

        service.prepareRecoverySession(sessionId: "session-123")
        try await service.startRecording(serviceType: "Sunday Service")

        #expect(engine.startCallCount == 1)
        #expect(service.isRecording)

        let manifest = isolated.store.load()
        #expect(manifest != nil)
        #expect(manifest?.sessionId == "session-123")
        #expect(manifest?.serviceType == "Sunday Service")
        #expect(manifest?.audioFileName == engine.stubbedFileName)
        #expect(manifest?.userId != nil)
    }

    @Test func startWithoutRecoverySessionWritesNoManifest() async throws {
        let (service, _) = makeService()

        // prepareRecoverySession deliberately not called.
        try await service.startRecording(serviceType: "Sunday Service")
        #expect(isolated.store.load() == nil)
    }

    @Test func stopRecordingClearsManifestAndState() async throws {
        let (service, engine) = makeService()

        service.prepareRecoverySession(sessionId: "session-123")
        try await service.startRecording(serviceType: "Sunday Service")
        #expect(isolated.store.load() != nil)

        let url = service.stopRecording()
        #expect(url == engine.lastStartedURL)
        #expect(engine.stopCallCount == 1)
        #expect(!service.isRecording)
        #expect(isolated.store.load() == nil)
    }

    @Test(arguments: [true, false])
    func engineFailureAutoStopsAndEmitsStopEvent(hasManifest: Bool) async throws {
        let (service, engine) = makeService()

        let viewSession = RecordingNoteSession(sessionId: "session-123")
        service.fallbackNoteSessionProvider = { viewSession.sessionId }
        if hasManifest {
            service.prepareRecoverySession(sessionId: "session-123")
        }
        try await service.startRecording(serviceType: "Sunday Service")
        let startedURL = engine.lastStartedURL

        // Collect the auto-stop event MainAppView's save owner listens for.
        final class StopCollector: @unchecked Sendable {
            private let lock = NSLock()
            private var _events: [RecordingService.AutoStoppedRecording] = []
            var events: [RecordingService.AutoStoppedRecording] {
                lock.lock(); defer { lock.unlock() }
                return _events
            }
            func append(_ event: RecordingService.AutoStoppedRecording) {
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
        engine.emit(.captureFailed(url: startedURL, reason: "engine could not restart"))

        #expect(await eventually { collector.events.count == 1 })
        #expect(collector.events.first?.audioURL == startedURL)
        #expect(collector.events.first?.sessionId == "session-123")
        #expect(collector.events.first?.serviceType == "Sunday Service")
        #expect(!service.isRecording)

        // Simulate delivery being held until a later recording has replaced
        // both service state and the view's fallback session.
        let nextSession = viewSession.begin()
        engine.stubbedFileName = "later-sermon.m4a"
        service.prepareRecoverySession(sessionId: nextSession)
        try await service.startRecording(serviceType: "Bible Study")
        _ = service.stopRecording()
        #expect(service.lastRecordingSessionId == nextSession)
        let delivered = try #require(collector.events.first)
        #expect(delivered.audioURL == startedURL)
        #expect(delivered.sessionId == "session-123")
        #expect(delivered.serviceType == "Sunday Service")
    }

    @Test func staleCaptureFailureForAnotherRecordingIsIgnored() async throws {
        let (service, engine) = makeService()

        service.prepareRecoverySession(sessionId: "session-123")
        try await service.startRecording(serviceType: "Sunday Service")

        // A failure event queued for a PREVIOUS capture (different URL) runs
        // after this recording started: it must not stop this recording or
        // clear its manifest (PR #36 review round 2).
        let staleURL = FileManager.default.temporaryDirectory.appendingPathComponent("sermon_previous.m4a")
        engine.emit(.captureFailed(url: staleURL, reason: "stale failure"))

        // Give the main-actor hop time to run, then confirm nothing changed.
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(service.isRecording)
        #expect(isolated.store.load() != nil)
    }

    @Test func interruptionEventsTogglePausedState() async throws {
        let (service, engine) = makeService()

        try await service.startRecording(serviceType: "Sunday Service")
        let url = engine.lastStartedURL

        engine.emit(.interruptionBegan(url: url))
        #expect(await eventually { service.isPaused })

        engine.emit(.interruptionEndedAndResumed(url: url))
        #expect(await eventually { !service.isPaused })
        #expect(service.isRecording)
    }

    @Test func staleInterruptionForAnotherRecordingIsIgnored() async throws {
        let (service, engine) = makeService()

        try await service.startRecording(serviceType: "Sunday Service")

        // An interruption queued for a PREVIOUS capture must not phantom-pause
        // this recording (PR #36 review round 3).
        let staleURL = FileManager.default.temporaryDirectory.appendingPathComponent("sermon_previous.m4a")
        engine.emit(.interruptionBegan(url: staleURL))

        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(!service.isPaused)
        #expect(service.isRecording)
    }

    @Test func resumeFailureThrowsResumeFailed() async throws {
        let (service, engine) = makeService()

        try await service.startRecording(serviceType: "Sunday Service")
        try service.pauseRecording()
        #expect(service.isPaused)

        engine.resumeError = NSError(domain: "Engine", code: 1)
        #expect(throws: (any Error).self) {
            try service.resumeRecording()
        }
        #expect(service.isPaused)
    }

    @Test func liveGuardProtectsFallbackSessionWithoutManifest() {
        let (service, _) = makeService()
        let session = RecordingNoteSession()
        service.fallbackNoteSessionProvider = { session.sessionId }
        let previous = NoteService.liveRecordingSessionProvider
        NoteService.liveRecordingSessionProvider = { service.liveNoteSessionId }
        defer {
            NoteService.liveRecordingSessionProvider = previous
            NoteService.shared(for: session.sessionId).clearSession()
        }
        let notes = session.noteService
        notes.stagePrimaryNoteText("Live fallback note", timestamp: 15)
        #expect(service.liveNoteSessionId == nil)
        service.isRecording = true
        service.isPaused = true
        #expect(service.activeRecoverySessionId == nil)
        #expect(service.liveNoteSessionId == session.sessionId)
        #expect(!notes.clearSession())
        #expect(session.finish(session.sessionId, isRecordingLive: false) == .refusedLiveRecording)
        #expect(notes.currentNotes.first?.text == "Live fallback note")
        #expect(notes.stagePrimaryNoteText("Later keystrokes survive", timestamp: 20))
        service.isRecording = false
        #expect(service.liveNoteSessionId == nil)
        #expect(notes.clearSession())
    }

    // MARK: - lastRecordingSessionId lifecycle (TAB-113 round 4)

    @Test(arguments: [true, false])
    func delayedSaveKeepsStoppedAudioAndNotesAcrossAnotherRecording(hasManifest: Bool) async throws {
        let (service, engine) = makeService()
        let firstSession = UUID().uuidString
        let secondSession = UUID().uuidString
        defer {
            NoteService.shared(for: firstSession).clearSession()
            NoteService.shared(for: secondSession).clearSession()
        }
        NoteService.shared(for: firstSession).stagePrimaryNoteText("First sermon", timestamp: 12)
        NoteService.shared(for: secondSession).stagePrimaryNoteText("Second sermon", timestamp: 24)

        engine.stubbedFileName = "first-sermon.m4a"
        if hasManifest {
            service.prepareRecoverySession(sessionId: firstSession)
        }
        try await service.startRecording(serviceType: "Sunday Service")
        let firstURL = try #require(engine.lastStartedURL)
        // With a manifest, deliberately pass the wrong view id. Without a
        // manifest, the fallback must be captured before the view moves on.
        let stopped = try #require(service.stopRecordingForSave(
            fallbackSessionId: hasManifest ? secondSession : firstSession
        ))

        let (saveGate, releaseSave) = AsyncStream<Void>.makeStream()
        let delayedSave = Task { @MainActor in
            for await _ in saveGate { break }
            let notes = NoteService.shared(for: stopped.sessionId).currentNotes
            return (stopped.audioURL, notes.map(\.text))
        }

        // Hold A's save until B has both reset and replaced the mutable
        // lastRecordingSessionId. No timing sleeps: the gate fixes the order.
        engine.stubbedFileName = "second-sermon.m4a"
        service.prepareRecoverySession(sessionId: secondSession)
        try await service.startRecording(serviceType: "Sunday Service")
        #expect(service.lastRecordingSessionId == nil)
        _ = service.stopRecording()
        #expect(service.lastRecordingSessionId == secondSession)
        releaseSave.yield(())
        releaseSave.finish()

        let (savedURL, savedTexts) = await delayedSave.value
        #expect(stopped.sessionId == firstSession)
        #expect(savedURL == firstURL)
        #expect(savedTexts == ["First sermon"])
    }

    /// The save owners bind a stopped recording's notes to
    /// `lastRecordingSessionId`. It must be exactly the manifest id of the
    /// recording that just stopped — never a previous recording's id
    /// lingering across a start, which would attach another sermon's notes
    /// (or an already-cleared session's empty re-mint) to the new audio.
    @Test func lastRecordingSessionIdIsTheStoppedRecordingsManifestIdAndResetsOnStart() async throws {
        let (service, _) = makeService()
        #expect(service.lastRecordingSessionId == nil)

        service.prepareRecoverySession(sessionId: "session-A")
        try await service.startRecording(serviceType: "Sunday Service")
        #expect(service.lastRecordingSessionId == nil)
        _ = service.stopRecording()
        #expect(service.lastRecordingSessionId == "session-A")

        // Second recording with no manifest session prepared: the stale
        // "session-A" must not survive the start, and the stop must not
        // resurrect it — nil tells the save owner to use the view session.
        try await service.startRecording(serviceType: "Sunday Service")
        #expect(service.lastRecordingSessionId == nil)
        _ = service.stopRecording()
        #expect(service.lastRecordingSessionId == nil)
    }
}
