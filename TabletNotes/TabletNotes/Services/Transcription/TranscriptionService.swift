import Foundation
import Combine
import SwiftData

/// Transcription facade. Live captions run on `StreamingTranscriber`
/// (consuming `AudioCaptureEngine`'s caption stream — this class touches no
/// audio hardware); post-recording file transcription is delegated to
/// `AssemblyAITranscriptionService`. The deprecated Apple Speech path — which
/// owned its own `AVAudioEngine` and was one of the three capture stacks
/// fighting over the audio session — was deleted in the TAB-71 rewrite.
class TranscriptionService: NSObject, ObservableObject {
    private let transcriptSubject = CurrentValueSubject<String, Never>("")
    var transcriptPublisher: AnyPublisher<String, Never> { transcriptSubject.eraseToAnyPublisher() }

    /// User-facing notice shown when live captions can't start. Exposed as a
    /// constant so the view can tell *its* live-caption banner apart from
    /// other transcript notices and clear only that one.
    static let liveCaptionsUnavailableMessage = "Live captions couldn't start. Your recording is still being saved and will be transcribed when you finish."

    /// Set when live transcription startup fails (e.g. the backend token
    /// endpoint denies a free-tier user or is unavailable), cleared on a
    /// successful start. Recording is unaffected — the audio is still saved and
    /// transcribed after recording — so the UI surfaces this as a non-blocking
    /// notice rather than an error.
    @Published var liveStartupError: String?

    // Service instances
    private let assemblyAITranscriptionService = AssemblyAITranscriptionService()
    private let liveTranscriber = StreamingTranscriber()
    private let settingsService = SettingsService.shared
    private let authManager = AuthenticationManager.shared
    private var transcriptForwardingTask: Task<Void, Never>?

    deinit {
        transcriptForwardingTask?.cancel()
    }

    /// Gets the effective transcription provider from SettingsService
    @MainActor
    private func getEffectiveTranscriptionProvider() -> TranscriptionProvider {
        let effectiveProvider = settingsService.effectiveTranscriptionProvider
        print("[TranscriptionService] Auto-selected provider: \(effectiveProvider.rawValue)")
        return effectiveProvider
    }

    func startTranscription() throws {
        Task { @MainActor in
            let provider = getEffectiveTranscriptionProvider()
            print("[TranscriptionService] Using transcription provider: \(provider.rawValue)")
            await self.startLiveCaptions(provider: provider)
        }
    }

    @MainActor
    private func startLiveCaptions(provider: TranscriptionProvider) async {
        switch provider {
        case .assemblyAILive:
            break
        case .appleSpeech:
            print("[TranscriptionService] Apple Speech is deprecated. Using AssemblyAI Live instead.")
        case .assemblyAI:
            print("[TranscriptionService] Regular AssemblyAI doesn't support live transcription. Using AssemblyAI Live instead.")
        }

        // Re-entry is normal: RecordingView's .onAppear restarts captions when
        // returning to an active recording. A live session makes this a no-op —
        // checked BEFORE creating a caption stream, because makeCaptionStream
        // replaces the engine's consumer and would starve the running session.
        guard !(await liveTranscriber.isActive) else {
            print("[TranscriptionService] Live captions already active")
            return
        }

        // Wire the transcript feed before starting so no update is missed.
        let updates = await liveTranscriber.transcriptUpdates()
        transcriptForwardingTask?.cancel()
        transcriptForwardingTask = Task { @MainActor [weak self] in
            for await transcript in updates {
                self?.transcriptSubject.send(transcript)
            }
        }

        // Captions consume the capture engine's chunk stream; they never touch
        // audio hardware. If this fails, recording is unaffected.
        let chunks = AudioCaptureEngine.shared.makeCaptionStream()
        do {
            try await liveTranscriber.start(chunks: chunks, sampleRate: AudioCaptureEngine.captionSampleRate)
            liveStartupError = nil
        } catch {
            print("[TranscriptionService] Failed to start live captions: \(error)")
            liveStartupError = Self.liveCaptionsUnavailableMessage
        }
    }

    func stopTranscription() {
        print("[TranscriptionService] Stopping transcription...")
        transcriptForwardingTask?.cancel()
        transcriptForwardingTask = nil
        Task {
            await liveTranscriber.stop()
        }
    }

    // MARK: - Post-recording transcription from file

    func transcribeAudioFile(url: URL, completion: @escaping (_ text: String?, _ segments: [TranscriptSegment]) -> Void) {
        assemblyAITranscriptionService.transcribeAudioFile(url: url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (text, segments)):
                    completion(text, segments)
                case .failure(let error):
                    print("[TranscriptionService] Transcription error: \(error.localizedDescription)")
                    completion(nil, [])
                }
            }
        }
    }

    // Enhanced version that returns Result for better error handling
    func transcribeAudioFileWithResult(url: URL, completion: @escaping (Result<(String, [TranscriptSegment]), Error>) -> Void) {
        assemblyAITranscriptionService.transcribeAudioFile(url: url, completion: completion)
    }

    func resumeAssemblyAITranscription(
        jobId: String,
        audioURL: URL,
        completion: @escaping (Result<(String, [TranscriptSegment]), Error>) -> Void
    ) {
        assemblyAITranscriptionService.resumePollingTranscription(jobId: jobId, audioURL: audioURL, completion: completion)
    }
}
