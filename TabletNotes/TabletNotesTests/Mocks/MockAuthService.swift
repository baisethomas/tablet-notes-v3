//
//  MockAuthService.swift
//  TabletNotesTests
//
//  Created by Claude for testing purposes.
//

import Foundation
import SwiftData
@testable import TabletNotes

class MockAuthService: AuthServiceProtocol {
    // MARK: - Mock State
    private(set) var isSignedIn = false
    private(set) var currentUser: User?
    private var shouldFailNextCall = false
    private var mockError: Error?
    
    // MARK: - Test Configuration
    func setSignedIn(_ signedIn: Bool, user: User? = nil) {
        isSignedIn = signedIn
        currentUser = user
    }
    
    func setShouldFailNextCall(_ shouldFail: Bool, error: Error? = nil) {
        shouldFailNextCall = shouldFail
        mockError = error ?? AuthError.networkError
    }
    
    // MARK: - AuthServiceProtocol Implementation
    func signUp(email: String, password: String) async throws -> User {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? AuthError.networkError
        }
        
        let user = User(
            id: "mock-user-\(UUID().uuidString)",
            email: email,
            displayName: nil,
            subscriptionTier: .pro,
            trialEndDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
            isActive: true,
            createdAt: Date(),
            lastLoginAt: Date()
        )
        
        isSignedIn = true
        currentUser = user
        return user
    }
    
    func signIn(email: String, password: String) async throws -> User {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? AuthError.invalidCredentials
        }
        
        let user = User(
            id: "mock-user-signin",
            email: email,
            displayName: nil,
            subscriptionTier: .pro,
            trialEndDate: Calendar.current.date(byAdding: .day, value: 10, to: Date()),
            isActive: true,
            createdAt: Date().addingTimeInterval(-86400), // Yesterday
            lastLoginAt: Date()
        )
        
        isSignedIn = true
        currentUser = user
        return user
    }
    
    func signOut() async throws {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? AuthError.networkError
        }
        
        isSignedIn = false
        currentUser = nil
    }
    
    func getCurrentUser() async -> User? {
        return currentUser
    }
    
    func updateProfile(displayName: String?) async throws -> User {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? AuthError.networkError
        }
        
        guard var user = currentUser else {
            throw AuthError.notAuthenticated
        }
        
        user.displayName = displayName
        currentUser = user
        return user
    }
    
    func refreshSession() async throws {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? AuthError.sessionExpired
        }
        
        // Mock session refresh - update last login
        if var user = currentUser {
            user.lastLoginAt = Date()
            currentUser = user
        }
    }
    
    func resetPassword(email: String) async throws {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? AuthError.networkError
        }
        
        // Mock password reset - no-op for testing
    }
    
    func updateSubscription(tier: SubscriptionTier) async throws -> User {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? AuthError.networkError
        }
        
        guard var user = currentUser else {
            throw AuthError.notAuthenticated
        }
        
        user.subscriptionTier = tier
        currentUser = user
        return user
    }
}

// MARK: - Test Helpers
extension MockAuthService {
    static func createMockUser(
        id: String = "test-user-id",
        email: String = "test@example.com",
        tier: SubscriptionTier = .pro
    ) -> User {
        return User(
            id: id,
            email: email,
            displayName: "Test User",
            subscriptionTier: tier,
            trialEndDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
            isActive: true,
            createdAt: Date().addingTimeInterval(-86400),
            lastLoginAt: Date()
        )
    }
}