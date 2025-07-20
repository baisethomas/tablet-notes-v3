import Foundation
import Speech
import Combine
import SwiftData


class TranscriptionService: NSObject, ObservableObject {
    // Apple Speech Recognition properties
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var fullTranscript: String = ""
    private let transcriptSubject = CurrentValueSubject<String, Never>("")
    var transcriptPublisher: AnyPublisher<String, Never> { transcriptSubject.eraseToAnyPublisher() }
    private var timer: Timer?
    private let sessionLimit: TimeInterval = 59 // seconds
    private var sessionStartTime: Date?
    private var lastPartial: String = ""
    private var isRestarting = false

    // Service instances
    private let assemblyAITranscriptionService = AssemblyAITranscriptionService()
    private let assemblyAILiveService = AssemblyAILiveTranscriptionService()
    private let settingsService = SettingsService.shared
    private let authManager = AuthenticationManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        setupLiveServiceObserver()
    }
    
    private func setupLiveServiceObserver() {
        // Forward live service transcripts to our main publisher
        assemblyAILiveService.transcriptPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcript in
                self?.transcriptSubject.send(transcript)
            }
            .store(in: &cancellables)
    }
    
    /// Gets the effective transcription provider from SettingsService
    private func getEffectiveTranscriptionProvider() -> TranscriptionProvider {
        let effectiveProvider = settingsService.effectiveTranscriptionProvider
        let requestedProvider = settingsService.transcriptionProvider
        
        if let currentUser = authManager.currentUser {
            print("[TranscriptionService] User subscription tier: \(currentUser.subscriptionTier)")
            print("[TranscriptionService] Has priority transcription: \(currentUser.canUsePriorityTranscription)")
        }
        print("[TranscriptionService] Requested provider: \(requestedProvider.rawValue)")
        print("[TranscriptionService] Effective provider: \(effectiveProvider.rawValue)")
        
        if effectiveProvider != requestedProvider {
            print("[TranscriptionService] Provider downgraded due to subscription tier limitations")
        }
        
        return effectiveProvider
    }

    func startTranscription() throws {
        fullTranscript = ""
        lastPartial = ""
        
        let provider = getEffectiveTranscriptionProvider()
        print("[TranscriptionService] Using transcription provider: \(provider.rawValue)")
        
        switch provider {
        case .assemblyAILive:
            Task {
                do {
                    try await assemblyAILiveService.startLiveTranscription()
                } catch {
                    print("[TranscriptionService] Failed to start AssemblyAI Live: \(error)")
                    // Fallback to Apple Speech if AssemblyAI Live fails
                    DispatchQueue.main.async {
                        do {
                            try self.startAppleSpeechSession()
                        } catch {
                            print("[TranscriptionService] Fallback to Apple Speech also failed: \(error)")
                        }
                    }
                }
            }
        case .appleSpeech:
            try startAppleSpeechSession()
        case .assemblyAI:
            // AssemblyAI provider uses post-recording transcription only
            // Fall back to Apple Speech for live transcription
            try startAppleSpeechSession()
        }
    }

    private func startAppleSpeechSession() throws {
        guard !audioEngine.isRunning else { return }
        print("[TranscriptionService] Starting new session...")
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { throw NSError(domain: "Transcription", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create request"]) }
        let inputNode = audioEngine.inputNode
        recognitionRequest.shouldReportPartialResults = true
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                self.lastPartial = result.bestTranscription.formattedString
                self.transcriptSubject.send(self.fullTranscript + (self.lastPartial.isEmpty ? "" : (self.fullTranscript.isEmpty ? "" : " ") + self.lastPartial))
            }
            if let error = error {
                // Check if this is just a cancellation (which is expected when stopping)
                if (error as NSError).code == 301 { // kLSRErrorDomain Code=301 is cancellation
                    print("[TranscriptionService] Transcription task was canceled (expected)")
                } else {
                    print("[TranscriptionService] Transcription error: \(error)")
                    if !self.isRestarting {
                        self.stopTranscription()
                    }
                }
            }
        }
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, _) in
            self.recognitionRequest?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        sessionStartTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: sessionLimit, repeats: false) { [weak self] _ in
            self?.restartSession()
        }
    }

    private func restartSession() {
        print("[TranscriptionService] Restarting session...")
        guard audioEngine.isRunning else {
            print("[TranscriptionService] Audio engine not running, aborting restart.")
            return
        }
        isRestarting = true
        // Append the last partial to the full transcript
        if !lastPartial.isEmpty {
            if fullTranscript.isEmpty {
                fullTranscript = lastPartial
            } else {
                fullTranscript += " " + lastPartial
            }
        }
        lastPartial = ""
        stopAppleSpeechSession(clean: true)
        // Wait a short delay before starting a new session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            do {
                print("[TranscriptionService] Attempting to start new session after restart...")
                try self.startAppleSpeechSession()
            } catch {
                print("[TranscriptionService] Failed to restart transcription session: \(error)")
            }
            self.isRestarting = false
        }
    }

    func stopTranscription() {
        print("[TranscriptionService] Stopping transcription...")
        
        let provider = getEffectiveTranscriptionProvider()
        
        switch provider {
        case .assemblyAILive:
            assemblyAILiveService.stopLiveTranscription()
        case .appleSpeech, .assemblyAI:
            stopAppleSpeechSessionGracefully()
        }
    }
    
    private func stopAppleSpeechSessionGracefully() {
        print("[TranscriptionService] Gracefully stopping Apple Speech session...")
        
        // First, stop the audio engine and timer
        timer?.invalidate()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        
        // Signal end of audio to allow final processing
        recognitionRequest?.endAudio()
        
        // Give the recognition task a moment to process final results
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            // Append the last partial to the full transcript
            if !self.lastPartial.isEmpty {
                if self.fullTranscript.isEmpty {
                    self.fullTranscript = self.lastPartial
                } else {
                    self.fullTranscript += " " + self.lastPartial
                }
            }
            
            // Send the final transcript
            self.transcriptSubject.send(self.fullTranscript)
            
            // Clean up recognition task
            self.recognitionTask?.cancel()
            self.recognitionRequest = nil
            self.recognitionTask = nil
            
            print("[TranscriptionService] Apple Speech session stopped gracefully")
        }
    }

    private func stopAppleSpeechSession(clean: Bool = false) {
        print("[TranscriptionService] Stopping session...")
        timer?.invalidate()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        if clean {
            // Give the system a moment to release resources
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    // Post-recording transcription from file
    func transcribeAudioFile(url: URL, completion: @escaping (_ text: String?, _ segments: [TranscriptSegment]) -> Void) {
        // Use AssemblyAI service for file transcription
        assemblyAITranscriptionService.transcribeAudioFile(url: url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (text, segments)):
                    completion(text, segments)
                case .failure(let error):
                    print("[TranscriptionService] Netlify transcription error: \(error.localizedDescription)")
                    completion(nil, [])
                }
            }
        }
    }
}
