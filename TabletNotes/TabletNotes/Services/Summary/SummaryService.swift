import Foundation
import Combine

class SummaryService: ObservableObject {
    private let summarySubject = CurrentValueSubject<String?, Never>(nil)
    let statusSubject = CurrentValueSubject<String, Never>("idle") // idle, pending, complete, failed
    var summaryPublisher: AnyPublisher<String?, Never> { summarySubject.eraseToAnyPublisher() }
    var statusPublisher: AnyPublisher<String, Never> { statusSubject.eraseToAnyPublisher() }
    private var cancellables = Set<AnyCancellable>()
    
    // Load the OpenAI API key from the .env file
    let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    // Make sure to set your API key in the .env file at the project root
    
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-3.5-turbo"
    
    func generateSummary(for transcript: String, type: String) {
        print("[SummaryService] Called generateSummary with transcript length: \(transcript.count), type: \(type)")
        if apiKey.isEmpty {
            print("[SummaryService] ERROR: OpenAI API key is missing!")
        } else {
            print("[SummaryService] OpenAI API key loaded (length: \(apiKey.count))")
        }
        statusSubject.send("pending")
        summarySubject.send(nil)
        let prompt = Self.buildPrompt(sermonType: type, transcript: transcript)
        print("[SummaryService] Prompt to OpenAI (first 200 chars): \(prompt.prefix(200))...")
        let messages: [[String: String]] = [
            ["role": "system", "content": "You are a thoughtful spiritual assistant helping to summarize religious teachings."],
            ["role": "user", "content": prompt]
        ]
        let requestBody: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 800
        ]
        guard let url = URL(string: endpoint),
              let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("[SummaryService] ERROR: Failed to create request body or URL")
            self.statusSubject.send("failed")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        print("[SummaryService] Sending request to OpenAI API...")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[SummaryService] ERROR: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.statusSubject.send("failed")
                    self.summarySubject.send("[Error] \(error.localizedDescription)")
                }
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                print("[SummaryService] OpenAI API HTTP status: \(httpResponse.statusCode)")
            }
            guard let data = data else {
                print("[SummaryService] ERROR: No data received from OpenAI API")
                DispatchQueue.main.async {
                    self.statusSubject.send("failed")
                    self.summarySubject.send("[Error] No data received from OpenAI API.")
                }
                return
            }
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[SummaryService] OpenAI API response: \(jsonString.prefix(500))...")
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                print("[SummaryService] ERROR: Invalid response from OpenAI API")
                DispatchQueue.main.async {
                    self.statusSubject.send("failed")
                    self.summarySubject.send("[Error] Invalid response from OpenAI API.")
                }
                return
            }
            print("[SummaryService] Summary content received (first 200 chars): \(content.prefix(200))...")
            DispatchQueue.main.async {
                self.summarySubject.send(content.trimmingCharacters(in: .whitespacesAndNewlines))
                self.statusSubject.send("complete")
            }
        }
        task.resume()
    }

    func retrySummary(for transcript: String, type: String) {
        generateSummary(for: transcript, type: type)
    }

    private static func buildPrompt(sermonType: String, transcript: String) -> String {
        // Use the provided prompt template
        return """
You are a thoughtful spiritual assistant helping to summarize religious teachings. You've been given a transcript of a \(sermonType) to summarize.

CONTEXT:
- This summary will help people revisit and reflect on spiritual teachings they've heard
- The summary should preserve the spiritual essence and key teachings
- Scripture references should be highlighted and properly formatted
- The tone should be respectful and aligned with faith-based contexts

TRANSCRIPT:
\(transcript)

Please create a comprehensive summary that includes:

1. MAIN THEME: In 1-2 sentences, what was the central message or theme?

2. KEY POINTS: Identify 3-5 main points or teachings, presented as brief paragraphs

3. SCRIPTURE REFERENCES: List all Bible verses mentioned or referenced (with the full reference, e.g., \"John 3:16\")

4. PRACTICAL APPLICATIONS: 2-3 ways this teaching could be applied in daily life

5. REFLECTION QUESTION: One thoughtful question for personal reflection based on this message

Format the summary in a clean, readable way with appropriate headings. The total summary should be approximately 300-500 words.

ADDITIONAL GUIDANCE BASED ON SERMON TYPE:
{if SERMON_TYPE = \"Sunday Sermon\"}
Focus on the main spiritual lesson and how it connects to everyday faith. Highlight practical applications.
{endif}

{if SERMON_TYPE = \"Bible Study\"}
Emphasize scriptural analysis and connections between passages. Include any historical or contextual information mentioned.
{endif}

{if SERMON_TYPE = \"Youth Group\"}
Use slightly more accessible language. Highlight relatable examples and practical applications for younger audiences.
{endif}

{if SERMON_TYPE = \"Conference\"}
Identify the broader theme of the conference if mentioned. Connect this message to larger spiritual concepts or movements discussed.
{endif}
"""
    }
}
