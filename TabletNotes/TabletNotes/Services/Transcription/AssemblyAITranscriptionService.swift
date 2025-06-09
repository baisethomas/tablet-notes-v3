import Foundation

class AssemblyAITranscriptionService: ObservableObject {
    private let apiKey = AssemblyAIConfig.apiKey
    private let uploadEndpoint = "https://api.assemblyai.com/v2/upload"
    private let transcriptEndpoint = "https://api.assemblyai.com/v2/transcript"

    // 1. Upload audio file
    func uploadAudioFile(url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        var request = URLRequest(url: URL(string: uploadEndpoint)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")

        let task = URLSession.shared.uploadTask(with: request, fromFile: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let uploadUrl = json["upload_url"] as? String else {
                completion(.failure(NSError(domain: "AssemblyAI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Upload failed"])))
                return
            }
            completion(.success(uploadUrl))
        }
        task.resume()
    }

    // 2. Start transcription job
    func startTranscription(uploadUrl: String, completion: @escaping (Result<String, Error>) -> Void) {
        var request = URLRequest(url: URL(string: transcriptEndpoint)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = ["audio_url": uploadUrl]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String else {
                completion(.failure(NSError(domain: "AssemblyAI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Transcription start failed"])))
                return
            }
            completion(.success(id))
        }
        task.resume()
    }

    // 3. Poll for result
    func pollTranscriptionResult(id: String, completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "\(transcriptEndpoint)/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                completion(.failure(NSError(domain: "AssemblyAI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Polling failed"])))
                return
            }
            if status == "completed", let text = json["text"] as? String {
                completion(.success(text))
            } else if status == "failed" {
                completion(.failure(NSError(domain: "AssemblyAI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Transcription failed"])))
            } else {
                // Still processing, poll again after delay
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    self.pollTranscriptionResult(id: id, completion: completion)
                }
            }
        }
        task.resume()
    }

    // 4. High-level function to transcribe a file
    func transcribeAudioFile(url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        uploadAudioFile(url: url) { result in
            switch result {
            case .success(let uploadUrl):
                self.startTranscription(uploadUrl: uploadUrl) { result in
                    switch result {
                    case .success(let id):
                        self.pollTranscriptionResult(id: id, completion: completion)
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
} 