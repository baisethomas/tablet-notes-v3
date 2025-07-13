import Foundation

enum AssemblyAIConfig {
    static let netlifyBaseURL = "https://comfy-daffodil-7ecc55.netlify.app/.netlify/functions"
    
    // Note: AssemblyAI API key is now stored securely in Netlify environment variables
    // and accessed through the transcribe and transcribe-status functions
}