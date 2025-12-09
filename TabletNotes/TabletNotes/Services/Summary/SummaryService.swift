import Foundation
import Combine
import Supabase

class SummaryService: ObservableObject, SummaryServiceProtocol {
    static let shared = SummaryService()

    private let titleSubject = CurrentValueSubject<String?, Never>(nil)
    private let summarySubject = CurrentValueSubject<String?, Never>(nil)
    let statusSubject = CurrentValueSubject<String, Never>("idle") // idle, pending, complete, failed
    var titlePublisher: AnyPublisher<String?, Never> { titleSubject.eraseToAnyPublisher() }
    var summaryPublisher: AnyPublisher<String?, Never> { summarySubject.eraseToAnyPublisher() }
    var statusPublisher: AnyPublisher<String, Never> { statusSubject.eraseToAnyPublisher() }
    private let errorSubject = CurrentValueSubject<Error?, Never>(nil)
    var errorPublisher: AnyPublisher<Error?, Never> { errorSubject.eraseToAnyPublisher() }
    private var cancellables = Set<AnyCancellable>()
    private var lastTranscript: String?
    private var lastType: String?
    private var currentTask: URLSessionDataTask?
    private var isRequestInProgress = false

    private enum SummaryError: LocalizedError {
        case transcriptTooShort(Int)
        case invalidRequest
        case network(String)
        case server(Int)
        case noData
        case parseFailure
        case auth(String)

        var errorDescription: String? {
            switch self {
            case .transcriptTooShort(let count):
                return "Transcript too short (\(count) chars)"
            case .invalidRequest:
                return "Failed to create summarize request"
            case .network(let message):
                return message
            case .server(let code):
                return "Server error (\(code))"
            case .noData:
                return "No data received from summarize endpoint"
            case .parseFailure:
                return "Failed to parse summarize response"
            case .auth(let message):
                return "Authentication failed: \(message)"
            }
        }
    }
    
    private let endpoint = "https://comfy-daffodil-7ecc55.netlify.app/api/summarize"
    private let supabase: SupabaseClient

    private init(supabase: SupabaseClient = SupabaseService.shared.client) {
        self.supabase = supabase
    }

    // Helper function to get auth token with automatic refresh
    private func getAuthToken() async throws -> String {
        do {
            let session = try await supabase.auth.session
            return session.accessToken
        } catch {
            // Token might be expired, try to refresh
            print("[SummaryService] Session expired or invalid, attempting to refresh token...")
            do {
                let refreshedSession = try await supabase.auth.refreshSession()
                print("[SummaryService] Token refreshed successfully")
                return refreshedSession.accessToken
            } catch {
                print("[SummaryService] Token refresh failed: \(error.localizedDescription)")
                throw SummaryError.auth("Authentication failed. Please sign in again.")
            }
        }
    }

    func generateSummary(for transcript: String, type: String) {
        print("[SummaryService] Called generateSummary with transcript length: \(transcript.count), type: \(type)")

        // If a request is in progress, check if it's for the same content
        if isRequestInProgress {
            // If it's the same transcript, let the current request complete (observers will get the result)
            if lastTranscript == transcript && lastType == type {
                print("[SummaryService] ℹ️ Request already in progress for same content, continuing...")
                return
            }

            // Different transcript - cancel the old request and start new one
            print("[SummaryService] ⚠️ Cancelling previous request to process new transcript")
            currentTask?.cancel()
            currentTask = nil
            isRequestInProgress = false
        }

        lastTranscript = transcript
        lastType = type
        
        // Validate transcript content
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTranscript.count < 50 {
            print("[SummaryService] ERROR: Transcript too short (\(trimmedTranscript.count) chars)")
            DispatchQueue.main.async {
                self.statusSubject.send("failed")
                self.summarySubject.send("[Error] Transcript is too short for meaningful summarization. Please ensure the recording captured audio properly.")
                self.errorSubject.send(SummaryError.transcriptTooShort(trimmedTranscript.count))
            }
            return
        }
        
        // Reset state before starting new request
        DispatchQueue.main.async {
            self.statusSubject.send("pending")
            self.titleSubject.send(nil)
            self.summarySubject.send(nil)
            self.errorSubject.send(nil)
        }

        // Mark request as in progress
        isRequestInProgress = true

        Task {
            do {
                // Get authentication token with automatic refresh
                let accessToken = try await getAuthToken()

                let requestBody: [String: Any] = [
                    "text": transcript,
                    "serviceType": type
                ]

                // Debug logging
                print("[SummaryService] Request details:")
                print("- Transcript length: \(transcript.count) characters")
                print("- Service type: \(type)")
                print("- First 200 chars: \(String(transcript.prefix(200)))")
                if transcript.count > 200 {
                    print("- Last 200 chars: \(String(transcript.suffix(200)))")
                }
                guard let url = URL(string: endpoint),
                      let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
                    print("[SummaryService] ERROR: Failed to create request body or URL")
                    self.isRequestInProgress = false
                    DispatchQueue.main.async {
                        self.statusSubject.send("failed")
                        self.errorSubject.send(SummaryError.invalidRequest)
                    }
                    return
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.httpBody = httpBody
                request.timeoutInterval = 60.0 // Increase timeout to 60 seconds
                print("[SummaryService] Sending authenticated request to Netlify summarize endpoint...")
                let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                    print("[SummaryService] 🎯 Completion handler called! hasData=\(data != nil), hasResponse=\(response != nil), hasError=\(error != nil)")
                    guard let self = self else {
                        print("[SummaryService] ⚠️ self is nil in completion handler")
                        return
                    }

                    // Ensure request flag is reset when complete
                    defer { self.isRequestInProgress = false }

                    if let error = error {
                        print("[SummaryService] ERROR: \(error.localizedDescription)")
                        let errorMessage: String
                        if error.localizedDescription.contains("timeout") || error.localizedDescription.contains("timed out") {
                            errorMessage = "The summarization service is taking longer than expected. This often happens with longer transcripts. Please try again or contact support if the issue persists."
                        } else {
                            errorMessage = error.localizedDescription
                        }
                        DispatchQueue.main.async {
                            self.statusSubject.send("failed")
                            self.summarySubject.send("[Error] \(errorMessage)")
                            self.errorSubject.send(SummaryError.network(errorMessage))
                        }
                        return
                    }
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        print("[SummaryService] Netlify summarize HTTP status: \(httpResponse.statusCode)")
                        
                        // Handle specific HTTP error codes
                        if httpResponse.statusCode == 502 {
                            print("[SummaryService] ERROR: 502 Bad Gateway - Function timeout")
                            DispatchQueue.main.async {
                                self.statusSubject.send("failed")
                                self.summarySubject.send("[Error] The summarization service timed out. This is common with longer transcripts. Please try again with a shorter transcript or contact support.")
                                self.errorSubject.send(SummaryError.server(502))
                            }
                            return
                        } else if httpResponse.statusCode >= 500 {
                            print("[SummaryService] ERROR: Server error \(httpResponse.statusCode)")
                            DispatchQueue.main.async {
                                self.statusSubject.send("failed")
                                self.summarySubject.send("[Error] Server error (\(httpResponse.statusCode)). Please try again later.")
                                self.errorSubject.send(SummaryError.server(httpResponse.statusCode))
                            }
                            return
                        }
                    }
                    
                    guard let data = data else {
                        print("[SummaryService] ERROR: No data received from Netlify summarize endpoint")
                        DispatchQueue.main.async {
                            self.statusSubject.send("failed")
                            self.summarySubject.send("[Error] No data received from Netlify summarize endpoint.")
                            self.errorSubject.send(SummaryError.noData)
                        }
                        return
                    }
                    
                    // Log full response for debugging
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("[SummaryService] Netlify summarize response (full): \(jsonString)")
                        print("[SummaryService] Response length: \(jsonString.count) characters")
                    }
                    
                    // Parse JSON response
                    let json: [String: Any]
                    do {
                        guard let parsedJson = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            print("[SummaryService] ERROR: Response is not a dictionary")
                            DispatchQueue.main.async {
                                self.statusSubject.send("failed")
                                self.summarySubject.send("[Error] Invalid response format from summarize endpoint.")
                                self.errorSubject.send(SummaryError.parseFailure)
                            }
                            return
                        }
                        json = parsedJson
                        print("[SummaryService] Successfully parsed JSON response")
                        print("[SummaryService] JSON keys: \(json.keys.joined(separator: ", "))")
                    } catch {
                        print("[SummaryService] ERROR: Failed to parse JSON response: \(error.localizedDescription)")
                        if let jsonString = String(data: data, encoding: .utf8) {
                            print("[SummaryService] Raw response: \(jsonString)")
                        }
                        DispatchQueue.main.async {
                            self.statusSubject.send("failed")
                            self.summarySubject.send("[Error] Failed to parse response from summarize endpoint.")
                            self.errorSubject.send(SummaryError.parseFailure)
                        }
                        return
                    }
                    
                    // Check if response has nested structure with success/data
                    let summary: String
                    let title: String?
                    
                    // First try: Check for nested structure { success: true, data: { summary, title } }
                    if let success = json["success"] as? Bool {
                        print("[SummaryService] Found 'success' key: \(success)")
                        if success {
                            if let dataDict = json["data"] as? [String: Any] {
                                print("[SummaryService] Found 'data' key with keys: \(dataDict.keys.joined(separator: ", "))")
                                if let summaryText = dataDict["summary"] as? String {
                                    summary = summaryText
                                    title = dataDict["title"] as? String
                                    print("[SummaryService] ✅ Successfully extracted summary from nested structure")
                                    print("[SummaryService] Summary length: \(summary.count) characters")
                                    if let extractedTitle = title {
                                        print("[SummaryService] Title: \(extractedTitle)")
                                    } else {
                                        print("[SummaryService] ⚠️ No title found in data object")
                                    }
                                } else {
                                    print("[SummaryService] ERROR: 'data' object exists but 'summary' key is missing or not a string")
                                    print("[SummaryService] Available keys in 'data': \(dataDict.keys.joined(separator: ", "))")
                                    DispatchQueue.main.async {
                                        self.statusSubject.send("failed")
                                        self.summarySubject.send("[Error] Invalid response format: summary field missing.")
                                        self.errorSubject.send(SummaryError.parseFailure)
                                    }
                                    return
                                }
                            } else {
                                print("[SummaryService] ERROR: 'success' is true but 'data' is missing or not a dictionary")
                                print("[SummaryService] Available top-level keys: \(json.keys.joined(separator: ", "))")
                                DispatchQueue.main.async {
                                    self.statusSubject.send("failed")
                                    self.summarySubject.send("[Error] Invalid response format: data field missing.")
                                    self.errorSubject.send(SummaryError.parseFailure)
                                }
                                return
                            }
                        } else {
                            print("[SummaryService] ERROR: 'success' key is false")
                            if let errorMessage = json["message"] as? String {
                                print("[SummaryService] Error message: \(errorMessage)")
                            }
                            DispatchQueue.main.async {
                                self.statusSubject.send("failed")
                                self.summarySubject.send("[Error] Summary generation failed on server.")
                                self.errorSubject.send(SummaryError.parseFailure)
                            }
                            return
                        }
                    } else if let summaryText = json["summary"] as? String {
                        // Fallback: Check for flat structure { summary, title }
                        print("[SummaryService] ⚠️ Using fallback: flat structure detected")
                        summary = summaryText
                        title = json["title"] as? String
                        print("[SummaryService] ✅ Successfully extracted summary from flat structure")
                    } else {
                        // No valid structure found
                        print("[SummaryService] ERROR: No valid response structure found")
                        print("[SummaryService] Available keys: \(json.keys.joined(separator: ", "))")
                        if let errorMessage = json["error"] as? String {
                            print("[SummaryService] Error message: \(errorMessage)")
                        }
                        if let message = json["message"] as? String {
                            print("[SummaryService] Message: \(message)")
                        }
                        DispatchQueue.main.async {
                            self.statusSubject.send("failed")
                            self.summarySubject.send("[Error] Invalid response format from summarize endpoint.")
                            self.errorSubject.send(SummaryError.parseFailure)
                        }
                        return
                    }
                    
                    // Validate summary content
                    if summary.isEmpty {
                        print("[SummaryService] ERROR: Summary is empty")
                        DispatchQueue.main.async {
                            self.statusSubject.send("failed")
                            self.summarySubject.send("[Error] Received empty summary from server.")
                            self.errorSubject.send(SummaryError.parseFailure)
                        }
                        return
                    }
                    
                    print("[SummaryService] ✅ Summary content received (first 200 chars): \(summary.prefix(200))...")
                    if let extractedTitle = title {
                        print("[SummaryService] ✅ Title received: \(extractedTitle)")
                    } else {
                        print("[SummaryService] ⚠️ No title provided (will use default)")
                    }
                    DispatchQueue.main.async {
                        self.titleSubject.send(title?.trimmingCharacters(in: .whitespacesAndNewlines))
                        self.summarySubject.send(summary.trimmingCharacters(in: .whitespacesAndNewlines))
                        self.statusSubject.send("complete")
                        self.errorSubject.send(nil)
                    }
                }
                self.currentTask = task
                task.resume()
            } catch {
                print("[SummaryService] Authentication error: \(error.localizedDescription)")
                self.isRequestInProgress = false
                DispatchQueue.main.async {
                    self.statusSubject.send("failed")
                    self.summarySubject.send("[Error] Authentication failed: \(error.localizedDescription)")
                    self.errorSubject.send(SummaryError.auth(error.localizedDescription))
                }
            }
        }
    }

    func retrySummary() {
        guard let transcript = lastTranscript, let type = lastType else {
            print("[SummaryService] Cannot retry: No previous transcript or type stored")
            return
        }
        print("[SummaryService] Retrying summary generation...")
        generateSummary(for: transcript, type: type)
    }

    // Convenience method (not in protocol)
    func retrySummary(for transcript: String, type: String) {
        print("[SummaryService] Retrying summary generation with provided transcript and type")
        // Explicitly clear error state before retrying
        DispatchQueue.main.async {
            self.errorSubject.send(nil)
        }
        lastTranscript = transcript
        lastType = type
        generateSummary(for: transcript, type: type)
    }
    
    // Fallback method for when primary service fails
    func generateBasicSummary(for transcript: String, type: String) {
        print("[SummaryService] Generating basic summary as fallback")
        statusSubject.send("pending")

        // Create a basic extractive summary
        let sentences = transcript.components(separatedBy: ". ")
        let wordCount = transcript.components(separatedBy: " ").count

        // Generate a basic title
        let basicTitle: String
        if let firstSentence = sentences.first?.trimmingCharacters(in: .whitespacesAndNewlines), !firstSentence.isEmpty {
            // Use first sentence, truncated if needed
            let truncated = firstSentence.prefix(60)
            basicTitle = String(truncated) + (firstSentence.count > 60 ? "..." : "")
        } else {
            basicTitle = "\(type) Summary"
        }

        let basicSummary: String
        if wordCount < 100 {
            basicSummary = "Brief \(type.lowercased()): \(transcript)"
        } else {
            // Take first few sentences and key phrases
            let firstSentences = Array(sentences.prefix(3)).joined(separator: ". ")
            let keyPoints = sentences.filter { sentence in
                let lowercased = sentence.lowercased()
                return lowercased.contains("god") || lowercased.contains("jesus") ||
                       lowercased.contains("christ") || lowercased.contains("lord") ||
                       lowercased.contains("scripture") || lowercased.contains("bible") ||
                       lowercased.contains("prayer") || lowercased.contains("faith")
            }

            let keyPointsText = Array(keyPoints.prefix(2)).joined(separator: ". ")
            basicSummary = """
            **\(type) Summary**

            **Opening:** \(firstSentences)

            **Key Points:** \(keyPointsText.isEmpty ? "Main themes focus on faith and spiritual growth." : keyPointsText)

            **Note:** This is a basic summary generated offline. For a more detailed AI-powered summary, please try again when the summarization service is available.
            """
        }

        DispatchQueue.main.async {
            self.titleSubject.send(basicTitle)
            self.summarySubject.send(basicSummary)
            self.statusSubject.send("complete")
        }
    }
}

