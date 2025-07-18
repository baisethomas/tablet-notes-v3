//
//  AuthServiceTests.swift
//  TabletNotesTests
//
//  Created by Claude for testing purposes.
//

import Testing
import Foundation
@testable import TabletNotes

struct AuthServiceTests {
    private let mockAuthService = MockAuthService()
    
    // MARK: - Sign Up Tests
    @Test func testSignUpSuccess() async throws {
        // Given
        let email = "test@example.com"
        let password = "password123"
        
        // When
        let user = try await mockAuthService.signUp(email: email, password: password)
        
        // Then
        #expect(user.email == email)
        #expect(mockAuthService.isSignedIn == true)
        #expect(mockAuthService.currentUser?.email == email)
        #expect(user.subscriptionTier == .pro) // Default for new users
        #expect(user.trialEndDate != nil)
    }
    
    @Test func testSignUpFailure() async throws {
        // Given
        mockAuthService.setShouldFailNextCall(true, error: AuthError.emailAlreadyExists)
        
        // When/Then
        await #expect(throws: AuthError.self) {
            try await mockAuthService.signUp(email: "test@example.com", password: "password123")
        }
        
        #expect(mockAuthService.isSignedIn == false)
        #expect(mockAuthService.currentUser == nil)
    }
    
    // MARK: - Sign In Tests
    @Test func testSignInSuccess() async throws {
        // Given
        let email = "existing@example.com"
        let password = "password123"
        
        // When
        let user = try await mockAuthService.signIn(email: email, password: password)
        
        // Then
        #expect(user.email == email)
        #expect(mockAuthService.isSignedIn == true)
        #expect(mockAuthService.currentUser?.email == email)
        #expect(user.lastLoginAt != nil)
    }
    
    @Test func testSignInWithInvalidCredentials() async throws {
        // Given
        mockAuthService.setShouldFailNextCall(true, error: AuthError.invalidCredentials)
        
        // When/Then
        await #expect(throws: AuthError.self) {
            try await mockAuthService.signIn(email: "wrong@example.com", password: "wrongpassword")
        }
        
        #expect(mockAuthService.isSignedIn == false)
        #expect(mockAuthService.currentUser == nil)
    }
    
    // MARK: - Sign Out Tests
    @Test func testSignOutSuccess() async throws {
        // Given - Sign in first
        _ = try await mockAuthService.signIn(email: "test@example.com", password: "password123")
        #expect(mockAuthService.isSignedIn == true)
        
        // When
        try await mockAuthService.signOut()
        
        // Then
        #expect(mockAuthService.isSignedIn == false)
        #expect(mockAuthService.currentUser == nil)
    }
    
    @Test func testSignOutFailure() async throws {
        // Given - Sign in first
        _ = try await mockAuthService.signIn(email: "test@example.com", password: "password123")
        mockAuthService.setShouldFailNextCall(true, error: AuthError.networkError)
        
        // When/Then
        await #expect(throws: AuthError.self) {
            try await mockAuthService.signOut()
        }
    }
    
    // MARK: - Current User Tests
    @Test func testGetCurrentUserWhenSignedIn() async throws {
        // Given
        let signedInUser = try await mockAuthService.signIn(email: "test@example.com", password: "password123")
        
        // When
        let currentUser = await mockAuthService.getCurrentUser()
        
        // Then
        #expect(currentUser != nil)
        #expect(currentUser?.id == signedInUser.id)
        #expect(currentUser?.email == signedInUser.email)
    }
    
    @Test func testGetCurrentUserWhenSignedOut() async throws {
        // Given - Ensure signed out
        mockAuthService.setSignedIn(false, user: nil)
        
        // When
        let currentUser = await mockAuthService.getCurrentUser()
        
        // Then
        #expect(currentUser == nil)
    }
    
    // MARK: - Profile Update Tests
    @Test func testUpdateProfileSuccess() async throws {
        // Given
        _ = try await mockAuthService.signIn(email: "test@example.com", password: "password123")
        let newDisplayName = "Updated Name"
        
        // When
        let updatedUser = try await mockAuthService.updateProfile(displayName: newDisplayName)
        
        // Then
        #expect(updatedUser.displayName == newDisplayName)
        #expect(mockAuthService.currentUser?.displayName == newDisplayName)
    }
    
    @Test func testUpdateProfileWhenNotAuthenticated() async throws {
        // Given - Ensure signed out
        mockAuthService.setSignedIn(false, user: nil)
        
        // When/Then
        await #expect(throws: AuthError.self) {
            try await mockAuthService.updateProfile(displayName: "Test Name")
        }
    }
    
    // MARK: - Session Management Tests
    @Test func testRefreshSessionSuccess() async throws {
        // Given
        let user = try await mockAuthService.signIn(email: "test@example.com", password: "password123")
        let originalLoginTime = user.lastLoginAt
        
        // Wait a brief moment to ensure time difference
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // When
        try await mockAuthService.refreshSession()
        
        // Then
        let currentUser = await mockAuthService.getCurrentUser()
        #expect(currentUser?.lastLoginAt != nil)
        #expect(currentUser?.lastLoginAt != originalLoginTime)
    }
    
    @Test func testRefreshSessionFailure() async throws {
        // Given
        _ = try await mockAuthService.signIn(email: "test@example.com", password: "password123")
        mockAuthService.setShouldFailNextCall(true, error: AuthError.sessionExpired)
        
        // When/Then
        await #expect(throws: AuthError.self) {
            try await mockAuthService.refreshSession()
        }
    }
    
    // MARK: - Subscription Management Tests
    @Test func testUpdateSubscriptionSuccess() async throws {
        // Given
        _ = try await mockAuthService.signIn(email: "test@example.com", password: "password123")
        let newTier = SubscriptionTier.premium
        
        // When
        let updatedUser = try await mockAuthService.updateSubscription(tier: newTier)
        
        // Then
        #expect(updatedUser.subscriptionTier == newTier)
        #expect(mockAuthService.currentUser?.subscriptionTier == newTier)
    }
    
    @Test func testUpdateSubscriptionWhenNotAuthenticated() async throws {
        // Given - Ensure signed out
        mockAuthService.setSignedIn(false, user: nil)
        
        // When/Then
        await #expect(throws: AuthError.self) {
            try await mockAuthService.updateSubscription(tier: .premium)
        }
    }
    
    // MARK: - Password Reset Tests
    @Test func testResetPasswordSuccess() async throws {
        // Given
        let email = "test@example.com"
        
        // When/Then - Should not throw
        try await mockAuthService.resetPassword(email: email)
    }
    
    @Test func testResetPasswordFailure() async throws {
        // Given
        mockAuthService.setShouldFailNextCall(true, error: AuthError.networkError)
        
        // When/Then
        await #expect(throws: AuthError.self) {
            try await mockAuthService.resetPassword(email: "test@example.com")
        }
    }
}

// MARK: - Auth Error Definitions for Testing
enum AuthError: LocalizedError, Equatable {
    case emailAlreadyExists
    case invalidCredentials
    case networkError
    case notAuthenticated
    case sessionExpired
    case weakPassword
    case invalidEmail
    case userNotFound
    
    var errorDescription: String? {
        switch self {
        case .emailAlreadyExists:
            return "Email already exists"
        case .invalidCredentials:
            return "Invalid credentials"
        case .networkError:
            return "Network error"
        case .notAuthenticated:
            return "Not authenticated"
        case .sessionExpired:
            return "Session expired"
        case .weakPassword:
            return "Password is too weak"
        case .invalidEmail:
            return "Invalid email format"
        case .userNotFound:
            return "User not found"
        }
    }
}