import Foundation
import SwiftData
import SwiftUI
import Combine

// Ensure TabletNotes/TabletNotes/Resources/AssemblyAIKey.swift and TabletNotes/TabletNotes/Models/Transcript.swift are included in the build target for AssemblyAIConfig and TranscriptSegment to be in scope.

// MARK: - Vercel API Models

// For /api/generate-upload-url
struct GenerateUploadURLResponse: Codable {
    let uploadUrl: String
    let path: String
    let token: String
}

// For /api/transcribe
// Based on transcribe.js, it returns a transcript-like object.
// The `segments` are actually words from AssemblyAI.
struct TranscribeResponse: Codable {
    let id: String
    let text: String?
    let segments: [AssemblyAIWord]? // 'segments' in my Vercel API is 'words' from AssemblyAI
    let status: String
}

struct AssemblyAIWord: Codable {
    let text: String
    let start: Int
    let end: Int
    let confidence: Double
    let speaker: String?
}

class AssemblyAITranscriptionService: ObservableObject {
    // API endpoints
    private let apiBaseUrl = "https://comfy-daffodil-7ecc55.netlify.app"
    private lazy var generateUploadUrlEndpoint = "\(apiBaseUrl)/api/generate-upload-url"
    private lazy var transcribeEndpoint = "\(apiBaseUrl)/api/transcribe"

    // 1. Get Upload URL from backend
    private func getUploadURL(fileName: String, completion: @escaping (Result<GenerateUploadURLResponse, Error>) -> Void) {
        print("[API] Getting upload URL for \(fileName)")
        guard let url = URL(string: generateUploadUrlEndpoint) else {
            completion(.failure(NSError(domain: "InvalidURL", code: 0, userInfo: nil)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["fileName": fileName]
        request.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "NoData", code: 0, userInfo: nil)))
                return
            }
            do {
                let decodedResponse = try JSONDecoder().decode(GenerateUploadURLResponse.self, from: data)
                completion(.success(decodedResponse))
            } catch {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("[API] Failed to decode JSON. Raw response: \(responseString)")
                }
                completion(.failure(error))
            }
        }.resume()
    }

    // 2. Upload file to Supabase using the signed URL
    private func uploadFile(to uploadUrl: String, fileURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        print("[API] Uploading file to Supabase: \(fileURL)")
        guard let url = URL(string: uploadUrl) else {
            completion(.failure(NSError(domain: "InvalidURL", code: 1, userInfo: nil)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")

        do {
            let audioData = try Data(contentsOf: fileURL)
            URLSession.shared.uploadTask(with: request, from: audioData) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    print("[API] Supabase upload failed with status code: \(statusCode)")
                    if let responseData = data, let responseString = String(data: responseData, encoding: .utf8) {
                        print("[API] Supabase error response: \(responseString)")
                    }
                    completion(.failure(NSError(domain: "UploadFailed", code: statusCode, userInfo: nil)))
                    return
                }
                completion(.success(()))
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }

    // 3. Start Transcription via backend
    private func startTranscription(filePath: String, completion: @escaping (Result<(String, [TranscriptSegment]), Error>) -> Void) {
        print("[API] Starting transcription for path: \(filePath)")
        guard let url = URL(string: transcribeEndpoint) else {
            completion(.failure(NSError(domain: "InvalidURL", code: 2, userInfo: nil)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["filePath": filePath]
        request.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "NoData", code: 0, userInfo: nil)))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let statusCode = httpResponse.statusCode
                let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
                print("[API] Transcription failed with status: \(statusCode), body: \(responseBody)")
                completion(.failure(NSError(domain: "TranscriptionError", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error: \(responseBody)"])))
                return
            }
            
            do {
                let decodedResponse = try JSONDecoder().decode(TranscribeResponse.self, from: data)
                if decodedResponse.status == "completed" || decodedResponse.status == "success" {
                    let text = decodedResponse.text ?? ""
                    let segments: [TranscriptSegment] = [] 
                    completion(.success((text, segments)))
                } else {
                    completion(.failure(NSError(domain: "TranscriptionFailed", code: 0, userInfo: [NSLocalizedDescriptionKey: "Transcription did not complete. Status: \(decodedResponse.status)"])))
                }
            } catch {
                let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
                print("[API] JSON Decoding Error: \(error.localizedDescription). Response: \(responseBody)")
                completion(.failure(error))
            }
        }.resume()
    }

    // High-level function to transcribe a file using the backend
    func transcribeAudioFile(url: URL, completion: @escaping (Result<(String, [TranscriptSegment]), Error>) -> Void) {
        let fileName = url.lastPathComponent
        
        getUploadURL(fileName: fileName) { result in
            switch result {
            case .success(let uploadInfo):
                self.uploadFile(to: uploadInfo.uploadUrl, fileURL: url) { uploadResult in
                    switch uploadResult {
                    case .success:
                        self.startTranscription(filePath: uploadInfo.path) { transcriptionResult in
                            completion(transcriptionResult)
                        }
                    case .failure(let error):
                        print("[API] Upload failed: \(error.localizedDescription)")
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                print("[API] GetUploadURL failed: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
} 
