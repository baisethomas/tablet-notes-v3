//
//  MockAuthService.swift
//  TabletNotesTests
//
//  Created by Claude for testing purposes.
//

import Foundation
import Combine
@testable import TabletNotes

@MainActor
class MockAuthService: AuthServiceProtocol, ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var authState: AuthState = .unauthenticated
    @Published private(set) var currentUser: User? = nil

    // MARK: - Publishers
    var authStatePublisher: AnyPublisher<AuthState, Never> {
        $authState.eraseToAnyPublisher()
    }

    var currentUserPublisher: AnyPublisher<User?, Never> {
        $currentUser.eraseToAnyPublisher()
    }

    // MARK: - Mock State
    private var shouldFailNextCall = false
    private var mockError: AuthError?

    // MARK: - Test Configuration
    func setAuthState(_ state: AuthState) {
        authState = state
        switch state {
        case .authenticated(let user):
            currentUser = user
        default:
            currentUser = nil
        }
    }

    func setShouldFailNextCall(_ shouldFail: Bool, error: AuthError? = nil) {
        shouldFailNextCall = shouldFail
        mockError = error ?? .networkError
    }

    func resetState() {
        authState = .unauthenticated
        currentUser = nil
        shouldFailNextCall = false
        mockError = nil
    }

    // MARK: - AuthServiceProtocol Implementation
    func signUp(data: SignUpData) async throws -> User {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? .networkError
        }

        let user = User(
            id: UUID(),
            email: data.email,
            name: data.name,
            profileImageURL: nil,
            createdAt: Date(),
            isEmailVerified: true,
            subscriptionTier: "pro",
            subscriptionStatus: "active",
            subscriptionExpiry: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
            subscriptionProductId: nil,
            subscriptionPurchaseDate: Date(),
            subscriptionRenewalDate: Calendar.current.date(byAdding: .day, value: 14, to: Date())
        )

        authState = .authenticated(user)
        currentUser = user
        return user
    }

    func signIn(email: String, password: String) async throws -> User {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? .invalidCredentials
        }

        let user = User(
            id: UUID(),
            email: email,
            name: "Test User",
            profileImageURL: nil,
            createdAt: Date().addingTimeInterval(-86400), // Yesterday
            isEmailVerified: true,
            subscriptionTier: "pro",
            subscriptionStatus: "active",
            subscriptionExpiry: Calendar.current.date(byAdding: .day, value: 10, to: Date()),
            subscriptionProductId: nil,
            subscriptionPurchaseDate: Date().addingTimeInterval(-86400),
            subscriptionRenewalDate: Calendar.current.date(byAdding: .day, value: 10, to: Date())
        )

        authState = .authenticated(user)
        currentUser = user
        return user
    }

    func signOut() async throws {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? .networkError
        }

        authState = .unauthenticated
        currentUser = nil
    }

    func resetPassword(email: String) async throws {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? .networkError
        }

        // Mock password reset - no-op for testing
    }

    func updateProfile(name: String, email: String?) async throws -> User {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? .networkError
        }

        guard let existingUser = currentUser else {
            throw AuthError.sessionExpired
        }

        let updatedUser = User(
            id: existingUser.id,
            email: email ?? existingUser.email,
            name: name,
            profileImageURL: existingUser.profileImageURL,
            createdAt: existingUser.createdAt,
            isEmailVerified: existingUser.isEmailVerified,
            subscriptionTier: existingUser.subscriptionTier,
            subscriptionStatus: existingUser.subscriptionStatus,
            subscriptionExpiry: existingUser.subscriptionExpiry,
            subscriptionProductId: existingUser.subscriptionProductId,
            subscriptionPurchaseDate: existingUser.subscriptionPurchaseDate,
            subscriptionRenewalDate: existingUser.subscriptionRenewalDate,
            monthlyRecordingCount: existingUser.monthlyRecordingCount,
            monthlyRecordingMinutes: existingUser.monthlyRecordingMinutes,
            currentStorageUsedGB: existingUser.currentStorageUsedGB,
            monthlyExportCount: existingUser.monthlyExportCount,
            lastUsageResetDate: existingUser.lastUsageResetDate
        )

        authState = .authenticated(updatedUser)
        currentUser = updatedUser
        return updatedUser
    }

    func deleteAccount() async throws {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? .networkError
        }

        authState = .unauthenticated
        currentUser = nil
    }

    func refreshSession() async throws {
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw mockError ?? .sessionExpired
        }

        // Mock session refresh - no-op for testing
        // In a real implementation, this would refresh the authentication token
    }

    nonisolated func isAuthenticated() -> Bool {
        // Since this is nonisolated, we can't access @MainActor properties directly
        // For mock purposes, we'll return a simple implementation
        return true // Mock always returns authenticated for simplicity
    }
}

// MARK: - Test Helpers
extension MockAuthService {
    static func createMockUser(
        id: UUID = UUID(),
        email: String = "test@example.com",
        name: String = "Test User",
        tier: String = "pro"
    ) -> User {
        return User(
            id: id,
            email: email,
            name: name,
            profileImageURL: nil,
            createdAt: Date().addingTimeInterval(-86400),
            isEmailVerified: true,
            subscriptionTier: tier,
            subscriptionStatus: "active",
            subscriptionExpiry: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
            subscriptionProductId: nil,
            subscriptionPurchaseDate: Date().addingTimeInterval(-86400),
            subscriptionRenewalDate: Calendar.current.date(byAdding: .day, value: 14, to: Date())
        )
    }
}