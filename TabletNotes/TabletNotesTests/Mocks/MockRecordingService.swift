//
//  MockRecordingService.swift
//  TabletNotesTests
//
//  Created by Claude for testing purposes.
//

import Foundation
import AVFoundation
import Combine
@testable import TabletNotes

class MockRecordingService: RecordingServiceProtocol {
    // MARK: - Mock State
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var currentRecordingURL: URL?
    @Published private(set) var currentRecordingFileName: String?
    
    private var shouldFailNextCall = false
    private var mockError: Error?
    private var hasMockPermission = true
    private var recordingTimer: DispatchSourceTimer?
    private let mockRecordingURL = URL(fileURLWithPath: "/tmp/mock-recording.m4a")
    
    // MARK: - Publishers
    var isRecordingPublisher: AnyPublisher<Bool, Never> {
        $isRecording.eraseToAnyPublisher()
    }
    
    var audioFileURLPublisher: AnyPublisher<URL?, Never> {
        $currentRecordingURL.eraseToAnyPublisher()
    }
    
    var audioFileNamePublisher: AnyPublisher<String?, Never> {
        $currentRecordingFileName.eraseToAnyPublisher()
    }
    
    var isPausedPublisher: AnyPublisher<Bool, Never> {
        $isPaused.eraseToAnyPublisher()
    }

    var recordingStoppedPublisher: AnyPublisher<(URL?, Bool), Never> {
        recordingStoppedSubject.eraseToAnyPublisher()
    }

    private let recordingStoppedSubject = PassthroughSubject<(URL?, Bool), Never>()

    var recordingDurationPublisher: AnyPublisher<TimeInterval, Never> {
        $recordingDuration.eraseToAnyPublisher()
    }
    
    // MARK: - Test Configuration
    func setShouldFailNextCall(_ shouldFail: Bool, error: Error? = nil) {
        shouldFailNextCall = shouldFail
        mockError = error ?? RecordingError.recordingFailed
        if let recordingError = mockError as? RecordingError,
           case .permissionDenied = recordingError,
           shouldFail {
            hasMockPermission = false
        }
    }
    
    func resetState() {
        isRecording = false
        isPaused = false
        recordingDuration = 0
        currentRecordingURL = nil
        currentRecordingFileName = nil
        hasMockPermission = true
        stopMockTimer()
    }
    
    // MARK: - RecordingServiceProtocol Implementation
    func startRecording(serviceType: String) throws {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? RecordingError.recordingFailed
        }

        guard hasMockPermission else {
            throw RecordingError.permissionDenied
        }
        
        guard !isRecording else {
            throw RecordingError.recordingFailed
        }
        
        isRecording = true
        isPaused = false
        recordingDuration = 0
        currentRecordingURL = mockRecordingURL
        currentRecordingFileName = mockRecordingURL.lastPathComponent
        
        // Start mock timer to simulate recording duration
        startMockTimer()
    }
    
    func stopRecording() -> URL? {
        let currentURL = currentRecordingURL
        isRecording = false
        isPaused = false
        stopMockTimer()
        currentRecordingURL = nil
        currentRecordingFileName = nil
        recordingStoppedSubject.send((currentURL, false))
        return currentURL
    }
    
    func pauseRecording() throws {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? RecordingError.recordingFailed
        }
        
        guard isRecording && !isPaused else {
            throw RecordingError.recordingFailed
        }
        
        isPaused = true
        stopMockTimer()
    }
    
    func resumeRecording() throws {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? RecordingError.recordingFailed
        }
        
        guard isRecording && isPaused else {
            throw RecordingError.recordingFailed
        }
        
        isPaused = false
        startMockTimer()
    }
    
    func requestPermissions() async throws -> Bool {
        if shouldFailNextCall {
            shouldFailNextCall = false
            if let recordingError = mockError as? RecordingError,
               case .permissionDenied = recordingError {
                hasMockPermission = false
            }
            throw mockError ?? RecordingError.permissionDenied
        }
        
        hasMockPermission = true
        return true // Mock always grants permission
    }
    
    func hasPermission() -> Bool {
        return hasMockPermission && !shouldFailNextCall
    }
    
    func getCurrentRecordingURL() -> URL? {
        return currentRecordingURL
    }
    
    func getRecordingDuration() -> TimeInterval {
        return recordingDuration
    }
    
    // MARK: - Private Helpers
    private func startMockTimer() {
        stopMockTimer()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            self?.recordingDuration += 0.1
        }
        timer.resume()
        recordingTimer = timer
    }

    private func stopMockTimer() {
        recordingTimer?.cancel()
        recordingTimer = nil
    }
}
