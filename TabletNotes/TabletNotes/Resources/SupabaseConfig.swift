import Foundation

// MARK: - Supabase Configuration
// This file contains configuration for the Supabase backend service
// To use this service, you need to have a Supabase project set up

struct SupabaseConfig {
    // MARK: - Supabase Configuration

    // Your Supabase project URL
    static let projectURL = "https://ubghnmenxbhhlpxvypea.supabase.co"

    // Alternative URL property for compatibility
    static let url = projectURL

    // Your Supabase anonymous key
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InViZ2hubWVueGJoaGxweHZ5cGVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA0NTgzMzMsImV4cCI6MjA2NjAzNDMzM30.gAzL8N2vXA8FhcAIFR0gKV6K7WS0_WCnMyINOiXcDfs"

    // MARK: - Configuration Validation

    /// Validates that the Supabase configuration has been properly set up
    static func validateConfig() -> Bool {
        // Check if URL is valid
        guard !projectURL.isEmpty,
              URL(string: projectURL) != nil,
              projectURL.contains("supabase.co") else {
            print("❌ Supabase URL is not configured or invalid")
            return false
        }

        // Check if anonymous key is configured and looks like a JWT
        guard !anonKey.isEmpty,
              anonKey.contains(".") else {
            print("❌ Supabase anonymous key is not configured")
            return false
        }

        print("✅ Supabase configuration is valid")
        return true
    }

    // MARK: - Configuration Status

    /// Returns true if the configuration has been properly set up
    static var isConfigured: Bool {
        return validateConfig()
    }
}

// MARK: - Configuration Status
/*
 ✅ Supabase is fully configured and ready to use!

 Project: ubghnmenxbhhlpxvypea.supabase.co
 Features enabled:
 - User authentication (sign up, sign in, email verification)
 - Cross-device sermon syncing
 - User data backup and restore
 - Real-time features (if configured in Supabase)

 Note: The anon key is safe to use in client-side code as it has restricted permissions.
 Never put your service_role key in client-side code.
 */