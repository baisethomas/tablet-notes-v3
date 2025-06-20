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
        let prompt = Self.buildPrompt(serviceType: type, transcript: transcript)
        print("[SummaryService] Prompt to OpenAI (first 200 chars): \(prompt.prefix(200))...")
        let messages: [[String: String]] = [
            ["role": "system", "content": "You are a thoughtful spiritual assistant. Your primary goal is to summarize the sermon in a way that is easy to understand and remember. If the sermon is too short, under 1 minute, return a message that the sermon was too short to summarize accurately."],
            ["role": "user", "content": prompt]
        ]
        let requestBody: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.4, // Reduced from 0.7 to reduce creativity/hallucination
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

    private static func buildPrompt(serviceType: String, transcript: String) -> String {
        return """
You are a thoughtful spiritual assistant with a deep understanding of the Bible and interpreting sermons. Create a comprehensive summary of this \(serviceType) based on the transcript provided. Your goal is to capture the essence and key elements of the message.

TRANSCRIPT:
\(transcript)

Create a well-structured summary that includes:

**Main Message:**
What was the central theme or primary message of this \(serviceType)?

**Key Points:**
What were the main teachings, lessons, or points discussed? Include the most important insights and concepts covered.

**Scripture References:**
List any Bible verses, passages, or biblical stories that were mentioned or referenced.

**Practical Applications:**
What practical advice, applications, or calls to action were given? How can listeners apply these teachings to their daily lives?

**Additional Context:**
Include any relevant background information, series context, special occasions, or other notable elements that provide important context.

**Reflection Questions:**
One thoughtful question for personal reflection based on the message.
GUIDELINES:
- Draw from the entire transcript to create a thorough summary
- Focus on representing what was taught and discussed, pay attention to the nuances of the sermon as well
- Organize the information clearly and logically
- Make the summary detailed enough to be meaningful while remaining concise
- Base your summary on the content of the transcript

Create a summary that would help someone understand and remember the key elements of this message.

ADDITIONAL GUIDANCE BASED ON SERMON TYPE:
{if serviceType = "Sunday Sermon"}
Focus on the main spiritual lesson and how it connects to everyday faith. Highlight practical applications.
{endif}

{if serviceType = "Bible Study"}
Emphasize scriptural analysis and connections between passages. Include any historical or contextual information mentioned.
{endif}

{if serviceType = "Youth Group"}
Use slightly more accessible language. Highlight relatable examples and practical applications for younger audiences.
{endif}

{if serviceType = "Conference"}
Identify the broader theme of the conference if mentioned. Connect this message to larger spiritual concepts or movements discussed.
{endif}
"""
    }
}