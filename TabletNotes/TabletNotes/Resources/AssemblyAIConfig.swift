import Foundation

// MARK: - AssemblyAI Configuration
// Primary live-token flow uses the backend token endpoint.
// This config is only for direct-token fallback in development/support scenarios.
struct AssemblyAIConfig {
    private static let placeholder = "YOUR_ASSEMBLYAI_API_KEY_HERE"

    // Order of precedence:
    // 1) Process environment (local builds/CI)
    // 2) Info.plist key (ASSEMBLYAI_API_KEY)
    // 3) Placeholder (treated as not configured)
    static var apiKey: String {
        let env = ProcessInfo.processInfo.environment["ASSEMBLYAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !env.isEmpty {
            return env
        }

        let plist = (Bundle.main.object(forInfoDictionaryKey: "ASSEMBLYAI_API_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !plist.isEmpty {
            return plist
        }

        return placeholder
    }

    static var isConfigured: Bool {
        let key = apiKey
        return !key.isEmpty && key != placeholder
    }
}
