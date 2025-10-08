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
    private var connectionAttempts = 0
    private let maxConnectionAttempts = 3
    
    func startLiveTranscription() async throws {
        guard !isConnected else { return }

        // Clear previous transcript
        DispatchQueue.main.async {
            self.fullTranscript = ""
            self.transcriptSubject.send("")
        }

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

        // Note: isConnected will be set to true when we receive "SessionBegins" message
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
        // Determine the actual sample rate we'll be sending
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        let inputSampleRate = recordingFormat.sampleRate

        // Use input sample rate if supported by AssemblyAI, otherwise use target rate
        let supportedRates: [Double] = [8000, 16000, 22050, 44100, 48000]
        let actualSampleRate = supportedRates.contains(inputSampleRate) ? inputSampleRate : sampleRate

        // Try Universal-Streaming v3 first, then fallback to v2
        var urlComponents = URLComponents(string: "wss://streaming.assemblyai.com/v3/ws")!
        urlComponents.queryItems = [
            URLQueryItem(name: "sample_rate", value: String(Int(actualSampleRate))),
            URLQueryItem(name: "encoding", value: "pcm_s16le")
        ]

        guard let url = urlComponents.url else {
            throw NSError(domain: "InvalidWebSocketURL", code: 1, userInfo: nil)
        }

        print("[AssemblyAI Live] Connecting to Universal-Streaming v3 with \(Int(actualSampleRate))Hz: \(url)")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.setValue(AssemblyAIConfig.apiKey, forHTTPHeaderField: "Authorization")

        webSocketTask = session.webSocketTask(with: request)

        // Add connection state tracking
        webSocketTask?.resume()

        // Wait a moment for connection to establish
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

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
                    self?.isConnected = false
                    self?.error = error.localizedDescription
                }
                // Don't continue listening on failure
            }
        }
    }
    
    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            print("[AssemblyAI Live] Received message: \(text)")

            do {
                // Try to parse as JSON to understand the message structure
                if let jsonData = text.data(using: .utf8),
                   let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                    // Handle different message types from AssemblyAI
                    // v3 API uses "type" field, v2 API uses "message_type" field
                    let messageType = (jsonObject["type"] as? String) ?? (jsonObject["message_type"] as? String)

                    if let messageType = messageType {
                        print("[AssemblyAI Live] Message type: \(messageType)")

                        switch messageType {
                        case "Turn":
                            // v3 API uses "Turn" messages with a "transcript" field
                            if let transcriptText = jsonObject["transcript"] as? String {
                                let isEndOfTurn = jsonObject["end_of_turn"] as? Bool ?? false

                                if isEndOfTurn && !transcriptText.isEmpty {
                                    // Final transcript for this turn
                                    print("[AssemblyAI Live] ✅ Final turn transcript: '\(transcriptText)'")
                                    DispatchQueue.main.async {
                                        if self.fullTranscript.isEmpty {
                                            self.fullTranscript = transcriptText
                                        } else {
                                            self.fullTranscript += " " + transcriptText
                                        }
                                        print("[AssemblyAI Live] 📤 Sending final to UI: '\(self.fullTranscript)'")
                                        self.transcriptSubject.send(self.fullTranscript)
                                    }
                                } else if !transcriptText.isEmpty {
                                    // Partial transcript for this turn
                                    print("[AssemblyAI Live] ✅ Partial turn transcript: '\(transcriptText)'")
                                    DispatchQueue.main.async {
                                        let combinedText = self.fullTranscript + (self.fullTranscript.isEmpty ? "" : " ") + transcriptText
                                        print("[AssemblyAI Live] 📤 Sending partial to UI: '\(combinedText)'")
                                        self.transcriptSubject.send(combinedText)
                                    }
                                }
                            }
                        case "PartialTranscript":
                            if let partialText = jsonObject["text"] as? String {
                                print("[AssemblyAI Live] ✅ Partial transcript received: '\(partialText)'")
                                DispatchQueue.main.async {
                                    let combinedText = self.fullTranscript + (partialText.isEmpty ? "" : " " + partialText)
                                    print("[AssemblyAI Live] 📤 Sending partial to UI: '\(combinedText)'")
                                    self.transcriptSubject.send(combinedText)
                                }
                            } else {
                                print("[AssemblyAI Live] ⚠️ PartialTranscript message with no text")
                            }
                        case "FinalTranscript":
                            if let finalText = jsonObject["text"] as? String, !finalText.isEmpty {
                                print("[AssemblyAI Live] ✅ Final transcript received: '\(finalText)'")
                                DispatchQueue.main.async {
                                    if self.fullTranscript.isEmpty {
                                        self.fullTranscript = finalText
                                    } else {
                                        self.fullTranscript += " " + finalText
                                    }
                                    print("[AssemblyAI Live] 📤 Sending final to UI: '\(self.fullTranscript)'")
                                    self.transcriptSubject.send(self.fullTranscript)
                                }
                            } else {
                                print("[AssemblyAI Live] ⚠️ FinalTranscript message with no text")
                            }
                        case "SessionBegins", "Begin":
                            print("[AssemblyAI Live] ✅ Session began successfully")
                            DispatchQueue.main.async {
                                self.isConnected = true
                            }
                        case "SessionTerminated", "Error":
                            print("[AssemblyAI Live] Session terminated or error")
                            if let errorMessage = jsonObject["error"] as? String {
                                print("[AssemblyAI Live] Error message: \(errorMessage)")
                            }
                            DispatchQueue.main.async {
                                self.isConnected = false
                            }
                            // Stop listening when session terminates
                            return
                        default:
                            print("[AssemblyAI Live] Unknown message type: \(messageType)")
                        }
                    } else {
                        print("[AssemblyAI Live] No message type field in response: \(jsonObject)")
                    }
                }
            } catch {
                print("[AssemblyAI Live] Failed to parse message as JSON: \(error)")
                print("[AssemblyAI Live] Raw message: \(text)")
            }
        case .data(let data):
            print("[AssemblyAI Live] Received binary data: \(data.count) bytes")
        @unknown default:
            print("[AssemblyAI Live] Received unknown message type")
        }
    }
    
    private func startAudioCapture() throws {
        // Use the existing audio session configuration from RecordingService
        // Don't reconfigure the audio session since RecordingService already set it up
        let audioSession = AVAudioSession.sharedInstance()
        print("[AssemblyAI Live] Using existing audio session configuration: \(audioSession.category), mode: \(audioSession.mode)")

        // Ensure session is active (RecordingService should have already done this)
        if !audioSession.isOtherAudioPlaying {
            do {
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                print("[AssemblyAI Live] Audio session activated")
            } catch {
                print("[AssemblyAI Live] Warning: Could not activate audio session: \(error)")
                // Continue anyway since RecordingService might have it active
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        print("[AssemblyAI Live] Input format: \(recordingFormat)")

        // Use input format directly to avoid unnecessary conversion
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            let frameLength = Int(buffer.frameLength)
            print("[AssemblyAI Live] Raw audio buffer: \(frameLength) frames")

            if frameLength == 0 {
                print("[AssemblyAI Live] ⚠️ Received empty audio buffer")
                return
            }

            // Check if we need to convert the sample rate
            let inputSampleRate = recordingFormat.sampleRate
            let targetSampleRate = self.sampleRate

            // AssemblyAI Universal-Streaming requires PCM16, mono audio
            let needsConversion = recordingFormat.channelCount != 1 ||
                                recordingFormat.commonFormat != .pcmFormatInt16 ||
                                !([8000, 16000, 22050, 44100, 48000].contains(inputSampleRate))

            if !needsConversion {
                // Use input format directly - already mono, PCM16, and supported sample rate
                print("[AssemblyAI Live] Using input format directly: \(inputSampleRate)Hz, \(recordingFormat.channelCount) channel(s)")
                self.sendAudioData(buffer)
            } else {
                // Convert to the format AssemblyAI Universal-Streaming expects (PCM16, mono, target sample rate)
                print("[AssemblyAI Live] Converting from \(inputSampleRate)Hz to \(targetSampleRate)Hz")

                guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                                     sampleRate: targetSampleRate,
                                                     channels: 1,
                                                     interleaved: false) else {
                    print("[AssemblyAI Live] Failed to create output format")
                    return
                }

                guard let converter = AVAudioConverter(from: recordingFormat, to: outputFormat) else {
                    print("[AssemblyAI Live] Failed to create audio converter from \(recordingFormat) to \(outputFormat)")
                    return
                }

                // Calculate the output frame capacity for sample rate conversion
                let ratio = targetSampleRate / inputSampleRate
                let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else {
                    print("[AssemblyAI Live] Failed to create converted buffer with capacity \(outputFrameCapacity)")
                    return
                }

                var error: NSError?
                let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    outStatus.pointee = AVAudioConverterInputStatus.haveData
                    return buffer
                }

                // Ensure the converted buffer has the correct frame length
                if status == .haveData || status == .endOfStream {
                    // The converter should have set the frameLength, but let's verify it's not 0
                    if convertedBuffer.frameLength == 0 {
                        print("[AssemblyAI Live] Warning: Converter produced 0 frames, calculating expected length")
                        convertedBuffer.frameLength = outputFrameCapacity
                    }
                }

                if let error = error {
                    print("[AssemblyAI Live] Audio conversion error: \(error)")
                    return
                }

                if status == .error {
                    print("[AssemblyAI Live] Audio conversion failed with status: \(status)")
                    return
                }

                print("[AssemblyAI Live] Conversion successful: \(buffer.frameLength) → \(convertedBuffer.frameLength) frames")

                // Send audio data via WebSocket
                self.sendAudioData(convertedBuffer)
            }
        }

        print("[AssemblyAI Live] Installing audio tap and starting engine")
        audioEngine.prepare()
        try audioEngine.start()
        print("[AssemblyAI Live] Audio engine started successfully")
    }
    
    private func sendAudioData(_ buffer: AVAudioPCMBuffer) {
        guard isConnected else {
            print("[AssemblyAI Live] Not connected, skipping audio data")
            return
        }

        let frameLength = Int(buffer.frameLength)
        if frameLength == 0 {
            print("[AssemblyAI Live] ⚠️ Trying to send empty audio buffer")
            return
        }

        // Handle both PCM16 and Float32 formats
        let data: Data
        let audioLevel: Float

        if buffer.format.commonFormat == .pcmFormatInt16 {
            // PCM16 format (preferred for Universal-Streaming)
            guard let channelData = buffer.int16ChannelData?[0] else {
                print("[AssemblyAI Live] No PCM16 channel data available in buffer")
                return
            }

            data = Data(bytes: channelData, count: frameLength * 2) // 2 bytes per sample for 16-bit int

            // Calculate audio level for PCM16
            audioLevel = (0..<frameLength).reduce(0.0) { sum, i in
                sum + Float(abs(channelData[i])) / 32768.0 // Normalize to 0-1 range
            } / Float(frameLength)

        } else {
            // Float32 format (fallback)
            guard let channelData = buffer.floatChannelData?[0] else {
                print("[AssemblyAI Live] No Float32 channel data available in buffer")
                return
            }

            data = Data(bytes: channelData, count: frameLength * 4) // 4 bytes per sample for 32-bit float

            // Calculate audio level for Float32
            audioLevel = (0..<frameLength).reduce(0.0) { sum, i in
                sum + abs(channelData[i])
            } / Float(frameLength)
        }

        print("[AssemblyAI Live] Sending audio data: \(data.count) bytes (\(frameLength) frames) from \(buffer.format.channelCount) channel(s), format: \(buffer.format.commonFormat.rawValue), avg level: \(String(format: "%.6f", audioLevel))")

        // Send binary audio data directly (AssemblyAI Universal-Streaming expects PCM16 binary data)
        webSocketTask?.send(.data(data)) { error in
            if let error = error {
                print("[AssemblyAI Live] Failed to send audio data: \(error)")
                DispatchQueue.main.async {
                    self.isConnected = false
                }
            } else {
                // Successful send - log occasionally to avoid spam
                if frameLength > 0 && Int.random(in: 1...100) == 1 {
                    print("[AssemblyAI Live] ✅ Audio data sent successfully: \(frameLength) frames")
                }
            }
        }
    }
    
    private func stopAudioCapture() {
        print("[AssemblyAI Live] Stopping audio capture")
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            print("[AssemblyAI Live] Audio engine stopped")
        }

        // Don't deactivate the audio session since RecordingService is still using it
        print("[AssemblyAI Live] Leaving audio session active for RecordingService")
    }
    
    private func closeWebSocketConnection() {
        print("[AssemblyAI Live] Closing WebSocket connection")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        // Use weak self to avoid crash during deallocation
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
        }
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