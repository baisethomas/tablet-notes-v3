import Foundation

struct SupabaseConfig {
    // MARK: - Configuration
    static let projectURL = "https://ubghnmenxbhhlpxvypea.supabase.co"
    
    // Updated with correct anon key from Supabase dashboard
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InViZ2hubWVueGJoaGxweHZ5cGVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA0NTgzMzMsImV4cCI6MjA2NjAzNDMzM30.gAzL8N2vXA8FhcAIFR0gKV6K7WS0_WCnMyINOiXcDfs"
    
    // MARK: - Validation
    static func validateConfig() -> Bool {
        guard !anonKey.isEmpty,
              anonKey.starts(with: "eyJ"),
              anonKey.count > 100,
              URL(string: projectURL) != nil else {
            print("❌ Invalid Supabase configuration")
            return false
        }
        
        print("✅ Supabase configuration appears valid")
        print("📍 Project URL: \(projectURL)")
        print("🔑 API Key length: \(anonKey.count)")
        print("🔑 API Key prefix: \(String(anonKey.prefix(20)))...")
        
        return true
    }
}