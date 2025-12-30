//
//  ChatService.swift
//  TabletNotes
//
//  Created by Claude Code
//

import Foundation
import Combine
import SwiftData
import Supabase

class ChatService: ObservableObject, ChatServiceProtocol {
    static let shared = ChatService()

    // MARK: - Publishers
    private let messagesSubject = CurrentValueSubject<[ChatMessage], Never>([])
    private let loadingSubject = CurrentValueSubject<Bool, Never>(false)
    private let errorSubject = CurrentValueSubject<Error?, Never>(nil)
    private let suggestedQuestionsSubject = CurrentValueSubject<[String], Never>([])

    var messagesPublisher: AnyPublisher<[ChatMessage], Never> { messagesSubject.eraseToAnyPublisher() }
    var loadingPublisher: AnyPublisher<Bool, Never> { loadingSubject.eraseToAnyPublisher() }
    var errorPublisher: AnyPublisher<Error?, Never> { errorSubject.eraseToAnyPublisher() }
    var suggestedQuestionsPublisher: AnyPublisher<[String], Never> { suggestedQuestionsSubject.eraseToAnyPublisher() }

    // MARK: - Properties
    private let endpoint = "https://comfy-daffodil-7ecc55.netlify.app/api/chat"
    private let supabase: SupabaseClient
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Test Mode
    // Set to true to use mock responses for testing without backend
    private let useMockMode = false

    // MARK: - Errors
    enum ChatError: LocalizedError {
        case limitReached(remaining: Int)
        case rateLimitExceeded(retryAfter: Int)
        case invalidMessage
        case noContext
        case auth(String)
        case network(String)
        case server(Int)
        case parseFailure

        var errorDescription: String? {
            switch self {
            case .limitReached(let remaining):
                return "Question limit reached. You have \(remaining) questions remaining. Upgrade to Premium for unlimited questions."
            case .rateLimitExceeded(let retryAfter):
                let minutes = retryAfter / 60
                if minutes > 0 {
                    return "Too many requests. Please wait \(minutes) minute\(minutes == 1 ? "" : "s") before trying again."
                } else {
                    return "Too many requests. Please wait a moment before trying again."
                }
            case .invalidMessage:
                return "Please enter a valid question"
            case .noContext:
                return "Cannot chat without sermon transcript or summary"
            case .auth(let message):
                return "Authentication failed: \(message)"
            case .network(let message):
                return "Network error: \(message)"
            case .server(let code):
                return "Server error (\(code))"
            case .parseFailure:
                return "Failed to parse response"
            }
        }
    }

    // MARK: - Initialization
    private init(supabase: SupabaseClient = SupabaseService.shared.client) {
        self.supabase = supabase
    }

    // MARK: - Auth Helper
    private func getAuthToken() async throws -> String {
        do {
            let session = try await supabase.auth.session
            return session.accessToken
        } catch {
            print("[ChatService] Session expired, attempting refresh...")
            do {
                let refreshedSession = try await supabase.auth.refreshSession()
                print("[ChatService] Token refreshed successfully")
                return refreshedSession.accessToken
            } catch {
                print("[ChatService] Token refresh failed: \(error.localizedDescription)")
                throw ChatError.auth("Authentication failed. Please sign in again.")
            }
        }
    }

    // MARK: - Usage Limits
    // Note: Backend enforces rate limiting of 100 requests/hour per user to prevent API abuse
    // This is separate from the tier-based question limits below
    func canSendMessage(user: User, sermon: Sermon) -> Bool {
        // Premium users have unlimited questions per sermon
        // (but still subject to 100 req/hour rate limit on backend)
        if user.isPaidUser {
            return true
        }

        // Free users limited to 5 questions per sermon
        return sermon.userQuestionCount < 5
    }

    func remainingQuestions(user: User, sermon: Sermon) -> Int? {
        if user.isPaidUser {
            return nil // unlimited per sermon (100/hour rate limit applies)
        }
        return max(0, 5 - sermon.userQuestionCount)
    }

    // MARK: - Load Messages
    func loadMessages(for sermon: Sermon) {
        let messages = sermon.chatMessages.sorted { $0.timestamp < $1.timestamp }
        messagesSubject.send(messages)
    }

    // MARK: - Send Message
    func sendMessage(_ message: String, for sermon: Sermon, user: User) async throws {
        print("[ChatService] Sending message: \(message)")

        // Validate message
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw ChatError.invalidMessage
        }

        // Check usage limits
        guard canSendMessage(user: user, sermon: sermon) else {
            let remaining = remainingQuestions(user: user, sermon: sermon) ?? 0
            throw ChatError.limitReached(remaining: remaining)
        }

        // Check context availability
        guard sermon.transcript != nil || sermon.summary != nil else {
            throw ChatError.noContext
        }

        DispatchQueue.main.async {
            self.loadingSubject.send(true)
            self.errorSubject.send(nil)
        }

        // MARK: - Mock Mode for Testing
        if useMockMode {
            print("[ChatService] Using mock mode - simulating AI response")
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 second delay

            let mockResponse = generateMockResponse(for: trimmedMessage, sermon: sermon)

            await MainActor.run {
                // Create user message
                let userMessage = ChatMessage(
                    role: ChatRole.user.rawValue,
                    content: trimmedMessage,
                    countsTowardLimit: true
                )
                userMessage.sermon = sermon
                sermon.chatMessages.append(userMessage)

                // Create assistant message
                let assistantMessage = ChatMessage(
                    role: ChatRole.assistant.rawValue,
                    content: mockResponse,
                    countsTowardLimit: false
                )
                assistantMessage.sermon = sermon
                sermon.chatMessages.append(assistantMessage)

                // Update publishers
                loadMessages(for: sermon)
                loadingSubject.send(false)
            }
            return
        }

        do {
            // Get auth token
            let accessToken = try await getAuthToken()

            // Build context from sermon data
            let context = buildContext(for: sermon)

            // Build conversation history
            let conversationHistory = sermon.chatMessages
                .sorted { $0.timestamp < $1.timestamp }
                .map { ["role": $0.role, "content": $0.content] }

            // Create request body
            let requestBody: [String: Any] = [
                "message": trimmedMessage,
                "context": context,
                "conversationHistory": conversationHistory,
                "sermonId": sermon.id.uuidString
            ]

            guard let url = URL(string: endpoint),
                  let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
                throw ChatError.invalidMessage
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = httpBody
            request.timeoutInterval = 60.0

            print("[ChatService] Sending request to chat endpoint...")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ChatError.network("Invalid response")
            }

            print("[ChatService] Response status: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                // Handle rate limiting
                if httpResponse.statusCode == 429 {
                    if let retryAfterHeader = httpResponse.value(forHTTPHeaderField: "Retry-After"),
                       let retryAfter = Int(retryAfterHeader) {
                        throw ChatError.rateLimitExceeded(retryAfter: retryAfter)
                    }
                    throw ChatError.rateLimitExceeded(retryAfter: 60) // Default to 1 minute
                }
                if httpResponse.statusCode >= 500 {
                    throw ChatError.server(httpResponse.statusCode)
                }
                throw ChatError.network("Request failed with status \(httpResponse.statusCode)")
            }

            // Parse response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let success = json["success"] as? Bool,
                  success,
                  let dataDict = json["data"] as? [String: Any],
                  let aiResponse = dataDict["response"] as? String else {
                throw ChatError.parseFailure
            }

            print("[ChatService] Received AI response")

            // Save messages to SwiftData
            await MainActor.run {
                // Create user message
                let userMessage = ChatMessage(
                    role: ChatRole.user.rawValue,
                    content: trimmedMessage,
                    countsTowardLimit: true
                )
                userMessage.sermon = sermon
                sermon.chatMessages.append(userMessage)

                // Create assistant message
                let assistantMessage = ChatMessage(
                    role: ChatRole.assistant.rawValue,
                    content: aiResponse,
                    countsTowardLimit: false
                )
                assistantMessage.sermon = sermon
                sermon.chatMessages.append(assistantMessage)

                // Update publishers
                loadMessages(for: sermon)
                loadingSubject.send(false)
            }

        } catch {
            DispatchQueue.main.async {
                self.loadingSubject.send(false)
                self.errorSubject.send(error)
            }
            throw error
        }
    }

    // MARK: - Generate Suggested Questions
    func generateSuggestedQuestions(for sermon: Sermon) async throws {
        print("[ChatService] Generating suggested questions")

        guard sermon.transcript != nil || sermon.summary != nil else {
            print("[ChatService] No transcript or summary available for suggestions")
            return
        }

        // MARK: - Mock Mode for Testing
        if useMockMode {
            print("[ChatService] Using mock mode - generating suggested questions")
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay

            let mockQuestions = [
                "What are the main themes of this sermon?",
                "How can I apply these teachings to my daily life?",
                "What scriptures were referenced in this message?"
            ]

            DispatchQueue.main.async {
                self.suggestedQuestionsSubject.send(mockQuestions)
            }
            return
        }

        do {
            let accessToken = try await getAuthToken()
            let context = buildContext(for: sermon)

            let requestBody: [String: Any] = [
                "action": "generateQuestions",
                "context": context,
                "count": 3
            ]

            guard let url = URL(string: endpoint),
                  let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
                print("[ChatService] Failed to create request for suggested questions")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = httpBody
            request.timeoutInterval = 30.0

            print("[ChatService] Sending request to generate suggested questions...")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("[ChatService] Invalid response from suggested questions endpoint")
                return
            }

            print("[ChatService] Suggested questions response status: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("[ChatService] Suggested questions error response: \(responseString)")
                }
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[ChatService] Failed to parse JSON response")
                return
            }

            print("[ChatService] Suggested questions JSON: \(json)")

            guard let success = json["success"] as? Bool,
                  success,
                  let dataDict = json["data"] as? [String: Any],
                  let questions = dataDict["questions"] as? [String] else {
                print("[ChatService] Invalid response structure for suggested questions")
                return
            }

            print("[ChatService] Successfully generated \(questions.count) suggested questions")

            DispatchQueue.main.async {
                self.suggestedQuestionsSubject.send(questions)
            }

        } catch {
            print("[ChatService] Failed to generate questions: \(error)")
        }
    }

    // MARK: - Helper Methods
    private func buildContext(for sermon: Sermon) -> [String: Any] {
        var context: [String: Any] = [
            "title": sermon.title,
            "serviceType": sermon.serviceType,
            "date": sermon.date.ISO8601Format()
        ]

        if let speaker = sermon.speaker {
            context["speaker"] = speaker
        }

        if let summary = sermon.summary?.text {
            context["summary"] = summary
        }

        if let transcript = sermon.transcript?.text {
            // Limit transcript size to prevent token overflow
            let maxLength = 8000
            context["transcript"] = String(transcript.prefix(maxLength))
        }

        return context
    }

    // MARK: - Mock Response Generator (for testing)
    private func generateMockResponse(for question: String, sermon: Sermon) -> String {
        let responses = [
            "Based on the sermon '\(sermon.title)', this is an important question. The main themes include faith, action, and embracing God's calling in our daily lives.",
            "That's a great question! The sermon emphasizes the importance of moving beyond fear and stepping out in faith, trusting that God will guide us.",
            "According to the message, we're called to live with both faith and action. This means not just believing, but also actively demonstrating our faith through our choices.",
            "The speaker highlighted that embracing faith requires courage and a willingness to step outside our comfort zones. This applies directly to your question.",
            "Drawing from the sermon's message, we can see that God calls us to be bold and active in our faith, rather than passive observers."
        ]

        // Use hash of question to deterministically pick a response
        let hash = abs(question.hashValue)
        return responses[hash % responses.count]
    }
}
