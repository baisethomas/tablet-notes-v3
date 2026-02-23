import Foundation
import Combine

enum SocialAuthProvider: String, CaseIterable, Sendable {
    case google
    case apple
    
    var displayName: String {
        switch self {
        case .google: "Google"
        case .apple: "Apple"
        }
    }
}

@MainActor
protocol AuthServiceProtocol: ObservableObject {
    // Current authentication state
    var authState: AuthState { get }
    var authStatePublisher: AnyPublisher<AuthState, Never> { get }
    
    // Current user
    var currentUser: User? { get }
    var currentUserPublisher: AnyPublisher<User?, Never> { get }
    
    // Authentication methods
    func signUp(data: SignUpData) async throws -> User
    func signIn(email: String, password: String) async throws -> User
    func signInWithSocial(provider: SocialAuthProvider) async throws -> User
    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws -> User
    func signOut() async throws
    func resetPassword(email: String) async throws
    func updateProfile(name: String, email: String?) async throws -> User
    func deleteAccount() async throws
    
    // Session management
    func refreshSession() async throws
    nonisolated func isAuthenticated() -> Bool
} 
