import Foundation
import Combine
import Supabase
import FirebaseCore
import UIKit
#if canImport(GoogleSignIn)
@preconcurrency import GoogleSignIn
#endif

@MainActor
final class SupabaseAuthService: AuthServiceProtocol, ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var authState: AuthState = .loading
    @Published private(set) var currentUser: User? = nil
    
    // MARK: - Private Properties
    private let supabase: SupabaseClient
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Publishers
    var authStatePublisher: AnyPublisher<AuthState, Never> {
        $authState.eraseToAnyPublisher()
    }
    
    var currentUserPublisher: AnyPublisher<User?, Never> {
        $currentUser.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    init() {
        // Validate configuration first
        guard SupabaseConfig.validateConfig() else {
            fatalError("Invalid Supabase configuration. Please check SupabaseConfig.swift")
        }
        
        // Initialize Supabase client
        let supabaseURL = URL(string: SupabaseConfig.projectURL)!
        let supabaseKey = SupabaseConfig.anonKey
        
        self.supabase = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseKey
        )
        
        print("[SupabaseAuthService] Creating new SupabaseAuthService instance: \(ObjectIdentifier(self))")
        
        // Test connection
        Task {
            await testConnection()
        }
        
        setupAuthStateListener()
    }
    
    // MARK: - Authentication Methods
    
    func signUp(data: SignUpData) async throws -> User {
        print("[SupabaseAuthService] Starting sign up for email: \(data.email)")
        
        // Validate input
        if let validationError = data.validationError {
            throw validationError
        }
        
        do {
            // Create auth user with metadata and redirect URL
            let authResponse = try await supabase.auth.signUp(
                email: data.email,
                password: data.password,
                data: ["name": .string(data.name)],
                redirectTo: URL(string: "tabletnotes://auth/callback")
            )
            
            let authUser = authResponse.user
            
            // Wait a bit for the database trigger to complete, then ensure profile exists
            let newUser: User
            do {
                // Give the trigger time to complete
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                newUser = try await fetchUserProfile(authUser.id.uuidString)
                print("[SupabaseAuthService] Successfully fetched profile created by trigger")
            } catch {
                print("[SupabaseAuthService] Profile not found, ensuring completion: \(error.localizedDescription)")
                // Fallback: Ensure profile is complete using the database function
                try await supabase
                    .rpc("ensure_profile_complete", params: ["user_uuid": authUser.id.uuidString])
                    .execute()
                
                // Wait a bit more and try again
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                newUser = try await fetchUserProfile(authUser.id.uuidString)
                print("[SupabaseAuthService] Ensured profile completion for: \(newUser.name)")
            }
            
            // Update local state
            self.currentUser = newUser
            self.authState = .authenticated(newUser)
            
            print("[SupabaseAuthService] Sign up successful")
            return newUser
            
        } catch let error as AuthError {
            print("[SupabaseAuthService] Sign up failed: \(error.localizedDescription)")
            self.authState = .error(error)
            throw error
        } catch {
            print("[SupabaseAuthService] Sign up failed with error: \(error)")
            print("[SupabaseAuthService] Error description: \(error.localizedDescription)")
            print("[SupabaseAuthService] Error type: \(type(of: error))")
            if let nsError = error as NSError? {
                print("[SupabaseAuthService] NSError domain: \(nsError.domain)")
                print("[SupabaseAuthService] NSError code: \(nsError.code)")
                print("[SupabaseAuthService] NSError userInfo: \(nsError.userInfo)")
            }
            let authError = mapSupabaseError(error)
            self.authState = .error(authError)
            throw authError
        }
    }
    
    func signIn(email: String, password: String) async throws -> User {
        print("[SupabaseAuthService] Starting sign in for email: \(email) on instance: \(ObjectIdentifier(self))")
        
        guard !email.isEmpty && !password.isEmpty else {
            throw AuthError.invalidCredentials
        }
        
        do {
            // Authenticate with Supabase
            let authResponse = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            
            let authUser = authResponse.user
            
            // Fetch user profile with fallback to ensure completion
            let user = try await ensureProfileComplete(authUser.id.uuidString)
            
            // Update local state
            print("[SupabaseAuthService] Setting currentUser to: \(user.name)")
            self.currentUser = user
            print("[SupabaseAuthService] Setting authState to authenticated")
            self.authState = .authenticated(user)
            
            print("[SupabaseAuthService] Sign in successful")
            return user
            
        } catch let error as AuthError {
            print("[SupabaseAuthService] Sign in failed: \(error.localizedDescription)")
            self.authState = .error(error)
            throw error
        } catch {
            print("[SupabaseAuthService] Sign in failed: \(error.localizedDescription)")
            let authError = mapSupabaseError(error)
            self.authState = .error(authError)
            throw authError
        }
    }
    
    func signInWithSocial(provider: SocialAuthProvider) async throws -> User {
        print("[SupabaseAuthService] Starting social sign in with provider: \(provider.rawValue)")
        
        do {
            let session: Session
            switch provider {
            case .google:
                session = try await signInWithGoogleNative()
            case .apple:
                throw AuthError.unknownError(
                    "Apple Sign-In is handled natively in the app. Please use the Apple button."
                )
            }
            
            let user = try await ensureProfileComplete(session.user.id.uuidString)
            self.currentUser = user
            self.authState = .authenticated(user)
            
            print("[SupabaseAuthService] Social sign in successful for provider: \(provider.rawValue)")
            return user
        } catch {
            print("[SupabaseAuthService] Social sign in failed for provider \(provider.rawValue): \(error.localizedDescription)")
            let authError = mapSupabaseError(error)
            self.authState = .error(authError)
            throw authError
        }
    }
    
    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws -> User {
        print("[SupabaseAuthService] Completing native Apple sign in")
        
        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            
            let normalizedFullName = fullName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            
            if let normalizedFullName {
                _ = try? await supabase.auth.update(
                    user: UserAttributes(
                        data: [
                            "name": .string(normalizedFullName),
                            "full_name": .string(normalizedFullName)
                        ]
                    )
                )
            }
            
            var user = try await ensureProfileComplete(session.user.id.uuidString)
            
            let authEmail = session.user.email?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            let metadataName = session.user.userMetadata["full_name"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
                ?? session.user.userMetadata["name"]?.stringValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
            let fallbackName = displayNameFallback(fromEmail: authEmail)
            
            let resolvedName = normalizedFullName
                ?? metadataName
                ?? (isPlaceholderProfileName(user.name, userID: user.id) ? fallbackName : nil)
            let resolvedEmail = authEmail ?? user.email
            let nextName = resolvedName ?? user.name
            
            if nextName != user.name || resolvedEmail != user.email {
                let updatedUser = User(
                    id: user.id,
                    email: resolvedEmail,
                    name: nextName,
                    profileImageURL: user.profileImageURL,
                    createdAt: user.createdAt,
                    isEmailVerified: user.isEmailVerified,
                    subscriptionTier: user.subscriptionTier,
                    subscriptionStatus: user.subscriptionStatus,
                    subscriptionExpiry: user.subscriptionExpiry,
                    subscriptionProductId: user.subscriptionProductId,
                    subscriptionPurchaseDate: user.subscriptionPurchaseDate,
                    subscriptionRenewalDate: user.subscriptionRenewalDate,
                    monthlyRecordingCount: user.monthlyRecordingCount,
                    monthlyRecordingMinutes: user.monthlyRecordingMinutes,
                    currentStorageUsedGB: user.currentStorageUsedGB,
                    monthlyExportCount: user.monthlyExportCount,
                    lastUsageResetDate: user.lastUsageResetDate
                )
                try? await saveUserProfile(updatedUser)
                user = updatedUser
            }
            
            self.currentUser = user
            self.authState = .authenticated(user)
            
            print("[SupabaseAuthService] Native Apple sign in successful")
            return user
        } catch {
            print("[SupabaseAuthService] Native Apple sign in failed: \(error.localizedDescription)")
            let authError = mapSupabaseError(error)
            self.authState = .error(authError)
            throw authError
        }
    }
    
    func signOut() async throws {
        print("[SupabaseAuthService] Starting sign out")
        
        do {
            try await supabase.auth.signOut()
            
            // Update local state
            self.currentUser = nil
            self.authState = .unauthenticated
            
            print("[SupabaseAuthService] Sign out successful")
            
        } catch {
            print("[SupabaseAuthService] Sign out failed: \(error.localizedDescription)")
            let authError = mapSupabaseError(error)
            self.authState = .error(authError)
            throw authError
        }
    }
    
    func resetPassword(email: String) async throws {
        print("[SupabaseAuthService] Starting password reset for email: \(email)")
        
        guard !email.isEmpty && email.contains("@") else {
            throw AuthError.invalidCredentials
        }
        
        do {
            try await supabase.auth.resetPasswordForEmail(email)
            print("[SupabaseAuthService] Password reset email sent")
        } catch {
            print("[SupabaseAuthService] Password reset failed: \(error.localizedDescription)")
            let authError = mapSupabaseError(error)
            throw authError
        }
    }
    
    func updateProfile(name: String, email: String?) async throws -> User {
        guard let currentUser = currentUser else {
            throw AuthError.userNotFound
        }
        
        print("[SupabaseAuthService] Updating profile")
        
        do {
            // Update auth email if provided
            if let newEmail = email, newEmail != currentUser.email {
                try await supabase.auth.update(
                    user: UserAttributes(email: newEmail)
                )
            }
            
            // Update user profile
            let updatedUser = User(
                id: currentUser.id,
                email: email ?? currentUser.email,
                name: name,
                profileImageURL: currentUser.profileImageURL,
                createdAt: currentUser.createdAt,
                isEmailVerified: currentUser.isEmailVerified,
                subscriptionTier: currentUser.subscriptionTier,
                subscriptionExpiry: currentUser.subscriptionExpiry
            )
            
            try await saveUserProfile(updatedUser)
            
            // Update local state
            self.currentUser = updatedUser
            self.authState = .authenticated(updatedUser)
            
            print("[SupabaseAuthService] Profile update successful")
            return updatedUser
            
        } catch {
            print("[SupabaseAuthService] Profile update failed: \(error.localizedDescription)")
            let authError = mapSupabaseError(error)
            throw authError
        }
    }
    
    func deleteAccount() async throws {
        guard let currentUser = currentUser else {
            throw AuthError.userNotFound
        }
        
        print("[SupabaseAuthService] Deleting account")
        
        do {
            // Delete user data from database
            try await deleteUserData(currentUser.id.uuidString)
            
            // Delete auth user
            // Note: Supabase doesn't have a direct delete user method
            // This typically requires admin API or server-side function
            
            // Update local state
            self.currentUser = nil
            self.authState = .unauthenticated
            
            print("[SupabaseAuthService] Account deletion successful")
            
        } catch {
            print("[SupabaseAuthService] Account deletion failed: \(error.localizedDescription)")
            let authError = mapSupabaseError(error)
            throw authError
        }
    }
    
    func refreshSession() async throws {
        print("[SupabaseAuthService] Refreshing session")
        
        do {
            let session = try await supabase.auth.refreshSession()
            
            let authUser = session.user
            let user = try await ensureProfileComplete(authUser.id.uuidString)
            self.currentUser = user
            self.authState = .authenticated(user)
            
        } catch {
            print("[SupabaseAuthService] Session refresh failed: \(error.localizedDescription)")
            self.currentUser = nil
            self.authState = .unauthenticated
            throw mapSupabaseError(error)
        }
    }
    
    // MARK: - Profile Management Methods
    
    func ensureProfileComplete() async throws -> User {
        print("[SupabaseAuthService] Ensuring profile completion")
        
        do {
            // Call the database function to ensure profile is complete
            try await supabase
                .rpc("ensure_profile_complete")
                .execute()
            
            // Get the current user ID from the session
            let session = try await supabase.auth.session
            let userId = session.user.id.uuidString
            
            // Fetch the updated profile
            return try await fetchUserProfile(userId)
        } catch {
            print("[SupabaseAuthService] Profile completion failed: \(error.localizedDescription)")
            throw mapSupabaseError(error)
        }
    }
    
    // MARK: - Testing Methods
    
    private func testConnection() async {
        do {
            print("[SupabaseAuthService] Testing connection...")
            // Test connection with a simple query
            try await supabase
                .from("profiles")
                .select("id")
                .limit(1)
                .execute()
            print("[SupabaseAuthService] Connection test successful.")
        } catch {
            print("[SupabaseAuthService] Connection test failed: \(error)")
            print("[SupabaseAuthService] Error details: \(error.localizedDescription)")
            // Don't fail app startup if connection test fails
        }
    }
    
    // MARK: - Private Methods
    
    private func setupAuthStateListener() {
        Task {
            for await (event, session) in supabase.auth.authStateChanges {
                await MainActor.run {
                    switch event {
                    case .signedIn:
                        if let user = session?.user {
                            Task {
                                do {
                                    let userProfile = try await self.ensureProfileComplete(user.id.uuidString)
                                    await MainActor.run {
                                        self.currentUser = userProfile
                                        self.authState = .authenticated(userProfile)
                                    }
                                } catch {
                                    await MainActor.run {
                                        self.authState = .error(.unknownError("Failed to fetch user profile"))
                                    }
                                }
                            }
                        }
                    case .signedOut:
                        self.currentUser = nil
                        self.authState = .unauthenticated
                    case .tokenRefreshed:
                        // Handle token refresh if needed
                        break
                    default:
                        break
                    }
                }
            }
        }
    }
    
    nonisolated func isAuthenticated() -> Bool {
        // TODO: Implement proper nonisolated authentication check
        return false
    }
    
    private func signInWithGoogleNative() async throws -> Session {
        #if canImport(GoogleSignIn)
        guard let rootViewController = topViewController() else {
            throw AuthError.unknownError("Unable to present Google Sign-In")
        }
        
        let clientID = try googleClientID()
        try validateGoogleURLSchemeConfiguration(clientID: clientID)
        let serverClientID = googleServerClientID()
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: clientID,
            serverClientID: serverClientID
        )
        
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
        
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.unknownError("Google Sign-In did not return an ID token")
        }
        
        return try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .google,
                idToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
        )
        #else
        throw AuthError.unknownError(
            "GoogleSignIn SDK is not linked. Add the GoogleSignIn Swift package and configure the Google URL scheme."
        )
        #endif
    }
    
    private func googleClientID() throws -> String {
        if
            let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
            !clientID.isEmpty
        {
            return clientID
        }
        
        if let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty {
            return clientID
        }
        
        if
            let gspPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
            let plist = NSDictionary(contentsOfFile: gspPath),
            let clientID = plist["CLIENT_ID"] as? String,
            !clientID.isEmpty
        {
            return clientID
        }
        
        throw AuthError.unknownError(
            "Missing Google client ID. Add GIDClientID to Info.plist or use a GoogleService-Info.plist that includes CLIENT_ID."
        )
    }
    
    private func googleServerClientID() -> String? {
        guard
            let serverClientID = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String,
            !serverClientID.isEmpty
        else {
            return nil
        }
        
        return serverClientID
    }
    
    private func validateGoogleURLSchemeConfiguration(clientID: String) throws {
        let expectedScheme = googleReversedClientIDScheme(from: clientID)
        let configuredSchemes = configuredURLSchemes()
        
        guard configuredSchemes.contains(expectedScheme) else {
            throw AuthError.unknownError(
                "Missing Google URL scheme '\(expectedScheme)'. Add it to Info.plist > CFBundleURLTypes before using Google Sign-In."
            )
        }
    }
    
    private func configuredURLSchemes() -> Set<String> {
        guard let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return []
        }
        
        let schemes = urlTypes
            .compactMap { $0["CFBundleURLSchemes"] as? [String] }
            .flatMap { $0 }
        
        return Set(schemes)
    }
    
    private func googleReversedClientIDScheme(from clientID: String) -> String {
        clientID
            .split(separator: ".")
            .reversed()
            .joined(separator: ".")
    }
    
    private func isPlaceholderProfileName(_ name: String, userID: UUID) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        
        let lowered = trimmed.lowercased()
        return lowered == "user"
            || lowered == userID.uuidString.lowercased()
            || lowered.hasPrefix("user ")
            || lowered.hasPrefix("user_")
    }
    
    private func displayNameFallback(fromEmail email: String?) -> String? {
        guard
            let email,
            let localPart = email.split(separator: "@").first,
            !localPart.isEmpty
        else {
            return nil
        }
        
        let formatted = localPart
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !formatted.isEmpty else { return nil }
        return formatted.capitalized
    }
    
    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
    
    private func ensureProfileComplete(_ userId: String) async throws -> User {
        print("[SupabaseAuthService] Ensuring profile completion for: \(userId)")
        
        do {
            // First try to fetch the profile
            return try await fetchUserProfile(userId)
        } catch {
            print("[SupabaseAuthService] Profile not found, ensuring completion: \(error.localizedDescription)")
            // If profile not found, ensure it's complete using the database function
            try await supabase
                .rpc("ensure_profile_complete", params: ["user_uuid": userId])
                .execute()
            
            return try await fetchUserProfile(userId)
        }
    }
    
    private func fetchUserProfile(_ userId: String) async throws -> User {
        print("[SupabaseAuthService] Fetching user profile for: \(userId)")
        
        do {
            let response: [SupabaseProfile] = try await supabase
                .from("profiles")
                .select("*")
                .eq("id", value: userId)
                .execute()
                .value
            
            print("[SupabaseAuthService] Query returned \(response.count) profiles")
            
            guard let profile = response.first else {
                print("[SupabaseAuthService] No profile found in database for user: \(userId)")
                
                // Let's also check what profiles exist
                let allProfiles: [SupabaseProfile] = try await supabase
                    .from("profiles")
                    .select("id, email, name")
                    .execute()
                    .value
                
                print("[SupabaseAuthService] Total profiles in database: \(allProfiles.count)")
                for profile in allProfiles.prefix(3) {
                    print("[SupabaseAuthService] Existing profile: \(profile.id) - \(profile.email)")
                }
                
                throw AuthError.userNotFound
            }
            
            print("[SupabaseAuthService] Successfully fetched profile for: \(profile.name)")
            print("[SupabaseAuthService] Subscription details - Tier: \(profile.subscriptionTier), Status: \(profile.subscriptionStatus), Expiry: \(profile.subscriptionExpiry?.description ?? "none")")
            return profile.toUser()
            
        } catch {
            print("[SupabaseAuthService] Failed to fetch user profile: \(error.localizedDescription)")
            throw mapSupabaseError(error)
        }
    }
    
    private func saveUserProfile(_ user: User) async throws {
        print("[SupabaseAuthService] Saving user profile: \(user.name)")
        
        do {
            try await supabase
                .from("profiles")
                .upsert(user.toSupabaseInsert())
                .execute()
            
            print("[SupabaseAuthService] Successfully saved profile for: \(user.name)")
            
        } catch {
            print("[SupabaseAuthService] Failed to save user profile: \(error.localizedDescription)")
            throw mapSupabaseError(error)
        }
    }
    
    private func deleteUserData(_ userId: String) async throws {
        print("[SupabaseAuthService] Deleting user data for: \(userId)")
        
        do {
            // Delete user profile (notification settings will be deleted via cascade)
            try await supabase
                .from("profiles")
                .delete()
                .eq("id", value: userId)
                .execute()
            
            print("[SupabaseAuthService] Successfully deleted user data for: \(userId)")
            
        } catch {
            print("[SupabaseAuthService] Failed to delete user data: \(error.localizedDescription)")
            throw mapSupabaseError(error)
        }
    }
    
    private func mapSupabaseError(_ error: Error) -> AuthError {
        // Map Supabase errors to our AuthError types
        let errorString = error.localizedDescription.lowercased()
        
        // Fallback to string-based error mapping
        if errorString.contains("invalid") || errorString.contains("unauthorized") {
            return .invalidCredentials
        } else if errorString.contains("network") || errorString.contains("connection") {
            return .networkError
        } else if errorString.contains("user not found") {
            return .userNotFound
        } else if errorString.contains("email") && errorString.contains("exists") {
            return .emailAlreadyExists
        } else if errorString.contains("password") && errorString.contains("weak") {
            return .weakPassword
        } else if errorString.contains("session") && errorString.contains("expired") {
            return .sessionExpired
        } else {
            return .unknownError(error.localizedDescription)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
