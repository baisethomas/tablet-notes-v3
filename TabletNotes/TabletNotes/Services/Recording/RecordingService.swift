import Foundation
#if canImport(AVFoundation) && os(iOS)
import AVFoundation
import Combine
import UIKit

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
        
        // Create audio recordings directory if it doesn't exist
        createAudioRecordingsDirectory()
        
        // Setup app lifecycle notifications for background handling
        setupAppLifecycleObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        // Ensure audio session remains active in background
        if isRecording {
            do {
                try recordingSession.setActive(true)
            } catch {
                print("[RecordingService] Failed to maintain audio session in background: \(error)")
            }
        }
    }
    
    @objc private func appWillEnterForeground() {
        // Reactivate audio session when returning to foreground
        if isRecording {
            do {
                try recordingSession.setActive(true)
            } catch {
                print("[RecordingService] Failed to reactivate audio session: \(error)")
            }
        }
    }
    
    private func createAudioRecordingsDirectory() {
        do {
            let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioPath = documentsPath.appendingPathComponent("AudioRecordings")
            try fileManager.createDirectory(at: audioPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("[RecordingService] Failed to create audio recordings directory: \(error)")
        }
    }
    
    private func getAudioRecordingsDirectory() -> URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("AudioRecordings")
    }

    func startRecording(serviceType: String) throws {
        try recordingSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
        try recordingSession.setActive(true)
        
        // Use permanent storage instead of temporary directory
        let filename = "sermon_\(UUID().uuidString).m4a"
        let url = getAudioRecordingsDirectory().appendingPathComponent(filename)
        
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
    
    // MARK: - File Management
    
    /// Move a temporary audio file to permanent storage
    func moveToPermamentStorage(temporaryURL: URL) -> URL? {
        let filename = "sermon_\(UUID().uuidString).m4a"
        let permanentURL = getAudioRecordingsDirectory().appendingPathComponent(filename)
        
        do {
            // Move file from temporary to permanent location
            try fileManager.moveItem(at: temporaryURL, to: permanentURL)
            print("[RecordingService] Moved audio file to permanent storage: \(permanentURL)")
            return permanentURL
        } catch {
            print("[RecordingService] Failed to move audio file to permanent storage: \(error)")
            return nil
        }
    }
    
    /// Check if an audio file exists at the given URL
    func audioFileExists(at url: URL) -> Bool {
        return fileManager.fileExists(atPath: url.path)
    }
    
    /// Delete an audio file
    func deleteAudioFile(at url: URL) {
        do {
            try fileManager.removeItem(at: url)
            print("[RecordingService] Deleted audio file: \(url)")
        } catch {
            print("[RecordingService] Failed to delete audio file: \(error)")
        }
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
