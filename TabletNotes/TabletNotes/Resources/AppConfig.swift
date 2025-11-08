import Foundation

// MARK: - App Configuration
// This file contains shared configuration helpers for loading values from Config.plist
// All backend URLs and API keys should be loaded from Config.plist for environment-based configuration

struct AppConfig {
    // MARK: - Configuration Loading
    
    /// Loads a configuration value from Config.plist
    /// - Parameter key: The key to look up in Config.plist
    /// - Returns: The configuration value as a String
    /// - Note: This will fatalError if the key is missing or contains placeholder values
    private static func loadConfigValue(for key: String) -> String {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let value = plist[key] as? String else {
            fatalError("❌ Failed to load \(key) from Config.plist. Please copy Config.plist.example to Config.plist and fill in your configuration values.")
        }
        
        // Check if placeholder values are still present
        if value.contains("YOUR_") || value.isEmpty {
            fatalError("❌ \(key) is not configured in Config.plist. Please add your configuration value.")
        }
        
        return value
    }
    
    // MARK: - Netlify API Configuration
    
    /// Netlify API base URL (loaded from Config.plist)
    /// This is the base URL for all Netlify backend functions
    static var netlifyAPIBaseURL: String {
        return loadConfigValue(for: "NetlifyAPIBaseURL")
    }
    
    // MARK: - Configuration Validation
    
    /// Validates that the Netlify API configuration has been properly set up
    static func validateNetlifyConfig() -> Bool {
        guard !netlifyAPIBaseURL.isEmpty,
              URL(string: netlifyAPIBaseURL) != nil else {
            print("❌ Netlify API base URL is not configured or invalid")
            return false
        }
        
        print("✅ Netlify API configuration is valid")
        return true
    }
}

