import Foundation
#if canImport(AVFoundation) && os(iOS)
import AVFoundation
import Combine

class RecordingService: NSObject, ObservableObject {
    private var audioRecorder: AVAudioRecorder?
    private let recordingSession = AVAudioSession.sharedInstance()
    private let fileManager = FileManager.default
    private var recordingURL: URL?
    @Published var isRecording: Bool = false
    @Published var isPaused: Bool = false
    let isRecordingPublisher: AnyPublisher<Bool, Never>
    let audioFileURLPublisher: AnyPublisher<URL?, Never>
    let isPausedPublisher: AnyPublisher<Bool, Never>
    private let isRecordingSubject = CurrentValueSubject<Bool, Never>(false)
    private let audioFileURLSubject = CurrentValueSubject<URL?, Never>(nil)
    private let isPausedSubject = CurrentValueSubject<Bool, Never>(false)

    override init() {
        isRecordingPublisher = isRecordingSubject.eraseToAnyPublisher()
        audioFileURLPublisher = audioFileURLSubject.eraseToAnyPublisher()
        isPausedPublisher = isPausedSubject.eraseToAnyPublisher()
        super.init()
    }

    func startRecording(serviceType: String) throws {
        try recordingSession.setCategory(.playAndRecord, mode: .default)
        try recordingSession.setActive(true)
        let filename = "sermon_\(UUID().uuidString).m4a"
        let url = fileManager.temporaryDirectory.appendingPathComponent(filename)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.record()
        recordingURL = url
        isRecording = true
        isRecordingSubject.send(true)
        audioFileURLSubject.send(url)
    }

    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        isPaused = false
        isRecordingSubject.send(false)
        isPausedSubject.send(false)
    }
    
    func pauseRecording() throws {
        guard isRecording, !isPaused else { return }
        audioRecorder?.pause()
        isPaused = true
        isPausedSubject.send(true)
    }
    
    func resumeRecording() throws {
        guard isRecording, isPaused else { return }
        audioRecorder?.record()
        isPaused = false
        isPausedSubject.send(false)
    }
}

extension RecordingService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        isRecording = false
        isPaused = false
        isRecordingSubject.send(false)
        isPausedSubject.send(false)
        if flag {
            audioFileURLSubject.send(recorder.url)
        } else {
            audioFileURLSubject.send(nil)
        }
    }
}
#endif
