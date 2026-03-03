import Foundation
import Combine
import SwiftUI
import Observation
import FirebaseCrashlytics

@MainActor
@Observable
final class AuthenticationManager {

    // MARK: - Observable Properties (auto-tracked by @Observable)
    private(set) var authState: AuthState = .loading
    private(set) var currentUser: User? = nil
    private(set) var isInitialized = false

    // MARK: - Combine Publishers (for backward compatibility during migration)
    @ObservationIgnored @Published var authStatePublished: AuthState = .loading
    
    // MARK: - Private Properties
    private let authService: any AuthServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Singleton
    static let shared = AuthenticationManager()
    
    // MARK: - Initialization
    init() {
        self.authService = SupabaseAuthService()
        print("[AuthenticationManager] Initializing AuthenticationManager: \(ObjectIdentifier(self))")
        print("[AuthenticationManager] Using SupabaseAuthService instance: \(ObjectIdentifier(self.authService))")
        print("[AuthenticationManager] Setting up bindings")
        setupBindings()
        print("[AuthenticationManager] Initializing auth state")
        initializeAuth()
    }
    
    // MARK: - Public Methods
    
    func signUp(data: SignUpData) async throws -> User {
        return try await authService.signUp(data: data)
    }
    
    func signIn(email: String, password: String) async throws -> User {
        print("[AuthenticationManager] signIn called on AuthManager: \(ObjectIdentifier(self)), using SupabaseAuthService: \(ObjectIdentifier(authService))")
        return try await authService.signIn(email: email, password: password)
    }
    
    func signInWithSocial(provider: SocialAuthProvider) async throws -> User {
        print("[AuthenticationManager] signInWithSocial called with provider: \(provider.rawValue)")
        return try await authService.signInWithSocial(provider: provider)
    }
    
    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws -> User {
        print("[AuthenticationManager] signInWithApple called")
        return try await authService.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
    }
    
    func signOut() async throws {
        try await authService.signOut()
    }
    
    func resetPassword(email: String) async throws {
        try await authService.resetPassword(email: email)
    }
    
    func updateProfile(name: String, email: String? = nil) async throws -> User {
        return try await authService.updateProfile(name: name, email: email)
    }
    
    func deleteAccount() async throws {
        try await authService.deleteAccount()
    }
    
    func refreshSession() async throws {
        try await authService.refreshSession()
    }
    
    func checkAuthenticationStatus() -> Bool {
        return authService.isAuthenticated()
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Bind auth service state to manager state
        authService.authStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                print("[AuthenticationManager] Auth state changed to: \(state)")
                guard let self = self else { return }
                self.authState = state
                self.authStatePublished = state // Sync for backward compat
                self.updateCrashlyticsUserContext(user: self.currentUser, authState: state)
            }
            .store(in: &cancellables)
        
        // Bind current user
        authService.currentUserPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                print("[AuthenticationManager] Current user changed to: \(user?.name ?? "nil")")
                
                // Fix subscription data inconsistencies before setting the user
                if let user = user {
                    user.fixSubscriptionDataInconsistency()
                }
                
                self?.currentUser = user
                self?.updateCrashlyticsUserContext(user: user, authState: self?.authState ?? .loading)
                
                // Validate transcription provider when user changes
                if user != nil {
                    SettingsService.shared.validateTranscriptionProvider()
                }
            }
            .store(in: &cancellables)
    }

    private func updateCrashlyticsUserContext(user: User?, authState: AuthState) {
        let crashlytics = Crashlytics.crashlytics()

        if let user {
            crashlytics.setUserID(user.id.uuidString)
            crashlytics.setCustomValue(user.id.uuidString, forKey: "app_user_id")
            crashlytics.setCustomValue(true, forKey: "is_authenticated")
            crashlytics.setCustomValue(user.subscriptionTier, forKey: "subscription_tier")
            crashlytics.setCustomValue(user.subscriptionStatus, forKey: "subscription_status")
            crashlytics.setCustomValue(user.isEmailVerified, forKey: "email_verified")

            let emailDomain = user.email.split(separator: "@").last.map(String.init) ?? ""
            crashlytics.setCustomValue(emailDomain, forKey: "email_domain")
        } else {
            crashlytics.setUserID("")
            crashlytics.setCustomValue("", forKey: "app_user_id")
            crashlytics.setCustomValue(false, forKey: "is_authenticated")
            crashlytics.setCustomValue("", forKey: "subscription_tier")
            crashlytics.setCustomValue("", forKey: "subscription_status")
            crashlytics.setCustomValue(false, forKey: "email_verified")
            crashlytics.setCustomValue("", forKey: "email_domain")
        }

        crashlytics.setCustomValue(crashlyticsAuthStateLabel(authState), forKey: "auth_state")
    }

    private func crashlyticsAuthStateLabel(_ authState: AuthState) -> String {
        switch authState {
        case .loading:
            return "loading"
        case .authenticated:
            return "authenticated"
        case .unauthenticated:
            return "unauthenticated"
        case .error(let error):
            return "error:\(error.localizedDescription)"
        }
    }
    
    private func initializeAuth() {
        Task {
            do {
                // Try to refresh existing session
                try await authService.refreshSession()
            } catch {
                // If refresh fails, user is not authenticated
                authState = .unauthenticated
                authStatePublished = .unauthenticated // Sync for backward compat
            }
            
            isInitialized = true
        }
    }
}

// MARK: - Authentication State Helpers
extension AuthenticationManager {
    
    var isLoading: Bool {
        if case .loading = authState {
            return true
        }
        return false
    }
    
    var isAuthenticated: Bool {
        if case .authenticated = authState {
            return true
        }
        return false
    }
    
    var authError: AuthError? {
        if case .error(let error) = authState {
            return error
        }
        return nil
    }
    
    func requiresAuthentication() -> Bool {
        return !isAuthenticated && isInitialized
    }
}

// MARK: - View Modifier for Authentication
struct AuthenticationRequired: ViewModifier {
    @State private var authManager = AuthenticationManager.shared
    @State private var recheckTimer: Timer?

    func body(content: Content) -> some View {
        Group {
            if authManager.isInitialized {
                if authManager.isAuthenticated {
                    content
                } else {
                    AuthenticationView()
                        .onAppear {
                            print("[AuthenticationRequired] Auth view appeared - starting periodic recheck")
                            startPeriodicRecheck()
                        }
                        .onDisappear {
                            print("[AuthenticationRequired] Auth view disappeared - stopping recheck")
                            stopPeriodicRecheck()
                        }
                }
            } else {
                // Show loading while checking auth state
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))

                    Text("Loading...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.top, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            print("[AuthenticationRequired] App entering foreground - rechecking auth")
            recheckAuthState()
        }
    }

    private func startPeriodicRecheck() {
        // Only start periodic check if we have a session to check
        // Check every 30 seconds instead of 2 seconds to avoid spam
        recheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            // Only recheck if we might have a session
            if case .unauthenticated = authManager.authState {
                // Don't recheck when unauthenticated
            } else {
                recheckAuthState()
            }
        }
    }
    
    private func stopPeriodicRecheck() {
        recheckTimer?.invalidate()
        recheckTimer = nil
    }
    
    private func recheckAuthState() {
        Task {
            do {
                print("[AuthenticationRequired] Rechecking auth state...")
                try await authManager.refreshSession()
                print("[AuthenticationRequired] Session refresh successful")
            } catch {
                print("[AuthenticationRequired] Session refresh failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - View Extension
extension View {
    func requiresAuthentication() -> some View {
        self.modifier(AuthenticationRequired())
    }
}

// MARK: - Environment Key for Auth Manager
private struct AuthManagerKey: EnvironmentKey {
    static let defaultValue: AuthenticationManager = AuthenticationManager.shared
}

extension EnvironmentValues {
    var authManager: AuthenticationManager {
        get { self[AuthManagerKey.self] }
        set { self[AuthManagerKey.self] = newValue }
    }
}
