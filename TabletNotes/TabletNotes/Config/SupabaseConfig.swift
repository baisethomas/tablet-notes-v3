import Foundation

struct SupabaseConfig {
    // MARK: - Configuration Properties
    static var url: String {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let result = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let supabaseURL = result["Supabase_URL"] as? String else {
            fatalError("Supabase URL not found in Config.plist. Please ensure the file is in the project and has the 'Supabase_URL' key.")
        }
        return supabaseURL
    }
    
    // Legacy interface compatibility
    static var projectURL: String {
        return url
    }
    
    static var anonKey: String {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let result = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let anonKey = result["Supabase_Anon_Key"] as? String else {
            fatalError("Supabase Anon Key not found in Config.plist. Please ensure the file is in the project and has the 'Supabase_Anon_Key' key.")
        }
        return anonKey
    }
    
    // MARK: - Validation
    static func validateConfig() -> Bool {
        guard !anonKey.isEmpty,
              anonKey.starts(with: "eyJ"),
              anonKey.count > 100,
              URL(string: url) != nil else {
            print("❌ Invalid Supabase configuration")
            return false
        }
        
        print("✅ Supabase configuration appears valid")
        print("📍 Project URL: \(url)")
        print("🔑 API Key length: \(anonKey.count)")
        print("🔑 API Key prefix: \(String(anonKey.prefix(20)))...")
        
        return true
    }
}