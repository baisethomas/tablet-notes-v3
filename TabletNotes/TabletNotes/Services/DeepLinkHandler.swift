import Foundation
import SwiftUI
import Supabase

@MainActor
class DeepLinkHandler: ObservableObject {
    @Published var shouldShowVerificationSuccess = false
    
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
        default:
            print("[DeepLinkHandler] Unknown path: \(url.path)")
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
            
            // Get the Supabase client from the auth service
            let authManager = AuthenticationManager.shared
            
            // Access the private supabase client through the auth service
            // We need to create a new client instance for this operation
            let supabase = SupabaseClient(
                supabaseURL: URL(string: SupabaseConfig.projectURL)!,
                supabaseKey: SupabaseConfig.anonKey
            )
            
            // Exchange the code for a session
            let session = try await supabase.auth.exchangeCodeForSession(authCode: authCode)
            
            print("[DeepLinkHandler] Successfully exchanged code for session")
            print("[DeepLinkHandler] User ID: \(session.user.id)")
            
            // Now refresh the auth manager session
            try await authManager.refreshSession()
            
            print("[DeepLinkHandler] Email verification successful via deep link")
            shouldShowVerificationSuccess = true
            
            // Hide success message after 3 seconds
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