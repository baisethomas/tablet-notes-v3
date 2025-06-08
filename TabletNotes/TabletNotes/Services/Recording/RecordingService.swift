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
    let isRecordingPublisher: AnyPublisher<Bool, Never>
    let audioFileURLPublisher: AnyPublisher<URL?, Never>
    private let isRecordingSubject = CurrentValueSubject<Bool, Never>(false)
    private let audioFileURLSubject = CurrentValueSubject<URL?, Never>(nil)

    override init() {
        isRecordingPublisher = isRecordingSubject.eraseToAnyPublisher()
        audioFileURLPublisher = audioFileURLSubject.eraseToAnyPublisher()
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
        isRecordingSubject.send(false)
    }
}

extension RecordingService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        isRecording = false
        isRecordingSubject.send(false)
        if flag {
            audioFileURLSubject.send(recorder.url)
        } else {
            audioFileURLSubject.send(nil)
        }
    }
}
#endif
