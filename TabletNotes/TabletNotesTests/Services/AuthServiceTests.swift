import Foundation
import Testing
@testable import TabletNotes

@MainActor
struct AuthServiceTests {
    private let mockAuthService = MockAuthService()

    @Test func testSignUpSuccess() async throws {
        let signUpData = SignUpData(
            email: "test@example.com",
            password: "password123",
            name: "Test User"
        )

        let user = try await mockAuthService.signUp(data: signUpData)

        #expect(user.email == signUpData.email)
        #expect(user.name == signUpData.name)
        #expect(user.subscriptionTierEnum == .premium)
        #expect(mockAuthService.currentUser?.id == user.id)
        #expect(mockAuthService.authState == .authenticated(user))
    }

    @Test func testSignUpFailure() async throws {
        mockAuthService.setShouldFailNextCall(true, error: .emailAlreadyExists)

        await #expect(throws: AuthError.self) {
            try await mockAuthService.signUp(
                data: SignUpData(
                    email: "test@example.com",
                    password: "password123",
                    name: "Test User"
                )
            )
        }

        #expect(mockAuthService.currentUser == nil)
        #expect(mockAuthService.authState == .unauthenticated)
    }

    @Test func testSignInSuccess() async throws {
        let user = try await mockAuthService.signIn(email: "existing@example.com", password: "password123")

        #expect(user.email == "existing@example.com")
        #expect(mockAuthService.currentUser?.id == user.id)
        #expect(mockAuthService.authState == .authenticated(user))
    }

    @Test func testSignInWithInvalidCredentials() async throws {
        mockAuthService.setShouldFailNextCall(true, error: .invalidCredentials)

        await #expect(throws: AuthError.self) {
            try await mockAuthService.signIn(email: "wrong@example.com", password: "wrongpassword")
        }

        #expect(mockAuthService.currentUser == nil)
        #expect(mockAuthService.authState == .unauthenticated)
    }

    @Test func testSignInWithSocialSuccess() async throws {
        let user = try await mockAuthService.signInWithSocial(provider: .google)

        #expect(user.email == "google@example.com")
        #expect(user.name == "Google User")
        #expect(mockAuthService.currentUser?.id == user.id)
    }

    @Test func testSignInWithAppleUsesProvidedFullName() async throws {
        let user = try await mockAuthService.signInWithApple(
            idToken: "test-token",
            nonce: nil,
            fullName: "Updated Name"
        )

        #expect(user.name == "Updated Name")
        #expect(mockAuthService.currentUser?.name == "Updated Name")
    }

    @Test func testSignOutSuccess() async throws {
        _ = try await mockAuthService.signIn(email: "test@example.com", password: "password123")

        try await mockAuthService.signOut()

        #expect(mockAuthService.currentUser == nil)
        #expect(mockAuthService.authState == .unauthenticated)
    }

    @Test func testSignOutFailure() async throws {
        _ = try await mockAuthService.signIn(email: "test@example.com", password: "password123")
        let signedInUser = mockAuthService.currentUser
        mockAuthService.setShouldFailNextCall(true, error: .networkError)

        await #expect(throws: AuthError.self) {
            try await mockAuthService.signOut()
        }

        #expect(mockAuthService.currentUser?.id == signedInUser?.id)
    }

    @Test func testCurrentUserWhenSignedIn() async throws {
        let signedInUser = try await mockAuthService.signIn(email: "test@example.com", password: "password123")

        #expect(mockAuthService.currentUser?.id == signedInUser.id)
        #expect(mockAuthService.currentUser?.email == signedInUser.email)
    }

    @Test func testCurrentUserWhenSignedOut() async throws {
        mockAuthService.resetState()

        #expect(mockAuthService.currentUser == nil)
        #expect(mockAuthService.authState == .unauthenticated)
    }

    @Test func testUpdateProfileSuccess() async throws {
        _ = try await mockAuthService.signIn(email: "test@example.com", password: "password123")

        let updatedUser = try await mockAuthService.updateProfile(name: "Updated Name", email: nil)

        #expect(updatedUser.name == "Updated Name")
        #expect(mockAuthService.currentUser?.name == "Updated Name")
    }

    @Test func testUpdateProfileWhenNotAuthenticated() async throws {
        mockAuthService.resetState()

        await #expect(throws: AuthError.self) {
            try await mockAuthService.updateProfile(name: "Test Name", email: nil)
        }
    }

    @Test func testRefreshSessionSuccessKeepsCurrentUser() async throws {
        let signedInUser = try await mockAuthService.signIn(email: "test@example.com", password: "password123")

        try await mockAuthService.refreshSession()

        #expect(mockAuthService.currentUser?.id == signedInUser.id)
    }

    @Test func testRefreshSessionFailure() async throws {
        _ = try await mockAuthService.signIn(email: "test@example.com", password: "password123")
        mockAuthService.setShouldFailNextCall(true, error: .sessionExpired)

        await #expect(throws: AuthError.self) {
            try await mockAuthService.refreshSession()
        }
    }

    @Test func testDeleteAccountSuccess() async throws {
        _ = try await mockAuthService.signIn(email: "test@example.com", password: "password123")

        try await mockAuthService.deleteAccount()

        #expect(mockAuthService.currentUser == nil)
        #expect(mockAuthService.authState == .unauthenticated)
    }

    @Test func testResetPasswordSuccess() async throws {
        try await mockAuthService.resetPassword(email: "test@example.com")
    }

    @Test func testResetPasswordFailure() async throws {
        mockAuthService.setShouldFailNextCall(true, error: .networkError)

        await #expect(throws: AuthError.self) {
            try await mockAuthService.resetPassword(email: "test@example.com")
        }
    }
}
