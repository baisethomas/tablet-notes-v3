import Foundation
import Speech
import Combine
import SwiftData
import AVFoundation

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
    
    // Usage stats
    @Published var isRestarting = false
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        setupLiveServiceObserver()
    }
    
    private func setupLiveServiceObserver() {
        // Placeholder for live service observer
        print("[TranscriptionService] Live service observer setup")
    }

    func startLiveTranscription(provider: String = "appleSpeech") {
        switch provider {
        case "assemblyAILive":
            print("[TranscriptionService] AssemblyAI Live transcription is temporarily disabled.")
            // Fallback to Apple Speech
            DispatchQueue.main.async {
                self.startAppleSpeechSession()
            }
        case "appleSpeech", "assemblyAI":
            startAppleSpeechSession()
        default:
            startAppleSpeechSession()
        }
    }

    func stopLiveTranscription(provider: String = "appleSpeech") {
        switch provider {
        case "assemblyAILive":
            print("[TranscriptionService] AssemblyAI Live transcription is temporarily disabled.")
        case "appleSpeech", "assemblyAI":
            stopAppleSpeechSession(clean: false)
        default:
            stopAppleSpeechSession(clean: false)
        }
    }

    private func startAppleSpeechSession() {
        guard speechRecognizer?.isAvailable == true else {
            print("[TranscriptionService] Speech recognizer not available")
            return
        }
        
        // Reset previous session
        fullTranscript = ""
        lastPartial = ""
        sessionStartTime = Date()
        
        // Setup audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[TranscriptionService] Audio session setup failed: \(error)")
            return
        }
        
        // Setup recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handleRecognitionResult(result: result, error: error)
            }
        }
        
        // Setup audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            
            // Setup session timer
            timer = Timer.scheduledTimer(withTimeInterval: sessionLimit, repeats: false) { [weak self] _ in
                self?.restartSession()
            }
            
            print("[TranscriptionService] Apple Speech session started")
        } catch {
            print("[TranscriptionService] Audio engine start failed: \(error)")
        }
    }
    
    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            print("[TranscriptionService] Recognition error: \(error)")
            return
        }
        
        guard let result = result else { return }
        
        let newText = result.bestTranscription.formattedString
        
        if result.isFinal {
            // Final result - add to full transcript
            let newSegment = String(newText.dropFirst(lastPartial.count))
            fullTranscript += newSegment
            lastPartial = ""
            transcriptSubject.send(fullTranscript)
        } else {
            // Partial result - update display
            let currentSegment = String(newText.dropFirst(lastPartial.count))
            let displayText = fullTranscript + currentSegment
            transcriptSubject.send(displayText)
            lastPartial = newText
        }
    }
    
    private func restartSession() {
        isRestarting = true
        stopAppleSpeechSession(clean: false)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startAppleSpeechSession()
            self.isRestarting = false
        }
    }
    
    private func stopAppleSpeechSession(clean: Bool) {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        timer?.invalidate()
        timer = nil
        
        if clean {
            fullTranscript = ""
            lastPartial = ""
            transcriptSubject.send("")
        }
        
        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[TranscriptionService] Failed to deactivate audio session: \(error)")
        }
        
        print("[TranscriptionService] Apple Speech session stopped")
    }
    
    func transcribeAudioFile(url: URL, completion: @escaping (_ text: String?, _ segments: [TranscriptSegment]) -> Void) {
        print("[TranscriptionService] File transcription is temporarily disabled.")
        completion(nil, [])
    }
}
