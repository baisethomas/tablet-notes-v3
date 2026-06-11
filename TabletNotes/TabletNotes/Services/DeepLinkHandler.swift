import Foundation
import SwiftUI
import Supabase

@MainActor
class DeepLinkHandler: ObservableObject {
    @Published var shouldShowVerificationSuccess = false
    @Published var shouldShowPasswordReset = false
    
    func handleURL(_ url: URL) {
        print("[DeepLinkHandler] Received URL: \(url)")
        
        guard url.scheme == "tabletnotes" else {
            print("[DeepLinkHandler] Invalid scheme: \(url.scheme ?? "nil")")
            return
        }
        
        guard url.host == "auth" else {
            print("[DeepLinkHandler] Invalid host: \(url.host ?? "nil")")
            return
        }
        
        // Handle different auth paths
        switch url.path {
        case "/callback":
            handleAuthCallback(url)
        case "/reset-password":
            handlePasswordResetLink(url)
        default:
            print("[DeepLinkHandler] Unknown path: \(url.path)")
        }
    }

    /// Handles the password-recovery link: establishes the recovery session
    /// from the link's code, then prompts the user for a new password.
    private func handlePasswordResetLink(_ url: URL) {
        print("[DeepLinkHandler] Handling password reset link")

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            print("[DeepLinkHandler] Password reset error: \(error)")
            return
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            print("[DeepLinkHandler] No recovery code found in reset link")
            return
        }

        Task {
            do {
                try await AuthenticationManager.shared.exchangeAuthCode(code)
                try await AuthenticationManager.shared.refreshSession()
                print("[DeepLinkHandler] Recovery session established, prompting for new password")
                shouldShowPasswordReset = true
            } catch {
                print("[DeepLinkHandler] Failed to establish recovery session: \(error)")
            }
        }
    }
    
    private func handleAuthCallback(_ url: URL) {
        print("[DeepLinkHandler] Handling auth callback")
        
        // Extract URL components
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            print("[DeepLinkHandler] No query items found")
            return
        }
        
        // Look for code, access_token, refresh_token, or error in the URL
        var authCode: String?
        var accessToken: String?
        var refreshToken: String?
        var error: String?
        
        for item in queryItems {
            switch item.name {
            case "code":
                authCode = item.value
            case "access_token":
                accessToken = item.value
            case "refresh_token":
                refreshToken = item.value
            case "error":
                error = item.value
            default:
                break
            }
        }
        
        if let error = error {
            print("[DeepLinkHandler] Auth error: \(error)")
            return
        }
        
        if let authCode = authCode {
            print("[DeepLinkHandler] Received auth code, exchanging for session")
            Task {
                await handleAuthCode(authCode)
            }
        } else if let accessToken = accessToken {
            print("[DeepLinkHandler] Received access token, processing session")
            Task {
                await handleAuthSuccess(accessToken: accessToken, refreshToken: refreshToken)
            }
        } else {
            print("[DeepLinkHandler] No auth code or access token found in callback")
        }
    }
    
    private func handleAuthCode(_ authCode: String) async {
        do {
            print("[DeepLinkHandler] Exchanging auth code for session")

            let authManager = AuthenticationManager.shared
            try await authManager.exchangeAuthCode(authCode)
            try await authManager.refreshSession()

            print("[DeepLinkHandler] Email verification successful via deep link")
            shouldShowVerificationSuccess = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.shouldShowVerificationSuccess = false
            }

        } catch {
            print("[DeepLinkHandler] Failed to exchange auth code: \(error)")
        }
    }
    
    private func handleAuthSuccess(accessToken: String, refreshToken: String?) async {
        do {
            // Get the auth manager and refresh the session
            let authManager = AuthenticationManager.shared
            try await authManager.refreshSession()
            
            print("[DeepLinkHandler] Authentication successful via deep link")
            shouldShowVerificationSuccess = true
            
            // Hide success message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.shouldShowVerificationSuccess = false
            }
            
        } catch {
            print("[DeepLinkHandler] Failed to authenticate via deep link: \(error)")
        }
    }
}