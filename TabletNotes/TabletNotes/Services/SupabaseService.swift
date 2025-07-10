import Foundation
import Supabase

class SupabaseService: SupabaseServiceProtocol {
    static let shared = SupabaseService()

    private let supabase: SupabaseClient
    
    // Public access to Supabase client for authentication
    var client: SupabaseClient {
        return supabase
    }

    init() {
        // NOTE: For a production app, it's better to load these from a Config.plist
        // that is not checked into version control, similar to how we handled the API keys before.
        let supabaseURL = URL(string: "https://ubghnmenxbhhlpxvypea.supabase.co")!
        let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InViZ2hubWVueGJoaGxweHZ5cGVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA0NTgzMzMsImV4cCI6MjA2NjAzNDMzM30.gAzL8N2vXA8FhcAIFR0gKV6K7WS0_WCnMyINOiXcDfs"
        
        self.supabase = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: supabaseKey)
    }

    // Netlify API endpoint
    private let apiBaseUrl = "https://comfy-daffodil-7ecc55.netlify.app"

    struct SignedUploadURLResponse: Codable {
        let uploadUrl: String
        let path: String
        let token: String
    }

    /// Fetches a secure, one-time URL for uploading a file.
    /// - Parameter fileName: The name of the file to be uploaded (e.g., "recording.m4a").
    /// - Returns: A tuple containing the signed URL for the upload and the file's permanent path in the bucket.
    func getSignedUploadURL(for fileName: String) async throws -> (uploadUrl: URL, path: String) {
        // Get authentication token
        let session = try await supabase.auth.session
        
        let url = URL(string: "\(apiBaseUrl)/api/generate-upload-url")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let body = ["fileName": fileName]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw URLError(.userAuthenticationRequired)
            }
            throw URLError(.badServerResponse)
        }

        let decodedResponse = try JSONDecoder().decode(SignedUploadURLResponse.self, from: data)
        guard let uploadUrl = URL(string: decodedResponse.uploadUrl) else {
            throw URLError(.badURL)
        }
        
        return (uploadUrl, decodedResponse.path)
    }

    /// Uploads the audio file from a local URL to the provided signed URL.
    /// - Parameters:
    ///   - localUrl: The URL of the audio file on the device.
    ///   - signedUploadUrl: The secure, one-time URL obtained from `getSignedUploadURL`.
    func uploadAudioFile(at localUrl: URL, to signedUploadUrl: URL) async throws {
        let audioData = try Data(contentsOf: localUrl)
        
        var request = URLRequest(url: signedUploadUrl)
        request.httpMethod = "PUT"
        request.setValue("audio/m4a", forHTTPHeaderField: "Content-Type") // Adjust if you use a different format

        let (_, response) = try await URLSession.shared.upload(for: request, from: audioData)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    /// Generic file upload method for protocol conformance
    func uploadFile(data: Data, to uploadUrl: URL) async throws {
        var request = URLRequest(url: uploadUrl)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.upload(for: request, from: data)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    /// Gets a signed download URL for a file
    func getSignedDownloadURL(for path: String) async throws -> URL {
        let url = URL(string: "\(apiBaseUrl)/api/generate-download-url")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Get authentication token
        let session = try await supabase.auth.session
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let body = ["path": path]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decodedResponse = try JSONDecoder().decode(SignedUploadURLResponse.self, from: data)
        guard let downloadUrl = URL(string: decodedResponse.uploadUrl) else {
            throw URLError(.badURL)
        }
        
        return downloadUrl
    }
    
    /// Updates user profile in Supabase
    func updateUserProfile(_ user: User) async throws {
        let url = URL(string: "\(apiBaseUrl)/api/update-profile")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Get authentication token
        let session = try await supabase.auth.session
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        // Create update payload
        let updateData: [String: Any] = [
            "id": user.id.uuidString,
            "subscription_tier": user.subscriptionTier,
            "subscription_status": user.subscriptionStatus,
            "subscription_expiry": user.subscriptionExpiry?.ISO8601Format() ?? NSNull(),
            "subscription_product_id": user.subscriptionProductId ?? NSNull(),
            "subscription_purchase_date": user.subscriptionPurchaseDate?.ISO8601Format() ?? NSNull(),
            "subscription_renewal_date": user.subscriptionRenewalDate?.ISO8601Format() ?? NSNull(),
            "monthly_recording_count": user.monthlyRecordingCount,
            "monthly_recording_minutes": user.monthlyRecordingMinutes,
            "current_storage_used_gb": user.currentStorageUsedGB,
            "monthly_export_count": user.monthlyExportCount,
            "last_usage_reset_date": user.lastUsageResetDate?.ISO8601Format() ?? NSNull()
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: updateData)

        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
} 
