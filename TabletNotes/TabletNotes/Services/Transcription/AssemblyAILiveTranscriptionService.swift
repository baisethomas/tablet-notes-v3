import Foundation
import AVFoundation
import Combine

class AssemblyAILiveTranscriptionService: NSObject, ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioEngine = AVAudioEngine()
    private let transcriptSubject = CurrentValueSubject<String, Never>("")
    private var fullTranscript: String = ""
    private var sessionToken: String?
    private let supabase = SupabaseService.shared
    
    var transcriptPublisher: AnyPublisher<String, Never> { 
        transcriptSubject.eraseToAnyPublisher() 
    }
    
    @Published var isConnected = false
    @Published var error: String?
    
    private let sampleRate: Double = 44100 // Use higher quality audio
    
    func startLiveTranscription() async throws {
        guard !isConnected else { return }

        do {
            // First, try to get a temporary session token from our Netlify function
            try await getSessionToken()
        } catch {
            print("[AssemblyAI Live] Failed to get session token from Netlify function: \(error)")
            do {
                // Fallback: use direct API key access
                try await getSessionTokenDirect()
            } catch let directError {
                print("[AssemblyAI Live] Direct API key access also failed: \(directError)")
                DispatchQueue.main.async {
                    self.error = "AssemblyAI Live transcription is not available. Please check your configuration."
                }
                throw directError
            }
        }

        // Start WebSocket connection
        try await startWebSocketConnection()

        // Start audio capture
        try startAudioCapture()

        isConnected = true
    }
    
    func stopLiveTranscription() {
        stopAudioCapture()
        closeWebSocketConnection()
        isConnected = false
    }
    
    private func getSessionToken() async throws {
        guard let url = URL(string: "https://comfy-daffodil-7ecc55.netlify.app/.netlify/functions/assemblyai-live-token") else {
            throw NSError(domain: "InvalidURL", code: 1, userInfo: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Try to add authentication if available, but don't require it for free users
        do {
            let session = try await supabase.client.auth.session
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            print("[AssemblyAI Live] Using authenticated session for live transcription")
        } catch {
            print("[AssemblyAI Live] No authentication available, using public access")
            // Continue without authentication - the Netlify function should handle unauthenticated requests
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "InvalidResponse", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }

        if httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("[AssemblyAI Live] Token request failed with status: \(httpResponse.statusCode), body: \(responseBody)")
            throw NSError(domain: "TokenError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to get session token: \(responseBody)"])
        }

        let tokenResponse = try JSONDecoder().decode(SessionTokenResponse.self, from: data)
        self.sessionToken = tokenResponse.sessionToken
    }

    private func getSessionTokenDirect() async throws {
        print("[AssemblyAI Live] Using direct API key for session token")

        // Check if API key is configured
        guard AssemblyAIConfig.apiKey != "YOUR_ASSEMBLYAI_API_KEY_HERE" && !AssemblyAIConfig.apiKey.isEmpty else {
            throw NSError(domain: "APIKeyError", code: 1, userInfo: [NSLocalizedDescriptionKey: "AssemblyAI API key not configured. Please add your API key to AssemblyAIKey.swift"])
        }

        guard let url = URL(string: "\(AssemblyAIConfig.baseURL)/realtime/token") else {
            throw NSError(domain: "InvalidURL", code: 1, userInfo: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AssemblyAIConfig.apiKey, forHTTPHeaderField: "Authorization")

        let requestBody = [
            "expires_in": 3600 // 1 hour
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "InvalidResponse", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }

        if httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("[AssemblyAI Live] Direct token request failed with status: \(httpResponse.statusCode), body: \(responseBody)")
            throw NSError(domain: "TokenError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to get session token directly: \(responseBody)"])
        }

        let tokenResponse = try JSONDecoder().decode(DirectTokenResponse.self, from: data)
        self.sessionToken = tokenResponse.token
    }
    
    private func startWebSocketConnection() async throws {
        guard let sessionToken = sessionToken else {
            throw NSError(domain: "NoToken", code: 1, userInfo: nil)
        }
        
        var urlComponents = URLComponents(string: "wss://api.assemblyai.com/v2/realtime/ws")!
        urlComponents.queryItems = [
            URLQueryItem(name: "sample_rate", value: String(Int(sampleRate))),
            URLQueryItem(name: "token", value: sessionToken),
            URLQueryItem(name: "encoding", value: "pcm_f32le"),
            URLQueryItem(name: "word_boost", value: "['sermon','church','bible','scripture','jesus','christ','god','lord','faith','prayer','worship','ministry','pastor','preacher','congregation','salvation','grace','mercy','gospel','holy','spirit','heaven','blessing','amen','hallelujah']"),
            URLQueryItem(name: "boost_param", value: "high")
        ]
        
        guard let url = urlComponents.url else {
            throw NSError(domain: "InvalidWebSocketURL", code: 1, userInfo: nil)
        }
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Start listening for messages
        startListeningForMessages()
    }
    
    private func startListeningForMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleWebSocketMessage(message)
                // Continue listening
                self?.startListeningForMessages()
            case .failure(let error):
                print("[AssemblyAI Live] WebSocket error: \(error)")
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                }
            }
        }
    }
    
    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            do {
                let response = try JSONDecoder().decode(TranscriptResponse.self, from: text.data(using: .utf8)!)
                DispatchQueue.main.async {
                    if response.messageType == "PartialTranscript" {
                        // Update with partial transcript
                        let partialText = response.text ?? ""
                        print("[AssemblyAI Live] Partial: '\(partialText)' (confidence: \(response.confidence ?? 0))")
                        self.transcriptSubject.send(self.fullTranscript + (partialText.isEmpty ? "" : " " + partialText))
                    } else if response.messageType == "FinalTranscript" {
                        // Add to full transcript
                        if let finalText = response.text, !finalText.isEmpty {
                            print("[AssemblyAI Live] Final: '\(finalText)' (confidence: \(response.confidence ?? 0))")
                            if self.fullTranscript.isEmpty {
                                self.fullTranscript = finalText
                            } else {
                                self.fullTranscript += " " + finalText
                            }
                            self.transcriptSubject.send(self.fullTranscript)
                        }
                    }
                }
            } catch {
                print("[AssemblyAI Live] Failed to decode message: \(error)")
            }
        case .data(_):
            break
        @unknown default:
            break
        }
    }
    
    private func startAudioCapture() throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Convert to high-quality format for better transcription
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, 
                                             sampleRate: sampleRate, 
                                             channels: 1, 
                                             interleaved: false) else {
            throw NSError(domain: "AudioFormatError", code: 1, userInfo: nil)
        }
        
        guard let converter = AVAudioConverter(from: recordingFormat, to: outputFormat) else {
            throw NSError(domain: "AudioConverterError", code: 1, userInfo: nil)
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // Convert audio format
            let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: buffer.frameCapacity)!
            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, _ in
                return buffer
            }
            
            if let error = error {
                print("[AssemblyAI Live] Audio conversion error: \(error)")
                return
            }
            
            // Send audio data via WebSocket
            self.sendAudioData(convertedBuffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
    }
    
    private func sendAudioData(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(buffer.frameLength)
        let data = Data(bytes: channelData, count: frameLength * 4) // 4 bytes per sample for 32-bit float
        
        let base64String = data.base64EncodedString()
        let message = ["audio_data": base64String]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("[AssemblyAI Live] Failed to send audio data: \(error)")
                }
            }
        } catch {
            print("[AssemblyAI Live] Failed to serialize audio message: \(error)")
        }
    }
    
    private func stopAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
    }
    
    private func closeWebSocketConnection() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }
    
    deinit {
        stopLiveTranscription()
    }
}

// MARK: - Response Models
private struct SessionTokenResponse: Codable {
    let sessionToken: String
}

private struct DirectTokenResponse: Codable {
    let token: String
}

private struct TranscriptResponse: Codable {
    let messageType: String
    let text: String?
    let confidence: Double?
    let audioStart: Int?
    let audioEnd: Int?
    let punctuated: Bool?
    let textFormatted: Bool?
}