//
//  RecordingServiceTests.swift
//  TabletNotesTests
//
//  Created by Claude for testing purposes.
//

import Testing
import Foundation
import Combine
@testable import TabletNotes

struct RecordingServiceTests {
    private let mockRecordingService = MockRecordingService()
    
    // MARK: - Setup and Teardown
    private func setupTest() {
        mockRecordingService.resetState()
    }
    
    // MARK: - Permission Tests
    @Test func testRequestPermissionsSuccess() async throws {
        // Given
        setupTest()
        
        // When
        let hasPermission = try await mockRecordingService.requestPermissions()
        
        // Then
        #expect(hasPermission == true)
    }
    
    @Test func testRequestPermissionsFailure() async throws {
        // Given
        setupTest()
        mockRecordingService.setShouldFailNextCall(true, error: RecordingError.permissionDenied)
        
        // When/Then
        await #expect(throws: RecordingError.self) {
            try await mockRecordingService.requestPermissions()
        }
    }
    
    @Test func testHasPermissionWhenGranted() {
        // Given
        setupTest()
        
        // When
        let hasPermission = mockRecordingService.hasPermission()
        
        // Then
        #expect(hasPermission == true)
    }
    
    @Test func testHasPermissionWhenDenied() {
        // Given
        setupTest()
        mockRecordingService.setShouldFailNextCall(true)
        
        // When
        let hasPermission = mockRecordingService.hasPermission()
        
        // Then
        #expect(hasPermission == false)
    }
    
    // MARK: - Recording Start Tests
    @Test func testStartRecordingSuccess() async throws {
        // Given
        setupTest()
        
        // When
        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        let recordingURL = mockRecordingService.getCurrentRecordingURL()
        
        // Then
        #expect(mockRecordingService.isRecording == true)
        #expect(mockRecordingService.isPaused == false)
        #expect(recordingURL?.pathExtension == "m4a")
        #expect(mockRecordingService.getCurrentRecordingURL() == recordingURL)
    }
    
    @Test func testStartRecordingFailure() async throws {
        // Given
        setupTest()
        mockRecordingService.setShouldFailNextCall(true, error: RecordingError.recordingFailed)
        
        // When/Then
        #expect(throws: RecordingError.self) {
            try mockRecordingService.startRecording(serviceType: "Sunday Service")
        }
        
        #expect(mockRecordingService.isRecording == false)
    }
    
    @Test func testStartRecordingWhenAlreadyRecording() async throws {
        // Given
        setupTest()
        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        
        // When/Then
        #expect(throws: RecordingError.self) {
            try mockRecordingService.startRecording(serviceType: "Sunday Service")
        }
    }
    
    // MARK: - Recording Stop Tests
    @Test func testStopRecordingSuccess() async throws {
        // Given
        setupTest()
        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        let startURL = mockRecordingService.getCurrentRecordingURL()
        
        // When
        let stopURL = mockRecordingService.stopRecording()
        
        // Then
        #expect(mockRecordingService.isRecording == false)
        #expect(mockRecordingService.isPaused == false)
        #expect(stopURL == startURL)
        #expect(mockRecordingService.getCurrentRecordingURL() == nil)
    }
    
    @Test func testStopRecordingWhenNotRecording() async throws {
        // Given
        setupTest()
        
        // When
        let recordingURL = mockRecordingService.stopRecording()

        // Then
        #expect(recordingURL == nil)
        #expect(mockRecordingService.isRecording == false)
    }
    
    @Test func testStopRecordingAfterFailureFlagStillReturnsURL() async throws {
        // Given
        setupTest()
        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        mockRecordingService.setShouldFailNextCall(true, error: RecordingError.recordingFailed)
        
        // When
        let recordingURL = mockRecordingService.stopRecording()

        // Then
        #expect(recordingURL != nil)
        #expect(mockRecordingService.isRecording == false)
    }
    
    // MARK: - Recording Pause/Resume Tests
    @Test func testPauseRecordingSuccess() async throws {
        // Given
        setupTest()
        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        
        // When
        try mockRecordingService.pauseRecording()
        
        // Then
        #expect(mockRecordingService.isRecording == true)
        #expect(mockRecordingService.isPaused == true)
    }
    
    @Test func testPauseRecordingWhenNotRecording() async throws {
        // Given
        setupTest()
        
        // When/Then
        #expect(throws: RecordingError.self) {
            try mockRecordingService.pauseRecording()
        }
    }
    
    @Test func testResumeRecordingSuccess() async throws {
        // Given
        setupTest()
        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        try mockRecordingService.pauseRecording()
        
        // When
        try mockRecordingService.resumeRecording()
        
        // Then
        #expect(mockRecordingService.isRecording == true)
        #expect(mockRecordingService.isPaused == false)
    }
    
    @Test func testResumeRecordingWhenNotPaused() async throws {
        // Given
        setupTest()
        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        
        // When/Then
        #expect(throws: RecordingError.self) {
            try mockRecordingService.resumeRecording()
        }
    }
    
    // MARK: - Duration Tests
    @Test func testRecordingDurationUpdates() async throws {
        // Given
        setupTest()
        
        // When
        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        
        // Wait for duration to update
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Then
        let duration = mockRecordingService.getRecordingDuration()
        #expect(duration > 0)
        #expect(duration >= 0.1) // Should be at least 0.1 seconds
    }
    
    @Test func testRecordingDurationPausesOnPause() async throws {
        // Given
        setupTest()
        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        
        // Wait for some duration
        try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
        
        // When
        try mockRecordingService.pauseRecording()
        let pausedDuration = mockRecordingService.getRecordingDuration()
        
        // Wait a bit more
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Then
        let finalDuration = mockRecordingService.getRecordingDuration()
        #expect(finalDuration == pausedDuration) // Duration should not change when paused
    }
    
    // MARK: - Publisher Tests
    @Test func testIsRecordingPublisher() async throws {
        // Given
        setupTest()
        var recordingStates: [Bool] = []
        let cancellable = mockRecordingService.isRecordingPublisher
            .sink { state in
                recordingStates.append(state)
            }
        
        // When
        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        _ = mockRecordingService.stopRecording()
        
        // Allow publishers to emit
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        
        // Then
        #expect(recordingStates.contains(false)) // Initial state
        #expect(recordingStates.contains(true))  // Recording state
        
        cancellable.cancel()
    }
    
    @Test func testIsPausedPublisher() async throws {
        // Given
        setupTest()
        var pausedStates: [Bool] = []
        let cancellable = mockRecordingService.isPausedPublisher
            .sink { state in
                pausedStates.append(state)
            }
        
        // When
        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        try mockRecordingService.pauseRecording()
        try mockRecordingService.resumeRecording()
        
        // Allow publishers to emit
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        
        // Then
        #expect(pausedStates.contains(false)) // Initial and resumed state
        #expect(pausedStates.contains(true))  // Paused state
        
        cancellable.cancel()
    }
    
    // MARK: - State Management Tests
    @Test func testRecordingStateTransitions() async throws {
        // Given
        setupTest()
        
        // Initial state
        #expect(mockRecordingService.isRecording == false)
        #expect(mockRecordingService.isPaused == false)
        #expect(mockRecordingService.getCurrentRecordingURL() == nil)
        
        // Start recording
        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        let recordingURL = mockRecordingService.getCurrentRecordingURL()
        #expect(mockRecordingService.isRecording == true)
        #expect(mockRecordingService.isPaused == false)
        #expect(mockRecordingService.getCurrentRecordingURL() == recordingURL)
        
        // Pause recording
        try mockRecordingService.pauseRecording()
        #expect(mockRecordingService.isRecording == true)
        #expect(mockRecordingService.isPaused == true)
        
        // Resume recording
        try mockRecordingService.resumeRecording()
        #expect(mockRecordingService.isRecording == true)
        #expect(mockRecordingService.isPaused == false)
        
        // Stop recording
        _ = mockRecordingService.stopRecording()
        #expect(mockRecordingService.isRecording == false)
        #expect(mockRecordingService.isPaused == false)
        #expect(mockRecordingService.getCurrentRecordingURL() == nil)
    }
}
