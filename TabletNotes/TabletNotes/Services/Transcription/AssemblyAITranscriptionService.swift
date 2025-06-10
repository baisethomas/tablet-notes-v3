import Foundation
import SwiftData
import SwiftUI
import Combine

class AssemblyAITranscriptionService: ObservableObject {
    private let apiKey = AssemblyAIConfig.apiKey
    private let uploadEndpoint = "https://api.assemblyai.com/v2/upload"
    private let transcriptEndpoint = "https://api.assemblyai.com/v2/transcript"

    // 1. Upload audio file to AssemblyAI
    func uploadAudioFile(_ audioFileURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        print("[AssemblyAI] Uploading audio file: \(audioFileURL)")
        var request = URLRequest(url: URL(string: uploadEndpoint)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
        do {
            let audioData = try Data(contentsOf: audioFileURL)
            let task = URLSession.shared.uploadTask(with: request, from: audioData) { data, response, error in
                if let error = error {
                    print("[AssemblyAI] Upload error: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                if let httpResponse = response as? HTTPURLResponse {
                    print("[AssemblyAI] Upload HTTP status: \(httpResponse.statusCode)")
                }
                guard let data = data else {
                    print("[AssemblyAI] Upload failed: No data returned")
                    completion(.failure(NSError(domain: "AssemblyAI", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data returned from upload"])) )
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("[AssemblyAI] Upload response JSON: \(json)")
                    if let uploadURL = json["upload_url"] as? String {
                        completion(.success(uploadURL))
                    } else {
                        print("[AssemblyAI] Upload failed: No upload_url in response")
                        completion(.failure(NSError(domain: "AssemblyAI", code: 0, userInfo: [NSLocalizedDescriptionKey: "No upload_url in response"])) )
                    }
                } else {
                    print("[AssemblyAI] Upload failed: Could not parse JSON")
                    completion(.failure(NSError(domain: "AssemblyAI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not parse upload response JSON"])) )
                }
            }
            task.resume()
        } catch {
            print("[AssemblyAI] Failed to read audio file data: \(error.localizedDescription)")
            completion(.failure(error))
        }
    }

    // 2. Start transcription job
    func startTranscription(uploadUrl: String, completion: @escaping (Result<(String, [TranscriptSegment]), Error>) -> Void) {
        print("[AssemblyAI] Starting transcription with uploadUrl: \(uploadUrl)")
        var request = URLRequest(url: URL(string: transcriptEndpoint)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "audio_url": uploadUrl
        ]
        let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        if let httpBody = httpBody, let jsonString = String(data: httpBody, encoding: .utf8) {
            print("[AssemblyAI] Raw JSON body: \(jsonString)")
        }
        request.httpBody = httpBody
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[AssemblyAI] Transcription start error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                print("[AssemblyAI] Transcription start HTTP status: \(httpResponse.statusCode)")
            }
            guard let data = data else {
                print("[AssemblyAI] Transcription start failed: No data returned")
                completion(.failure(NSError(domain: "AssemblyAI", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data returned from transcription start"])) )
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("[AssemblyAI] Transcription start response JSON: \(json)")
                if let id = json["id"] as? String {
                    // Continue polling for result (existing logic)
                    self.pollTranscriptionResult(id: id, completion: completion)
                } else {
                    print("[AssemblyAI] Transcription start failed: No id in response")
                    completion(.failure(NSError(domain: "AssemblyAI", code: 0, userInfo: [NSLocalizedDescriptionKey: "No id in transcription start response"])) )
                }
            } else {
                print("[AssemblyAI] Transcription start failed: Could not parse JSON")
                completion(.failure(NSError(domain: "AssemblyAI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not parse transcription start response JSON"])) )
            }
        }
        task.resume()
    }

    // Fetch paragraphs for a completed transcript
    private func fetchParagraphs(transcriptId: String, text: String, completion: @escaping (Result<(String, [TranscriptSegment]), Error>) -> Void) {
        let url = URL(string: "\(transcriptEndpoint)/\(transcriptId)/paragraphs")!
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
                  let paragraphs = json["paragraphs"] as? [[String: Any]] else {
                completion(.failure(NSError(domain: "AssemblyAI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch paragraphs"])) )
                return
            }
            let segments: [TranscriptSegment] = paragraphs.compactMap { para in
                guard let start = para["start"] as? Double,
                      let end = para["end"] as? Double,
                      let text = para["text"] as? String else { return nil }
                return TranscriptSegment(
                    id: UUID(),
                    text: text,
                    startTime: start / 1000.0,
                    endTime: end / 1000.0
                )
            }
            completion(.success((text, segments)))
        }
        task.resume()
    }

    // 3. Poll for result (now returns both text and segments)
    func pollTranscriptionResult(id: String, completion: @escaping (Result<(String, [TranscriptSegment]), Error>) -> Void) {
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
                // Fetch paragraphs from the dedicated endpoint
                self.fetchParagraphs(transcriptId: id, text: text, completion: completion)
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

    // 4. High-level function to transcribe a file (now returns both text and segments)
    func transcribeAudioFile(url: URL, completion: @escaping (Result<(String, [TranscriptSegment]), Error>) -> Void) {
        uploadAudioFile(url) { result in
            switch result {
            case .success(let uploadUrl):
                self.startTranscription(uploadUrl: uploadUrl) { result in
                    switch result {
                    case .success(let (text, segments)):
                        completion(.success((text, segments)))
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
