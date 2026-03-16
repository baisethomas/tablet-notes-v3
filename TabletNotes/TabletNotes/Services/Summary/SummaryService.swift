import Foundation
import Combine
import Supabase

class SummaryService: ObservableObject, SummaryServiceProtocol {
    static let shared = SummaryService()

    struct SummaryGenerationResult {
        let title: String?
        let summary: String
    }

    private let titleSubject = CurrentValueSubject<String?, Never>(nil)
    private let summarySubject = CurrentValueSubject<String?, Never>(nil)
    let statusSubject = CurrentValueSubject<String, Never>("idle") // idle, pending, complete, failed
    var titlePublisher: AnyPublisher<String?, Never> { titleSubject.eraseToAnyPublisher() }
    var summaryPublisher: AnyPublisher<String?, Never> { summarySubject.eraseToAnyPublisher() }
    var statusPublisher: AnyPublisher<String, Never> { statusSubject.eraseToAnyPublisher() }
    private let errorSubject = CurrentValueSubject<Error?, Never>(nil)
    var errorPublisher: AnyPublisher<Error?, Never> { errorSubject.eraseToAnyPublisher() }

    private var lastTranscript: String?
    private var lastType: String?
    private var currentRequestTask: Task<Void, Never>?
    private var currentRequestId: UUID?
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

        var userFacingMessage: String {
            switch self {
            case .transcriptTooShort:
                return "[Error] Transcript is too short for meaningful summarization. Please ensure the recording captured audio properly."
            case .invalidRequest:
                return "[Error] Failed to create summarize request."
            case .network(let message):
                return "[Error] \(message)"
            case .server(let code) where code == 502:
                return "[Error] The summarization service timed out. This is common with longer transcripts. Please try again with a shorter transcript or contact support."
            case .server(let code):
                return "[Error] Server error (\(code)). Please try again later."
            case .noData:
                return "[Error] No data received from Netlify summarize endpoint."
            case .parseFailure:
                return "[Error] Failed to parse response from summarize endpoint."
            case .auth(let message):
                return "[Error] Authentication failed: \(message)"
            }
        }
    }

    private let endpoint = "https://comfy-daffodil-7ecc55.netlify.app/api/summarize"
    private let supabase: SupabaseClient

    private init(supabase: SupabaseClient = SupabaseService.shared.client) {
        self.supabase = supabase
    }

    private func getAuthToken() async throws -> String {
        do {
            let session = try await supabase.auth.session
            return session.accessToken
        } catch {
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

    private func validateTranscript(_ transcript: String) throws -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTranscript.count >= 50 else {
            throw SummaryError.transcriptTooShort(trimmedTranscript.count)
        }
        return trimmedTranscript
    }

    private func makeRequest(
        transcript: String,
        type: String,
        accessToken: String
    ) throws -> URLRequest {
        guard let url = URL(string: endpoint) else {
            throw SummaryError.invalidRequest
        }

        let requestBody: [String: Any] = [
            "text": transcript,
            "serviceType": type
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw SummaryError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = httpBody
        request.timeoutInterval = 60.0
        return request
    }

    private func parseSummaryResponse(data: Data, response: URLResponse?) throws -> SummaryGenerationResult {
        if let httpResponse = response as? HTTPURLResponse {
            print("[SummaryService] Netlify summarize HTTP status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 502 {
                throw SummaryError.server(502)
            }

            if httpResponse.statusCode >= 500 {
                throw SummaryError.server(httpResponse.statusCode)
            }
        }

        guard !data.isEmpty else {
            throw SummaryError.noData
        }

        if let jsonString = String(data: data, encoding: .utf8) {
            print("[SummaryService] Netlify summarize response (full): \(jsonString)")
            print("[SummaryService] Response length: \(jsonString.count) characters")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SummaryError.parseFailure
        }

        print("[SummaryService] Successfully parsed JSON response")
        print("[SummaryService] JSON keys: \(json.keys.joined(separator: ", "))")

        let rawSummary: String
        let rawTitle: String?

        if let success = json["success"] as? Bool {
            print("[SummaryService] Found 'success' key: \(success)")

            guard success,
                  let dataDict = json["data"] as? [String: Any],
                  let summaryText = dataDict["summary"] as? String else {
                throw SummaryError.parseFailure
            }

            print("[SummaryService] Found 'data' key with keys: \(dataDict.keys.joined(separator: ", "))")
            rawSummary = summaryText
            rawTitle = dataDict["title"] as? String
        } else if let summaryText = json["summary"] as? String {
            print("[SummaryService] Using fallback flat summary structure")
            rawSummary = summaryText
            rawTitle = json["title"] as? String
        } else {
            throw SummaryError.parseFailure
        }

        let summary = rawSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            throw SummaryError.parseFailure
        }

        let title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[SummaryService] Summary length: \(summary.count) characters")
        if let title, !title.isEmpty {
            print("[SummaryService] Title: \(title)")
        } else {
            print("[SummaryService] No title returned from summarize endpoint")
        }

        return SummaryGenerationResult(
            title: title?.isEmpty == true ? nil : title,
            summary: summary
        )
    }

    private func mapRequestError(_ error: Error) -> Error {
        if error is CancellationError {
            return error
        }

        if let urlError = error as? URLError {
            if urlError.code == .cancelled {
                return CancellationError()
            }

            if urlError.code == .timedOut {
                return SummaryError.network(
                    "The summarization service is taking longer than expected. This often happens with longer transcripts. Please try again or contact support if the issue persists."
                )
            }

            return SummaryError.network(urlError.localizedDescription)
        }

        if error is SummaryError {
            return error
        }

        return SummaryError.network(error.localizedDescription)
    }

    private func beginPublishedRequest(
        transcript: String,
        type: String,
        requestId: UUID
    ) {
        lastTranscript = transcript
        lastType = type
        currentRequestId = requestId
        isRequestInProgress = true
        statusSubject.send("pending")
        titleSubject.send(nil)
        summarySubject.send(nil)
        errorSubject.send(nil)
    }

    private func finishPublishedRequest(requestId: UUID) {
        guard currentRequestId == requestId else { return }
        currentRequestTask = nil
        currentRequestId = nil
        isRequestInProgress = false
    }

    private func publishFailure(_ error: Error, requestId: UUID) {
        guard currentRequestId == requestId else { return }

        let summaryError = (error as? SummaryError) ?? SummaryError.network(error.localizedDescription)
        statusSubject.send("failed")
        summarySubject.send(summaryError.userFacingMessage)
        errorSubject.send(summaryError)
        finishPublishedRequest(requestId: requestId)
    }

    func generateSummaryResult(for transcript: String, type: String) async throws -> SummaryGenerationResult {
        let trimmedTranscript = try validateTranscript(transcript)
        let accessToken = try await getAuthToken()
        let request = try makeRequest(transcript: trimmedTranscript, type: type, accessToken: accessToken)

        print("[SummaryService] Request details:")
        print("- Transcript length: \(trimmedTranscript.count) characters")
        print("- Service type: \(type)")
        print("- First 200 chars: \(String(trimmedTranscript.prefix(200)))")
        if trimmedTranscript.count > 200 {
            print("- Last 200 chars: \(String(trimmedTranscript.suffix(200)))")
        }
        print("[SummaryService] Sending authenticated request to Netlify summarize endpoint...")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return try parseSummaryResponse(data: data, response: response)
        } catch {
            throw mapRequestError(error)
        }
    }

    func generateSummary(for transcript: String, type: String) {
        print("[SummaryService] Called generateSummary with transcript length: \(transcript.count), type: \(type)")

        if isRequestInProgress {
            if lastTranscript == transcript && lastType == type {
                print("[SummaryService] Request already in progress for identical content")
                return
            }

            print("[SummaryService] Cancelling previous summary request to start a new one")
            currentRequestTask?.cancel()
            currentRequestTask = nil
            currentRequestId = nil
            isRequestInProgress = false
        }

        let requestId = UUID()
        beginPublishedRequest(transcript: transcript, type: type, requestId: requestId)

        currentRequestTask = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await self.generateSummaryResult(for: transcript, type: type)
                guard !Task.isCancelled else { return }

                DispatchQueue.main.async {
                    guard self.currentRequestId == requestId else { return }
                    self.titleSubject.send(result.title)
                    self.summarySubject.send(result.summary)
                    self.statusSubject.send("complete")
                    self.errorSubject.send(nil)
                    self.finishPublishedRequest(requestId: requestId)
                }
            } catch is CancellationError {
                DispatchQueue.main.async {
                    self.finishPublishedRequest(requestId: requestId)
                }
            } catch {
                DispatchQueue.main.async {
                    self.publishFailure(error, requestId: requestId)
                }
            }
        }
    }

    func retrySummary() {
        guard let transcript = lastTranscript, let type = lastType else {
            print("[SummaryService] Cannot retry: No previous transcript or type stored")
            return
        }

        print("[SummaryService] Retrying summary generation")
        generateSummary(for: transcript, type: type)
    }

    func retrySummary(for transcript: String, type: String) {
        print("[SummaryService] Retrying summary generation with explicit transcript/type")
        generateSummary(for: transcript, type: type)
    }

    func generateBasicSummaryResult(for transcript: String, type: String) -> SummaryGenerationResult {
        let sentences = transcript.components(separatedBy: ". ")
        let wordCount = transcript.components(separatedBy: " ").count

        let basicTitle: String
        if let firstSentence = sentences.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !firstSentence.isEmpty {
            let truncated = firstSentence.prefix(60)
            basicTitle = String(truncated) + (firstSentence.count > 60 ? "..." : "")
        } else {
            basicTitle = "\(type) Summary"
        }

        let basicSummary: String
        if wordCount < 100 {
            basicSummary = "Brief \(type.lowercased()): \(transcript)"
        } else {
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

        return SummaryGenerationResult(title: basicTitle, summary: basicSummary)
    }

    func generateBasicSummary(for transcript: String, type: String) {
        print("[SummaryService] Generating basic summary as fallback")

        if isRequestInProgress {
            currentRequestTask?.cancel()
            currentRequestTask = nil
            currentRequestId = nil
            isRequestInProgress = false
        }

        let requestId = UUID()
        beginPublishedRequest(transcript: transcript, type: type, requestId: requestId)

        let result = generateBasicSummaryResult(for: transcript, type: type)
        titleSubject.send(result.title)
        summarySubject.send(result.summary)
        statusSubject.send("complete")
        errorSubject.send(nil)
        finishPublishedRequest(requestId: requestId)
    }
}
