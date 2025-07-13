import Foundation

enum SupabaseConfig {
    static var url: String {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let result = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let supabaseURL = result["Supabase_URL"] as? String else {
            fatalError("Supabase URL not found in Config.plist. Please ensure the file is in the project and has the 'Supabase_URL' key.")
        }
        return supabaseURL
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
}