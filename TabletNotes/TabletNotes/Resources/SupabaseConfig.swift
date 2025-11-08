import Foundation

// MARK: - Supabase Configuration
// This file contains configuration for the Supabase backend service
// To use this service, you need to have a Supabase project set up
// API keys are stored in Config.plist (not committed to version control)

struct SupabaseConfig {
    // MARK: - Configuration Loading
    
    private static func loadConfigValue(for key: String) -> String {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let value = plist[key] as? String else {
            fatalError("❌ Failed to load \(key) from Config.plist. Please copy Config.plist.example to Config.plist and fill in your API keys.")
        }
        
        // Check if placeholder values are still present
        if value.contains("YOUR_") || value.isEmpty {
            fatalError("❌ \(key) is not configured in Config.plist. Please add your API key.")
        }
        
        return value
    }
    
    // MARK: - Supabase Configuration

    // Your Supabase project URL (loaded from Config.plist)
    static var projectURL: String {
        return loadConfigValue(for: "SupabaseProjectURL")
    }

    // Alternative URL property for compatibility
    static var url: String {
        return projectURL
    }

    // Your Supabase anonymous key (loaded from Config.plist)
    static var anonKey: String {
        return loadConfigValue(for: "SupabaseAnonKey")
    }

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