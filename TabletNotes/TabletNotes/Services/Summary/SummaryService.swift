import Foundation
import Combine
import Supabase

class SummaryService: ObservableObject {
    private let summarySubject = CurrentValueSubject<String?, Never>(nil)
    let statusSubject = CurrentValueSubject<String, Never>("idle") // idle, pending, complete, failed
    var summaryPublisher: AnyPublisher<String?, Never> { summarySubject.eraseToAnyPublisher() }
    var statusPublisher: AnyPublisher<String, Never> { statusSubject.eraseToAnyPublisher() }
    private var cancellables = Set<AnyCancellable>()
    
    private let endpoint = "https://comfy-daffodil-7ecc55.netlify.app/api/summarize"
    private let refreshEndpoint = "https://comfy-daffodil-7ecc55.netlify.app/api/summarize-refresh"
    private let supabase: SupabaseClient
    
    // Refresh limits based on subscription tier
    private let refreshLimits: [String: Int] = [
        "free": 3,
        "pro": 10,
        "premium": 25
    ]
    
    init(supabase: SupabaseClient = SupabaseService.shared.client) {
        self.supabase = supabase
    }
    
    func generateSummary(for transcript: String, type: String) {
        print("[SummaryService] Called generateSummary with transcript length: \(transcript.count), type: \(type)")
        
        // Validate transcript content
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTranscript.count < 50 {
            print("[SummaryService] ERROR: Transcript too short (\(trimmedTranscript.count) chars)")
            statusSubject.send("failed")
            summarySubject.send("[Error] Transcript is too short for meaningful summarization. Please ensure the recording captured audio properly.")
            return
        }
        
        statusSubject.send("pending")
        summarySubject.send(nil)
        
        Task {
            do {
                // Get authentication token
                let session = try await supabase.auth.session
                
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
                    DispatchQueue.main.async {
                        self.statusSubject.send("failed")
                    }
                    return
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
                request.httpBody = httpBody
                request.timeoutInterval = 60.0 // Increase timeout to 60 seconds
                print("[SummaryService] Sending authenticated request to Netlify summarize endpoint...")
                let task = URLSession.shared.dataTask(with: request) { data, response, error in
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
                    }
                    return
                } else if httpResponse.statusCode >= 500 {
                    print("[SummaryService] ERROR: Server error \(httpResponse.statusCode)")
                    DispatchQueue.main.async {
                        self.statusSubject.send("failed")
                        self.summarySubject.send("[Error] Server error (\(httpResponse.statusCode)). Please try again later.")
                    }
                    return
                }
            }
            guard let data = data else {
                print("[SummaryService] ERROR: No data received from Netlify summarize endpoint")
                DispatchQueue.main.async {
                    self.statusSubject.send("failed")
                    self.summarySubject.send("[Error] No data received from Netlify summarize endpoint.")
                }
                return
            }
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[SummaryService] Netlify summarize response: \(jsonString.prefix(500))...")
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[SummaryService] ERROR: Failed to parse JSON response")
                DispatchQueue.main.async {
                    self.statusSubject.send("failed")
                    self.summarySubject.send("[Error] Failed to parse response from summarize endpoint.")
                }
                return
            }
            
            // Check if response has nested structure with success/data
            let summary: String
            if let success = json["success"] as? Bool, success,
               let data = json["data"] as? [String: Any],
               let summaryText = data["summary"] as? String {
                summary = summaryText
            } else if let summaryText = json["summary"] as? String {
                // Fallback to flat structure
                summary = summaryText
            } else {
                print("[SummaryService] ERROR: No summary found in response structure")
                DispatchQueue.main.async {
                    self.statusSubject.send("failed")
                    self.summarySubject.send("[Error] Invalid response format from summarize endpoint.")
                }
                return
            }
            print("[SummaryService] Summary content received (first 200 chars): \(summary.prefix(200))...")
            DispatchQueue.main.async {
                self.summarySubject.send(summary.trimmingCharacters(in: .whitespacesAndNewlines))
                self.statusSubject.send("complete")
            }
                }
                task.resume()
            } catch {
                print("[SummaryService] Authentication error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.statusSubject.send("failed")
                    self.summarySubject.send("[Error] Authentication failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func retrySummary(for transcript: String, type: String) {
        generateSummary(for: transcript, type: type)
    }
    
    func refreshSummary(for transcript: String, type: String) {
        print("[SummaryService] Called refreshSummary with transcript length: \(transcript.count), type: \(type)")
        
        // Validate transcript content
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTranscript.count < 50 {
            print("[SummaryService] ERROR: Transcript too short (\(trimmedTranscript.count) chars)")
            statusSubject.send("failed")
            summarySubject.send("[Error] Transcript is too short for meaningful summarization. Please ensure the recording captured audio properly.")
            return
        }
        
        statusSubject.send("pending")
        summarySubject.send(nil)
        
        Task {
            do {
                // Get authentication token
                let session = try await supabase.auth.session
                
                let requestBody: [String: Any] = [
                    "text": transcript,
                    "serviceType": type
                ]
                
                // Debug logging
                print("[SummaryService] Refresh request details:")
                print("- Transcript length: \(transcript.count) characters")
                print("- Service type: \(type)")
                
                guard let url = URL(string: refreshEndpoint),
                      let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
                    print("[SummaryService] ERROR: Failed to create refresh request body or URL")
                    DispatchQueue.main.async {
                        self.statusSubject.send("failed")
                    }
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
                request.httpBody = httpBody
                request.timeoutInterval = 60.0
                
                print("[SummaryService] Sending authenticated refresh request to Netlify...")
                let task = URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error = error {
                        print("[SummaryService] Refresh ERROR: \(error.localizedDescription)")
                        let errorMessage: String
                        if error.localizedDescription.contains("timeout") || error.localizedDescription.contains("timed out") {
                            errorMessage = "The summarization service is taking longer than expected. This often happens with longer transcripts. Please try again or contact support if the issue persists."
                        } else {
                            errorMessage = error.localizedDescription
                        }
                        DispatchQueue.main.async {
                            self.statusSubject.send("failed")
                            self.summarySubject.send("[Error] \(errorMessage)")
                        }
                        return
                    }
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        print("[SummaryService] Refresh HTTP status: \(httpResponse.statusCode)")
                        
                        // Handle rate limiting specifically
                        if httpResponse.statusCode == 429 {
                            print("[SummaryService] ERROR: Rate limit exceeded for refresh")
                            DispatchQueue.main.async {
                                self.statusSubject.send("failed")
                                self.summarySubject.send("[Error] You have reached your daily refresh limit. Please try again tomorrow or upgrade your subscription for more refreshes.")
                            }
                            return
                        }
                        
                        // Handle other HTTP error codes
                        if httpResponse.statusCode == 502 {
                            print("[SummaryService] ERROR: 502 Bad Gateway - Function timeout")
                            DispatchQueue.main.async {
                                self.statusSubject.send("failed")
                                self.summarySubject.send("[Error] The summarization service timed out. This is common with longer transcripts. Please try again with a shorter transcript or contact support.")
                            }
                            return
                        } else if httpResponse.statusCode >= 500 {
                            print("[SummaryService] ERROR: Server error \(httpResponse.statusCode)")
                            DispatchQueue.main.async {
                                self.statusSubject.send("failed")
                                self.summarySubject.send("[Error] Server error (\(httpResponse.statusCode)). Please try again later.")
                            }
                            return
                        }
                    }
                    
                    guard let data = data else {
                        print("[SummaryService] ERROR: No data received from refresh endpoint")
                        DispatchQueue.main.async {
                            self.statusSubject.send("failed")
                            self.summarySubject.send("[Error] No data received from refresh endpoint.")
                        }
                        return
                    }
                    
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("[SummaryService] Refresh response: \(jsonString.prefix(500))...")
                    }
                    
                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        print("[SummaryService] ERROR: Failed to parse JSON response")
                        DispatchQueue.main.async {
                            self.statusSubject.send("failed")
                            self.summarySubject.send("[Error] Failed to parse response from refresh endpoint.")
                        }
                        return
                    }
                    
                    // Check if response has nested structure with success/data
                    let summary: String
                    if let success = json["success"] as? Bool, success,
                       let data = json["data"] as? [String: Any],
                       let summaryText = data["summary"] as? String {
                        summary = summaryText
                    } else if let summaryText = json["summary"] as? String {
                        // Fallback to flat structure
                        summary = summaryText
                    } else {
                        print("[SummaryService] ERROR: No summary found in refresh response structure")
                        DispatchQueue.main.async {
                            self.statusSubject.send("failed")
                            self.summarySubject.send("[Error] Invalid response format from refresh endpoint.")
                        }
                        return
                    }
                    
                    print("[SummaryService] Refreshed summary content received (first 200 chars): \(summary.prefix(200))...")
                    DispatchQueue.main.async {
                        self.summarySubject.send(summary.trimmingCharacters(in: .whitespacesAndNewlines))
                        self.statusSubject.send("complete")
                    }
                }
                task.resume()
            } catch {
                print("[SummaryService] Authentication error for refresh: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.statusSubject.send("failed")
                    self.summarySubject.send("[Error] Authentication failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func canRefreshSummary(currentRefreshCount: Int, userTier: String) -> Bool {
        let limit = refreshLimits[userTier] ?? refreshLimits["free"]!
        return currentRefreshCount < limit
    }
    
    func getRemainingRefreshes(currentRefreshCount: Int, userTier: String) -> Int {
        let limit = refreshLimits[userTier] ?? refreshLimits["free"]!
        return max(0, limit - currentRefreshCount)
    }
    
    // Fallback method for when primary service fails
    func generateBasicSummary(for transcript: String, type: String) {
        print("[SummaryService] Generating basic summary as fallback")
        statusSubject.send("pending")
        
        // Create a basic extractive summary
        let sentences = transcript.components(separatedBy: ". ")
        let wordCount = transcript.components(separatedBy: " ").count
        
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
            self.summarySubject.send(basicSummary)
            self.statusSubject.send("complete")
        }
    }
}