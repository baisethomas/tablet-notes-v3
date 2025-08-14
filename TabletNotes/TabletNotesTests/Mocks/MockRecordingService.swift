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
    private var recordingTimer: Timer?
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
    
    var recordingDurationPublisher: AnyPublisher<TimeInterval, Never> {
        $recordingDuration.eraseToAnyPublisher()
    }
    
    // MARK: - Test Configuration
    func setShouldFailNextCall(_ shouldFail: Bool, error: Error? = nil) {
        shouldFailNextCall = shouldFail
        mockError = error ?? RecordingError.recordingFailed
    }
    
    func resetState() {
        isRecording = false
        isPaused = false
        recordingDuration = 0
        currentRecordingURL = nil
        currentRecordingFileName = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    // MARK: - RecordingServiceProtocol Implementation
    func startRecording(serviceType: String) throws {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? RecordingError.recordingFailed
        }
        
        guard !isRecording else {
            throw RecordingError.alreadyRecording
        }
        
        isRecording = true
        isPaused = false
        recordingDuration = 0
        currentRecordingURL = mockRecordingURL
        currentRecordingFileName = mockRecordingURL.lastPathComponent
        
        // Start mock timer to simulate recording duration
        startMockTimer()
    }
    
    func stopRecording() {
        isRecording = false
        isPaused = false
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    func pauseRecording() throws {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? RecordingError.recordingFailed
        }
        
        guard isRecording && !isPaused else {
            throw RecordingError.notRecording
        }
        
        isPaused = true
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    func resumeRecording() throws {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? RecordingError.recordingFailed
        }
        
        guard isRecording && isPaused else {
            throw RecordingError.notRecording
        }
        
        isPaused = false
        startMockTimer()
    }
    
    func requestPermissions() async throws -> Bool {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? RecordingError.permissionDenied
        }
        
        return true // Mock always grants permission
    }
    
    func hasPermission() -> Bool {
        return !shouldFailNextCall // Return false if next call should fail
    }
    
    func getCurrentRecordingURL() -> URL? {
        return currentRecordingURL
    }
    
    func getRecordingDuration() -> TimeInterval {
        return recordingDuration
    }
    
    // MARK: - Private Helpers
    private func startMockTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.recordingDuration += 0.1
        }
    }
}

// MARK: - Recording Errors for Testing
enum RecordingError: LocalizedError {
    case permissionDenied
    case recordingFailed
    case alreadyRecording
    case notRecording
    case fileSystemError
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .recordingFailed:
            return "Recording failed"
        case .alreadyRecording:
            return "Already recording"
        case .notRecording:
            return "Not currently recording"
        case .fileSystemError:
            return "File system error"
        }
    }
}