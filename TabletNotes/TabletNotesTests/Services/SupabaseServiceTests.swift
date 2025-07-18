//
//  SupabaseServiceTests.swift
//  TabletNotesTests
//
//  Created by Claude for testing purposes.
//

import Testing
import Foundation
@testable import TabletNotes

struct SupabaseServiceTests {
    private let mockSupabaseService = MockSupabaseService()
    
    // MARK: - Setup and Teardown
    private func setupTest() {
        mockSupabaseService.clearMockData()
    }
    
    // MARK: - File Upload Tests
    @Test func testUploadFileSuccess() async throws {
        // Given
        setupTest()
        let testData = "Test audio data".data(using: .utf8)!
        let fileName = "test-recording.m4a"
        let userId = "test-user-id"
        
        // When
        let filePath = try await mockSupabaseService.uploadFile(
            data: testData,
            fileName: fileName,
            userId: userId
        )
        
        // Then
        #expect(filePath == "\(userId)/\(fileName)")
        
        // Verify file was stored
        let downloadedData = try await mockSupabaseService.downloadFile(filePath: filePath)
        #expect(downloadedData == testData)
    }
    
    @Test func testUploadFileFailure() async throws {
        // Given
        setupTest()
        mockSupabaseService.setShouldFailNextCall(true, error: SupabaseError.uploadFailed)
        let testData = "Test data".data(using: .utf8)!
        
        // When/Then
        await #expect(throws: SupabaseError.self) {
            try await mockSupabaseService.uploadFile(
                data: testData,
                fileName: "test.m4a",
                userId: "user-id"
            )
        }
    }
    
    // MARK: - File Download Tests
    @Test func testDownloadFileSuccess() async throws {
        // Given
        setupTest()
        let testData = "Test audio content".data(using: .utf8)!
        let filePath = "user-123/recording.m4a"
        mockSupabaseService.addMockFile(path: filePath, data: testData)
        
        // When
        let downloadedData = try await mockSupabaseService.downloadFile(filePath: filePath)
        
        // Then
        #expect(downloadedData == testData)
    }
    
    @Test func testDownloadFileNotFound() async throws {
        // Given
        setupTest()
        let nonExistentPath = "user-123/missing-file.m4a"
        
        // When/Then
        await #expect(throws: SupabaseError.self) {
            try await mockSupabaseService.downloadFile(filePath: nonExistentPath)
        }
    }
    
    @Test func testDownloadFileFailure() async throws {
        // Given
        setupTest()
        mockSupabaseService.setShouldFailNextCall(true, error: SupabaseError.downloadFailed)
        
        // When/Then
        await #expect(throws: SupabaseError.self) {
            try await mockSupabaseService.downloadFile(filePath: "any-path")
        }
    }
    
    // MARK: - File Delete Tests
    @Test func testDeleteFileSuccess() async throws {
        // Given
        setupTest()
        let testData = "Test data".data(using: .utf8)!
        let filePath = "user-123/to-delete.m4a"
        mockSupabaseService.addMockFile(path: filePath, data: testData)
        
        // When
        try await mockSupabaseService.deleteFile(filePath: filePath)
        
        // Then - File should no longer exist
        await #expect(throws: SupabaseError.self) {
            try await mockSupabaseService.downloadFile(filePath: filePath)
        }
    }
    
    @Test func testDeleteNonExistentFile() async throws {
        // Given
        setupTest()
        let nonExistentPath = "user-123/missing-file.m4a"
        
        // When/Then
        await #expect(throws: SupabaseError.self) {
            try await mockSupabaseService.deleteFile(filePath: nonExistentPath)
        }
    }
    
    // MARK: - Signed URL Generation Tests
    @Test func testGenerateSignedUploadURLSuccess() async throws {
        // Given
        setupTest()
        let fileName = "new-recording.m4a"
        let userId = "user-456"
        
        // When
        let result = try await mockSupabaseService.generateSignedUploadURL(
            fileName: fileName,
            userId: userId
        )
        
        // Then
        #expect(result.path == "\(userId)/\(fileName)")
        #expect(result.url.absoluteString.contains(fileName))
        #expect(result.url.absoluteString.contains("mock-supabase-url"))
    }
    
    @Test func testGenerateSignedUploadURLFailure() async throws {
        // Given
        setupTest()
        mockSupabaseService.setShouldFailNextCall(true, error: SupabaseError.signedURLFailed)
        
        // When/Then
        await #expect(throws: SupabaseError.self) {
            try await mockSupabaseService.generateSignedUploadURL(
                fileName: "test.m4a",
                userId: "user-id"
            )
        }
    }
    
    // MARK: - User Profile Tests
    @Test func testGetUserProfileSuccess() async throws {
        // Given
        setupTest()
        let mockUser = MockAuthService.createMockUser(id: "user-789", email: "test@example.com")
        mockSupabaseService.addMockUser(mockUser)
        
        // When
        let retrievedUser = try await mockSupabaseService.getUserProfile(userId: mockUser.id)
        
        // Then
        #expect(retrievedUser != nil)
        #expect(retrievedUser?.id == mockUser.id)
        #expect(retrievedUser?.email == mockUser.email)
    }
    
    @Test func testGetUserProfileNotFound() async throws {
        // Given
        setupTest()
        let nonExistentUserId = "non-existent-user"
        
        // When
        let retrievedUser = try await mockSupabaseService.getUserProfile(userId: nonExistentUserId)
        
        // Then
        #expect(retrievedUser == nil)
    }
    
    @Test func testUpdateUserProfileSuccess() async throws {
        // Given
        setupTest()
        let originalUser = MockAuthService.createMockUser(id: "user-123", email: "original@example.com")
        var updatedUser = originalUser
        updatedUser.displayName = "Updated Name"
        updatedUser.subscriptionTier = .premium
        
        // When
        try await mockSupabaseService.updateUserProfile(updatedUser)
        
        // Then
        let retrievedUser = try await mockSupabaseService.getUserProfile(userId: updatedUser.id)
        #expect(retrievedUser?.displayName == "Updated Name")
        #expect(retrievedUser?.subscriptionTier == .premium)
    }
    
    @Test func testUpdateUserProfileFailure() async throws {
        // Given
        setupTest()
        mockSupabaseService.setShouldFailNextCall(true, error: SupabaseError.updateFailed)
        let user = MockAuthService.createMockUser()
        
        // When/Then
        await #expect(throws: SupabaseError.self) {
            try await mockSupabaseService.updateUserProfile(user)
        }
    }
    
    // MARK: - Data Sync Tests
    @Test func testSyncUserDataSuccess() async throws {
        // Given
        setupTest()
        let userId = "sync-user-123"
        
        // When
        let sermons = try await mockSupabaseService.syncUserData(userId: userId)
        
        // Then
        #expect(sermons.count == 3) // Default mock returns 3 sermons
        #expect(sermons.allSatisfy { $0.userId == userId })
        #expect(sermons.allSatisfy { !$0.title.isEmpty })
    }
    
    @Test func testSyncUserDataFailure() async throws {
        // Given
        setupTest()
        mockSupabaseService.setShouldFailNextCall(true, error: SupabaseError.syncFailed)
        
        // When/Then
        await #expect(throws: SupabaseError.self) {
            try await mockSupabaseService.syncUserData(userId: "user-id")
        }
    }
    
    // MARK: - Sermon Management Tests
    @Test func testUploadSermonSuccess() async throws {
        // Given
        setupTest()
        let sermon = createTestSermon(userId: "user-456")
        
        // When/Then - Should not throw
        try await mockSupabaseService.uploadSermon(sermon, userId: sermon.userId)
    }
    
    @Test func testUploadSermonFailure() async throws {
        // Given
        setupTest()
        mockSupabaseService.setShouldFailNextCall(true, error: SupabaseError.uploadFailed)
        let sermon = createTestSermon(userId: "user-456")
        
        // When/Then
        await #expect(throws: SupabaseError.self) {
            try await mockSupabaseService.uploadSermon(sermon, userId: sermon.userId)
        }
    }
    
    @Test func testDownloadSermonSuccess() async throws {
        // Given
        setupTest()
        let sermonId = "mock-sermon-123"
        let userId = "user-789"
        
        // When
        let sermon = try await mockSupabaseService.downloadSermon(sermonId: sermonId, userId: userId)
        
        // Then
        #expect(sermon != nil)
        #expect(sermon?.userId == userId)
        #expect(sermon?.audioFilePath.contains(userId) == true)
    }
    
    @Test func testDownloadSermonNotFound() async throws {
        // Given
        setupTest()
        let nonExistentSermonId = "non-existent-sermon"
        
        // When
        let sermon = try await mockSupabaseService.downloadSermon(
            sermonId: nonExistentSermonId,
            userId: "user-id"
        )
        
        // Then
        #expect(sermon == nil)
    }
    
    // MARK: - Integration Tests
    @Test func testFileUploadDownloadDeleteCycle() async throws {
        // Given
        setupTest()
        let testData = "Integration test audio data".data(using: .utf8)!
        let fileName = "integration-test.m4a"
        let userId = "integration-user"
        
        // Upload
        let filePath = try await mockSupabaseService.uploadFile(
            data: testData,
            fileName: fileName,
            userId: userId
        )
        
        // Download and verify
        let downloadedData = try await mockSupabaseService.downloadFile(filePath: filePath)
        #expect(downloadedData == testData)
        
        // Delete
        try await mockSupabaseService.deleteFile(filePath: filePath)
        
        // Verify deletion
        await #expect(throws: SupabaseError.self) {
            try await mockSupabaseService.downloadFile(filePath: filePath)
        }
    }
    
    // MARK: - Helper Methods
    private func createTestSermon(userId: String) -> Sermon {
        return Sermon(
            title: "Test Sermon",
            serviceType: .sundayService,
            audioFilePath: "\(userId)/test-audio.m4a",
            duration: 1800,
            recordedAt: Date(),
            userId: userId
        )
    }
}