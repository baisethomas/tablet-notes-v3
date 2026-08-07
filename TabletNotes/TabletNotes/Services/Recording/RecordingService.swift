import Foundation
import Observation
#if canImport(AVFoundation) && os(iOS)
import AVFoundation
import Combine

/// Recording facade (TAB-71 rewrite). The public surface is unchanged from
/// the AVAudioRecorder-era service — same observable properties, publishers,
/// and methods — but capture now runs on `AudioCaptureEngine`, the single
/// owner of the audio session. This class holds NO audio hardware: it manages
/// subscription limits, the recovery manifest, the duration timer, and the
/// Combine bridge the views consume.
///
/// Deliberately not `@MainActor` (house rule): engine events arrive off-main;
/// UI-facing state updates hop to main explicitly.
@Observable
class RecordingService {
    private let captureEngine: any AudioCapturing
    private var recordingURL: URL?
    var isRecording: Bool = false
    var isPaused: Bool = false
    var recordingDuration: TimeInterval = 0
    var remainingTime: TimeInterval? = nil
    private var cachedMaxDuration: TimeInterval? = nil

    // Publishers (bridged for the views' existing .onReceive wiring)
    let isRecordingPublisher: AnyPublisher<Bool, Never>
    let audioFileURLPublisher: AnyPublisher<URL?, Never>
    let audioFileNamePublisher: AnyPublisher<String?, Never>
    let isPausedPublisher: AnyPublisher<Bool, Never>
    /// Deliberately a PassthroughSubject (no replay): MainAppView is the sole
    /// auto-stop save owner *because* late subscribers never see a stale stop
    /// event. A replaying subject here would double-save auto-stops.
    let recordingStoppedPublisher: AnyPublisher<(URL?, Bool), Never>
    private let isRecordingSubject = CurrentValueSubject<Bool, Never>(false)
    private let audioFileURLSubject = CurrentValueSubject<URL?, Never>(nil)
    private let audioFileNameSubject = CurrentValueSubject<String?, Never>(nil)
    private let isPausedSubject = CurrentValueSubject<Bool, Never>(false)
    private let recordingStoppedSubject = PassthroughSubject<(URL?, Bool), Never>()

    private var durationTask: Task<Void, Never>?
    private let authManager: AuthenticationManager
    private var activeRecoverySessionId: String?

    init(
        captureEngine: (any AudioCapturing)? = nil,
        authManager: AuthenticationManager? = nil
    ) {
        self.captureEngine = captureEngine ?? AudioCaptureEngine.shared
        self.authManager = authManager ?? AuthenticationManager.shared
        isRecordingPublisher = isRecordingSubject.eraseToAnyPublisher()
        audioFileURLPublisher = audioFileURLSubject.eraseToAnyPublisher()
        audioFileNamePublisher = audioFileNameSubject.eraseToAnyPublisher()
        isPausedPublisher = isPausedSubject.eraseToAnyPublisher()
        recordingStoppedPublisher = recordingStoppedSubject.eraseToAnyPublisher()

        captureEngine.onEvent = { [weak self] event in
            self?.handleEngineEvent(event)
        }
    }

    deinit {
        durationTask?.cancel()
    }

    // MARK: - Duration Limit Checking

    /// Check if user can start a new recording based on subscription limits
    @MainActor
    func canStartRecording() -> (canStart: Bool, reason: String?) {
        guard let currentUser = authManager.currentUser else {
            return (false, "User not authenticated")
        }

        if !currentUser.canCreateNewRecording() {
            let remaining = currentUser.remainingRecordings() ?? 0
            return (false, "Monthly recording limit reached. \(remaining) recordings remaining this month.")
        }

        return (true, nil)
    }

    /// Get the maximum recording duration for the current user
    @MainActor
    func getMaxRecordingDuration() -> TimeInterval? {
        guard let currentUser = authManager.currentUser,
              let maxMinutes = currentUser.maxRecordingDuration() else {
            return nil // Unlimited
        }
        return TimeInterval(maxMinutes * 60)
    }

    // MARK: - Recording lifecycle

    func startRecording(serviceType: String) async throws {
        let (canStart, reason) = await canStartRecording()
        if !canStart {
            throw RecordingError.limitExceeded(reason: reason ?? "Recording limit exceeded")
        }

        cachedMaxDuration = await getMaxRecordingDuration()

        // Resolve the recovery user id up front (AuthenticationManager is
        // @MainActor). The manifest must be written with no suspension point
        // after capture starts, so every await happens BEFORE start().
        let manager = authManager
        let recordingUserId: UUID? = await MainActor.run {
            manager.currentUser?.id
        }
        let startedAt = Date()

        let started: AudioCaptureEngine.StartedCapture
        do {
            // Synchronous: when this returns the engine is running and the
            // file exists on disk.
            started = try captureEngine.start()
        } catch {
            print("[RecordingService] Capture start failed: \(error)")
            throw RecordingError.recordingFailed
        }

        recordingURL = started.url
        // Synchronous — no await between engine start and this save. An
        // interruption or termination in that gap would otherwise leave an
        // orphaned on-disk recording with no manifest.
        saveRecoveryManifest(
            serviceType: serviceType,
            audioFileName: started.fileName,
            startedAt: startedAt,
            userId: recordingUserId
        )

        recordingDuration = 0
        isRecording = true
        isPaused = false
        isRecordingSubject.send(true)
        isPausedSubject.send(false)
        audioFileURLSubject.send(started.url)
        audioFileNameSubject.send(started.fileName)
        startDurationTask()

        if let maxDuration = cachedMaxDuration {
            print("[RecordingService] Started recording with \(Int(maxDuration / 60)) minute limit")
        } else {
            print("[RecordingService] Started recording with no duration limit")
        }
    }

    func stopRecording() -> URL? {
        // Engine stop is synchronous and finalizes the m4a before returning —
        // callers hand the URL straight to the save/transcribe pipeline.
        let currentURL = captureEngine.stop() ?? recordingURL
        durationTask?.cancel()
        durationTask = nil
        recordingURL = nil

        isRecording = false
        isPaused = false
        isRecordingSubject.send(false)
        isPausedSubject.send(false)

        recordingDuration = 0
        remainingTime = nil
        cachedMaxDuration = nil
        activeRecoverySessionId = nil
        InterruptedRecordingRecoveryStore.clear()

        if let currentURL {
            print("[RecordingService] stopRecording() finalized \(currentURL.lastPathComponent)")
        }
        return currentURL
    }

    func pauseRecording() throws {
        guard isRecording, !isPaused else { return }
        captureEngine.pause()
        isPaused = true
        isPausedSubject.send(true)
    }

    func resumeRecording() throws {
        guard isRecording, isPaused else { return }
        do {
            try captureEngine.resume()
        } catch {
            print("[RecordingService] Failed to resume capture: \(error)")
            throw RecordingError.resumeFailed
        }
        isPaused = false
        isPausedSubject.send(false)
    }

    // MARK: - Recovery manifest

    func prepareRecoverySession(sessionId: String) {
        activeRecoverySessionId = sessionId
    }

    /// Persists the recovery manifest. Synchronous by design — see the call
    /// site in `startRecording` for the invariant.
    private func saveRecoveryManifest(serviceType: String, audioFileName: String, startedAt: Date, userId: UUID?) {
        guard let activeRecoverySessionId else {
            print("[RecordingService] No recovery session ID was set before recording started")
            return
        }

        InterruptedRecordingRecoveryStore.save(
            InterruptedRecordingManifest(
                sessionId: activeRecoverySessionId,
                serviceType: serviceType,
                audioFileName: audioFileName,
                startedAt: startedAt,
                userId: userId
            )
        )
    }

    // MARK: - Engine events

    private func handleEngineEvent(_ event: AudioCaptureEngine.Event) {
        Task { @MainActor in
            switch event {
            case .interruptionBegan:
                guard self.isRecording, !self.isPaused else { return }
                self.isPaused = true
                self.isPausedSubject.send(true)
                print("[RecordingService] Recording paused due to interruption")

            case .interruptionEndedAndResumed:
                guard self.isRecording, self.isPaused else { return }
                self.isPaused = false
                self.isPausedSubject.send(false)
                print("[RecordingService] Recording resumed after interruption")

            case .captureFailed(let url, let reason):
                // Queued-hop guard (PR #36 review round 2): this main-actor
                // task can run AFTER a new recording started. The event is
                // tagged with the failed capture's URL — act only if that is
                // still the capture we're tracking; a stale failure must not
                // stop the new recording or clear its manifest.
                guard let url, url == self.recordingURL else {
                    print("[RecordingService] Ignoring stale capture failure for \(url?.lastPathComponent ?? "unknown file")")
                    return
                }
                print("[RecordingService] Capture failed (\(reason)) — finalizing what was recorded")
                // The engine has already finalized the file. Emit a stop so
                // the auto-stop save owner (MainAppView) persists the partial
                // recording instead of losing it.
                _ = self.stopRecording()
                self.recordingStoppedSubject.send((url, true))
            }
        }
    }

    // MARK: - Duration tracking

    private func startDurationTask() {
        durationTask?.cancel()
        durationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                // Weakly re-resolved each tick: binding self for the loop's
                // remainder would keep the service alive through its own task.
                guard let service = self else { return }
                service.tickDuration()
            }
        }
    }

    @MainActor
    private func tickDuration() {
        guard isRecording else { return }
        // Frame-based: pauses and interruptions don't inflate the duration
        // (the old wall-clock implementation drifted across pauses).
        recordingDuration = captureEngine.recordedDuration

        guard let maxDuration = cachedMaxDuration else {
            remainingTime = nil
            return
        }
        remainingTime = max(0, maxDuration - recordingDuration)

        if recordingDuration >= maxDuration {
            print("[RecordingService] Recording duration limit reached (\(Int(maxDuration / 60)) minutes), auto-stopping")
            let audioURL = stopRecording()
            recordingStoppedSubject.send((audioURL, true))
        }
    }
}
#endif
