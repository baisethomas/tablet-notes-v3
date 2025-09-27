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
    @Published var recordingDuration: TimeInterval = 0
    @Published var remainingTime: TimeInterval? = nil
    
    // Publishers
    let isRecordingPublisher: AnyPublisher<Bool, Never>
    let audioFileURLPublisher: AnyPublisher<URL?, Never>
    let audioFileNamePublisher: AnyPublisher<String?, Never>
    let isPausedPublisher: AnyPublisher<Bool, Never>
    let recordingStoppedPublisher: AnyPublisher<(URL?, Bool), Never>
    private let isRecordingSubject = CurrentValueSubject<Bool, Never>(false)
    private let audioFileURLSubject = CurrentValueSubject<URL?, Never>(nil)
    private let audioFileNameSubject = CurrentValueSubject<String?, Never>(nil)
    private let isPausedSubject = CurrentValueSubject<Bool, Never>(false)
    private let recordingStoppedSubject = PassthroughSubject<(URL?, Bool), Never>()
    
    // Duration tracking
    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private let authManager = AuthenticationManager.shared

    override init() {
        isRecordingPublisher = isRecordingSubject.eraseToAnyPublisher()
        audioFileURLPublisher = audioFileURLSubject.eraseToAnyPublisher()
        audioFileNamePublisher = audioFileNameSubject.eraseToAnyPublisher()
        isPausedPublisher = isPausedSubject.eraseToAnyPublisher()
        recordingStoppedPublisher = recordingStoppedSubject.eraseToAnyPublisher()
        super.init()
        
        // Create audio recordings directory if it doesn't exist
        createAudioRecordingsDirectory()
        
        // Setup app lifecycle notifications for background handling
        setupAppLifecycleObservers()
    }
    
    deinit {
        stopDurationTimer()
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
    
    // MARK: - Duration Limit Checking
    
    /// Check if user can start a new recording based on subscription limits
    @MainActor
    func canStartRecording() -> (canStart: Bool, reason: String?) {
        guard let currentUser = authManager.currentUser else {
            return (false, "User not authenticated")
        }
        
        // Check if user can create new recordings (monthly limit)
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
        return TimeInterval(maxMinutes * 60) // Convert to seconds
    }
    
    /// Check if current recording duration exceeds limit
    private func checkDurationLimit() {
        Task { @MainActor in
            guard let maxDuration = getMaxRecordingDuration() else {
                // No limit, update remaining time to nil
                remainingTime = nil
                return
            }
            
            let remaining = maxDuration - recordingDuration
            remainingTime = max(0, remaining)
            
            // Auto-stop if limit reached
            if recordingDuration >= maxDuration {
                print("[RecordingService] Recording duration limit reached (\(Int(maxDuration/60)) minutes), auto-stopping")
                let audioURL = stopRecording()
                // Emit auto-stop event with the audio URL and auto-stop flag
                recordingStoppedSubject.send((audioURL, true))
            }
        }
    }

    func startRecording(serviceType: String) async throws {
        // Check if user can start recording
        let (canStart, reason) = await canStartRecording()
        if !canStart {
            throw RecordingError.limitExceeded(reason ?? "Recording limit exceeded")
        }
        
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
        
        // Start duration tracking
        Task { @MainActor in
            recordingDuration = 0
            recordingStartTime = Date()
        }
        startDurationTimer()
        
        Task { @MainActor in
            isRecording = true
        }
        isRecordingSubject.send(true)
        audioFileURLSubject.send(url)
        audioFileNameSubject.send(filename)
        
        // Log the duration limit for this recording
        Task { @MainActor in
            if let maxDuration = getMaxRecordingDuration() {
                let maxMinutes = Int(maxDuration / 60)
                print("[RecordingService] Started recording with \(maxMinutes) minute limit")
            } else {
                print("[RecordingService] Started recording with no duration limit")
            }
        }
    }

    func stopRecording() -> URL? {
        let currentURL = recordingURL
        audioRecorder?.stop()
        stopDurationTimer()

        Task { @MainActor in
            isRecording = false
            isPaused = false
        }
        isRecordingSubject.send(false)
        isPausedSubject.send(false)

        // Reset duration tracking
        Task { @MainActor in
            recordingDuration = 0
            remainingTime = nil
        }
        recordingStartTime = nil

        return currentURL
    }
    
    func pauseRecording() throws {
        guard isRecording, !isPaused else { return }
        audioRecorder?.pause()
        stopDurationTimer()
        Task { @MainActor in
            isPaused = true
        }
        isPausedSubject.send(true)
    }
    
    func resumeRecording() throws {
        guard isRecording, isPaused else { return }
        audioRecorder?.record()
        startDurationTimer()
        Task { @MainActor in
            isPaused = false
        }
        isPausedSubject.send(false)
    }
    
    // MARK: - Duration Timer Management
    
    private func startDurationTimer() {
        // Ensure timer is created on main thread for proper scheduling
        DispatchQueue.main.async { [weak self] in
            self?.stopDurationTimer() // Ensure no duplicate timers

            print("[RecordingService] Starting duration timer on main thread")
            self?.durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.updateDuration()
            }
        }
    }
    
    private func stopDurationTimer() {
        // Ensure timer is stopped on main thread
        if Thread.isMainThread {
            durationTimer?.invalidate()
            durationTimer = nil
        } else {
            DispatchQueue.main.sync {
                durationTimer?.invalidate()
                durationTimer = nil
            }
        }
    }
    
    private func updateDuration() {
        guard let startTime = recordingStartTime else {
            print("[RecordingService] updateDuration: No start time set")
            return
        }

        let currentDuration = Date().timeIntervalSince(startTime)
        print("[RecordingService] updateDuration: \(String(format: "%.1f", currentDuration))s")

        Task { @MainActor in
            recordingDuration = currentDuration
        }
        checkDurationLimit()
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

// MARK: - Recording Errors
enum RecordingError: LocalizedError {
    case limitExceeded(String)
    case permissionDenied
    case audioSessionFailed
    case recordingFailed
    
    var errorDescription: String? {
        switch self {
        case .limitExceeded(let reason):
            return reason
        case .permissionDenied:
            return "Microphone permission denied"
        case .audioSessionFailed:
            return "Failed to setup audio session"
        case .recordingFailed:
            return "Recording failed"
        }
    }
}

extension RecordingService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            isRecording = false
            isPaused = false
        }
        isRecordingSubject.send(false)
        isPausedSubject.send(false)
        if flag {
            audioFileURLSubject.send(recorder.url)
            audioFileNameSubject.send(recorder.url.lastPathComponent)
        } else {
            audioFileURLSubject.send(nil)
            audioFileNameSubject.send(nil)
        }
    }
}
#endif
