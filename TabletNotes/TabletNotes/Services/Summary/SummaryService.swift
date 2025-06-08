import Foundation
import Combine

class SummaryService: ObservableObject {
    private let summarySubject = CurrentValueSubject<String?, Never>(nil)
    private let statusSubject = CurrentValueSubject<String, Never>("idle") // idle, pending, complete, failed
    var summaryPublisher: AnyPublisher<String?, Never> { summarySubject.eraseToAnyPublisher() }
    var statusPublisher: AnyPublisher<String, Never> { statusSubject.eraseToAnyPublisher() }
    private var cancellables = Set<AnyCancellable>()
    
    // Load the OpenAI API key from the .env file
    let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    // Make sure to set your API key in the .env file at the project root
    
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-3.5-turbo"
    
    func generateSummary(for transcript: String, type: String) {
        statusSubject.send("pending")
        summarySubject.send(nil)
        let prompt = Self.buildPrompt(sermonType: type, transcript: transcript)
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
            self.statusSubject.send("failed")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.statusSubject.send("failed")
                    self.summarySubject.send("[Error] \(error.localizedDescription)")
                }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                DispatchQueue.main.async {
                    self.statusSubject.send("failed")
                    self.summarySubject.send("[Error] Invalid response from OpenAI API.")
                }
                return
            }
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

1. TITLE: Create a concise, meaningful title that captures the essence of this message (3-8 words)

2. MAIN THEME: In 1-2 sentences, what was the central message or theme?

3. KEY POINTS: Identify 3-5 main points or teachings, presented as brief paragraphs

4. SCRIPTURE REFERENCES: List all Bible verses mentioned or referenced (with the full reference, e.g., \"John 3:16\")

5. PRACTICAL APPLICATIONS: 2-3 ways this teaching could be applied in daily life

6. REFLECTION QUESTION: One thoughtful question for personal reflection based on this message

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
