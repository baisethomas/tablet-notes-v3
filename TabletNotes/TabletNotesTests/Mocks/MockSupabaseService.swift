//
//  MockSupabaseService.swift
//  TabletNotesTests
//
//  Created by Claude for testing purposes.
//

import Foundation
@testable import TabletNotes

class MockSupabaseService: SupabaseServiceProtocol {
    // MARK: - Mock State
    private var shouldFailNextCall = false
    private var mockError: Error?
    private var mockFiles: [String: Data] = [:]
    private var mockUsers: [String: User] = [:]
    
    // MARK: - Test Configuration
    func setShouldFailNextCall(_ shouldFail: Bool, error: Error? = nil) {
        shouldFailNextCall = shouldFail
        mockError = error ?? SupabaseError.networkError
    }
    
    func addMockFile(path: String, data: Data) {
        mockFiles[path] = data
    }
    
    func addMockUser(_ user: User) {
        mockUsers[user.id] = user
    }
    
    func clearMockData() {
        mockFiles.removeAll()
        mockUsers.removeAll()
    }
    
    // MARK: - SupabaseServiceProtocol Implementation
    func uploadFile(data: Data, fileName: String, userId: String) async throws -> String {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? SupabaseError.uploadFailed
        }
        
        let filePath = "\(userId)/\(fileName)"
        mockFiles[filePath] = data
        
        return filePath
    }
    
    func downloadFile(filePath: String) async throws -> Data {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? SupabaseError.downloadFailed
        }
        
        guard let data = mockFiles[filePath] else {
            throw SupabaseError.fileNotFound
        }
        
        return data
    }
    
    func deleteFile(filePath: String) async throws {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? SupabaseError.deleteFailed
        }
        
        guard mockFiles[filePath] != nil else {
            throw SupabaseError.fileNotFound
        }
        
        mockFiles.removeValue(forKey: filePath)
    }
    
    func generateSignedUploadURL(fileName: String, userId: String) async throws -> (url: URL, path: String) {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? SupabaseError.signedURLFailed
        }
        
        let path = "\(userId)/\(fileName)"
        let url = URL(string: "https://mock-supabase-url.com/upload/\(path)")!
        
        return (url: url, path: path)
    }
    
    func getUserProfile(userId: String) async throws -> User? {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? SupabaseError.networkError
        }
        
        return mockUsers[userId]
    }
    
    func updateUserProfile(_ user: User) async throws {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? SupabaseError.updateFailed
        }
        
        mockUsers[user.id] = user
    }
    
    func syncUserData(userId: String) async throws -> [Sermon] {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? SupabaseError.syncFailed
        }
        
        // Return mock sermon data
        return createMockSermons(userId: userId)
    }
    
    func uploadSermon(_ sermon: Sermon, userId: String) async throws {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? SupabaseError.uploadFailed
        }
        
        // Mock sermon upload - no-op for testing
    }
    
    func downloadSermon(sermonId: String, userId: String) async throws -> Sermon? {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? SupabaseError.downloadFailed
        }
        
        // Return mock sermon if it matches expected pattern
        if sermonId.hasPrefix("mock-sermon") {
            return createMockSermon(id: sermonId, userId: userId)
        }
        
        return nil
    }
    
    // MARK: - Mock Data Helpers
    private func createMockSermons(userId: String, count: Int = 3) -> [Sermon] {
        return (1...count).map { index in
            createMockSermon(id: "mock-sermon-\(index)", userId: userId)
        }
    }
    
    private func createMockSermon(id: String, userId: String) -> Sermon {
        return Sermon(
            title: "Mock Sermon \(id.suffix(1))",
            serviceType: .sundayService,
            audioFilePath: "\(userId)/mock-audio-\(id).m4a",
            duration: 1800, // 30 minutes
            recordedAt: Date().addingTimeInterval(-Double.random(in: 0...604800)), // Within last week
            userId: userId
        )
    }
}

// MARK: - Supabase Errors for Testing
enum SupabaseError: LocalizedError {
    case networkError
    case uploadFailed
    case downloadFailed
    case deleteFailed
    case fileNotFound
    case signedURLFailed
    case updateFailed
    case syncFailed
    case authenticationRequired
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection error"
        case .uploadFailed:
            return "File upload failed"
        case .downloadFailed:
            return "File download failed"
        case .deleteFailed:
            return "File deletion failed"
        case .fileNotFound:
            return "File not found"
        case .signedURLFailed:
            return "Failed to generate signed URL"
        case .updateFailed:
            return "Profile update failed"
        case .syncFailed:
            return "Data synchronization failed"
        case .authenticationRequired:
            return "Authentication required"
        }
    }
}