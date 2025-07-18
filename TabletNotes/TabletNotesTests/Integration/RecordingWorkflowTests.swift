//
//  RecordingWorkflowTests.swift
//  TabletNotesTests
//
//  Created by Claude for testing purposes.
//

import Testing
import Foundation
import SwiftData
@testable import TabletNotes

struct RecordingWorkflowTests {
    private let mockAuthService = MockAuthService()
    private let mockRecordingService = MockRecordingService()
    private let mockSupabaseService = MockSupabaseService()
    
    // MARK: - Setup
    private func setupTest() async throws {
        // Reset all services
        mockRecordingService.resetState()
        mockSupabaseService.clearMockData()
        
        // Sign in a test user
        _ = try await mockAuthService.signIn(email: "test@example.com", password: "password123")
    }
    
    // MARK: - Complete Recording Workflow Tests
    @Test func testCompleteRecordingWorkflow() async throws {
        // Given
        try await setupTest()
        guard let user = await mockAuthService.getCurrentUser() else {
            #expect(Bool(false), "User should be signed in")
            return
        }
        
        // Step 1: Check permissions
        let hasPermission = try await mockRecordingService.requestPermissions()
        #expect(hasPermission == true)
        
        // Step 2: Start recording
        let recordingURL = try await mockRecordingService.startRecording()
        #expect(mockRecordingService.isRecording == true)
        #expect(recordingURL.pathExtension == "m4a")
        
        // Step 3: Simulate recording for a duration
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        let duration = mockRecordingService.getRecordingDuration()
        #expect(duration > 0)
        
        // Step 4: Stop recording
        let finalURL = try await mockRecordingService.stopRecording()
        #expect(mockRecordingService.isRecording == false)
        #expect(finalURL == recordingURL)
        
        // Step 5: Upload to Supabase
        let testAudioData = "Mock audio data for recording".data(using: .utf8)!
        let uploadPath = try await mockSupabaseService.uploadFile(
            data: testAudioData,
            fileName: recordingURL.lastPathComponent,
            userId: user.id
        )
        
        #expect(uploadPath.contains(user.id))
        #expect(uploadPath.contains(recordingURL.lastPathComponent))
        
        // Step 6: Verify file can be downloaded
        let downloadedData = try await mockSupabaseService.downloadFile(filePath: uploadPath)
        #expect(downloadedData == testAudioData)
    }
    
    @Test func testRecordingWorkflowWithPauseResume() async throws {
        // Given
        try await setupTest()
        
        // Start recording
        _ = try await mockRecordingService.startRecording()
        #expect(mockRecordingService.isRecording == true)
        
        // Record for a bit
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        let durationBeforePause = mockRecordingService.getRecordingDuration()
        
        // Pause recording
        try await mockRecordingService.pauseRecording()
        #expect(mockRecordingService.isRecording == true)
        #expect(mockRecordingService.isPaused == true)
        
        // Wait while paused (duration should not increase)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        let durationWhilePaused = mockRecordingService.getRecordingDuration()
        #expect(durationWhilePaused == durationBeforePause)
        
        // Resume recording
        try await mockRecordingService.resumeRecording()
        #expect(mockRecordingService.isRecording == true)
        #expect(mockRecordingService.isPaused == false)
        
        // Record a bit more
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        let finalDuration = mockRecordingService.getRecordingDuration()
        #expect(finalDuration > durationWhilePaused)
        
        // Stop recording
        _ = try await mockRecordingService.stopRecording()
        #expect(mockRecordingService.isRecording == false)
    }
    
    @Test func testRecordingWorkflowWithAuthenticationFailure() async throws {
        // Given - Start without authentication
        mockSupabaseService.clearMockData()
        mockRecordingService.resetState()
        
        // Recording should work (local operation)
        _ = try await mockRecordingService.startRecording()
        _ = try await mockRecordingService.stopRecording()
        
        // But upload should fail without authentication
        mockSupabaseService.setShouldFailNextCall(true, error: SupabaseError.authenticationRequired)
        
        await #expect(throws: SupabaseError.self) {
            try await mockSupabaseService.uploadFile(
                data: Data(),
                fileName: "test.m4a",
                userId: "no-user"
            )
        }
    }
    
    @Test func testRecordingWorkflowWithNetworkFailure() async throws {
        // Given
        try await setupTest()
        guard let user = await mockAuthService.getCurrentUser() else {
            #expect(Bool(false), "User should be signed in")
            return
        }
        
        // Recording should succeed
        let recordingURL = try await mockRecordingService.startRecording()
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        _ = try await mockRecordingService.stopRecording()
        
        // But upload should fail due to network issues
        mockSupabaseService.setShouldFailNextCall(true, error: SupabaseError.networkError)
        
        await #expect(throws: SupabaseError.self) {
            try await mockSupabaseService.uploadFile(
                data: Data(),
                fileName: recordingURL.lastPathComponent,
                userId: user.id
            )
        }
    }
    
    @Test func testRecordingWorkflowWithPermissionDenied() async throws {
        // Given
        try await setupTest()
        mockRecordingService.setShouldFailNextCall(true, error: RecordingError.permissionDenied)
        
        // When/Then - Should fail at permission request
        await #expect(throws: RecordingError.self) {
            try await mockRecordingService.requestPermissions()
        }
        
        // Recording should also fail
        await #expect(throws: RecordingError.self) {
            try await mockRecordingService.startRecording()
        }
    }
    
    // MARK: - Data Persistence Workflow Tests
    @Test func testSermonCreationAndSyncWorkflow() async throws {
        // Given
        try await setupTest()
        guard let user = await mockAuthService.getCurrentUser() else {
            #expect(Bool(false), "User should be signed in")
            return
        }
        
        // Create a sermon (simulating local creation)
        let sermon = Sermon(
            title: "Integration Test Sermon",
            serviceType: .sundayService,
            audioFilePath: "\(user.id)/test-recording.m4a",
            duration: 1800,
            recordedAt: Date(),
            userId: user.id
        )
        
        // Upload sermon to cloud
        try await mockSupabaseService.uploadSermon(sermon, userId: user.id)
        
        // Sync user data to get sermons back
        let syncedSermons = try await mockSupabaseService.syncUserData(userId: user.id)
        #expect(syncedSermons.count > 0)
        #expect(syncedSermons.allSatisfy { $0.userId == user.id })
    }
    
    @Test func testUserProfileUpdateWorkflow() async throws {
        // Given
        try await setupTest()
        guard let user = await mockAuthService.getCurrentUser() else {
            #expect(Bool(false), "User should be signed in")
            return
        }
        
        // Update auth service profile
        let updatedAuthUser = try await mockAuthService.updateProfile(displayName: "Updated Name")
        #expect(updatedAuthUser.displayName == "Updated Name")
        
        // Sync to Supabase
        try await mockSupabaseService.updateUserProfile(updatedAuthUser)
        
        // Verify sync
        let syncedUser = try await mockSupabaseService.getUserProfile(userId: user.id)
        #expect(syncedUser?.displayName == "Updated Name")
    }
    
    // MARK: - Error Recovery Workflow Tests
    @Test func testWorkflowWithRetryLogic() async throws {
        // Given
        try await setupTest()
        guard let user = await mockAuthService.getCurrentUser() else {
            #expect(Bool(false), "User should be signed in")
            return
        }
        
        // First attempt should fail
        mockSupabaseService.setShouldFailNextCall(true, error: SupabaseError.networkError)
        
        await #expect(throws: SupabaseError.self) {
            try await mockSupabaseService.uploadFile(
                data: Data(),
                fileName: "test.m4a",
                userId: user.id
            )
        }
        
        // Second attempt should succeed (failure flag is reset)
        let filePath = try await mockSupabaseService.uploadFile(
            data: "Retry test data".data(using: .utf8)!,
            fileName: "retry-test.m4a",
            userId: user.id
        )
        
        #expect(filePath.contains(user.id))
        #expect(filePath.contains("retry-test.m4a"))
    }
    
    @Test func testConcurrentRecordingAttempts() async throws {
        // Given
        try await setupTest()
        
        // Start first recording
        _ = try await mockRecordingService.startRecording()
        #expect(mockRecordingService.isRecording == true)
        
        // Attempt to start second recording concurrently
        await #expect(throws: RecordingError.self) {
            try await mockRecordingService.startRecording()
        }
        
        // First recording should still be active
        #expect(mockRecordingService.isRecording == true)
        
        // Should be able to stop the first recording
        _ = try await mockRecordingService.stopRecording()
        #expect(mockRecordingService.isRecording == false)
    }
}