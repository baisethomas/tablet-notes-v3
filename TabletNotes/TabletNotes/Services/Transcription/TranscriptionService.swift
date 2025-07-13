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

    func startTranscription() throws {
        fullTranscript = ""
        lastPartial = ""
        
        let provider = settingsService.transcriptionProvider
        
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
                print("[TranscriptionService] Transcription error: \(error)")
                if !self.isRestarting {
                    self.stopTranscription()
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
        
        let provider = settingsService.transcriptionProvider
        
        switch provider {
        case .assemblyAILive:
            assemblyAILiveService.stopLiveTranscription()
        case .appleSpeech, .assemblyAI:
            stopAppleSpeechSession(clean: false)
            // Append the last partial to the full transcript for Apple Speech
            if !lastPartial.isEmpty {
                if fullTranscript.isEmpty {
                    fullTranscript = lastPartial
                } else {
                    fullTranscript += " " + lastPartial
                }
            }
            transcriptSubject.send(fullTranscript)
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
