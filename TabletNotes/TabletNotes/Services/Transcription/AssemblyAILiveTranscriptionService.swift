import Foundation
import AVFoundation
import Combine
import Observation

@Observable
class AssemblyAILiveTranscriptionService: NSObject, @unchecked Sendable {
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioEngine = AVAudioEngine()
    private let transcriptSubject = CurrentValueSubject<String, Never>("")
    private var fullTranscript: String = ""
    private var sessionToken: String?
    private let supabase = SupabaseService.shared
    private var wasInterrupted = false
    private var tokenRenewalTimer: Timer?
    private var sessionStartTime: Date?
    private let audioProcessingQueue = DispatchQueue(label: "com.tabletnotes.audioprocessing", qos: .userInitiated)
    private let networkMonitor = NetworkMonitor.shared
    private var networkObservationTask: Task<Void, Never>?

    var transcriptPublisher: AnyPublisher<String, Never> {
        transcriptSubject.eraseToAnyPublisher()
    }

    // Observable properties (no @Published needed with @Observable)
    var isConnected = false
    var error: String?

    private let sampleRate: Double = 44100 // Use higher quality audio
    private var connectionAttempts = 0
    private let maxConnectionAttempts = 3
    private let tokenRenewalInterval: TimeInterval = 480 // Renew token every 8 minutes (before 10-minute expiration)

    override init() {
        super.init()
        setupAudioInterruptionObserver()
        setupNetworkObserver()
    }

    private func setupNetworkObserver() {
        // Monitor network changes and attempt reconnection when network returns
        networkObservationTask = Task { [weak self] in
            guard let self = self else { return }

            var previouslyConnected = networkMonitor.isConnected

            // Poll network status periodically
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Check every second

                let currentlyConnected = networkMonitor.isConnected

                // Network transitioned from disconnected to connected
                if !previouslyConnected && currentlyConnected && wasInterrupted {
                    print("[AssemblyAI Live] Network restored, attempting to reconnect...")
                    await attemptReconnection()
                }

                previouslyConnected = currentlyConnected
            }
        }
    }

    private func attemptReconnection() async {
        guard wasInterrupted && networkMonitor.isConnected else { return }

        print("[AssemblyAI Live] Attempting to reconnect WebSocket after network restoration...")

        do {
            // Get a new session token
            try await getSessionToken()

            // Reconnect WebSocket
            try await startWebSocketConnection()

            // Restart audio capture if needed
            if !audioEngine.isRunning {
                try startAudioCapture()
            }

            wasInterrupted = false
            print("[AssemblyAI Live] ✅ Reconnection successful")

            await MainActor.run {
                self.error = nil
            }
        } catch {
            print("[AssemblyAI Live] ⚠️ Reconnection failed: \(error)")
            // Will try again on next network check
        }
    }
    
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

        // Start token renewal timer
        startTokenRenewalTimer()

        // Note: isConnected will be set to true when we receive "SessionBegins" message
    }
    
    func stopLiveTranscription() {
        stopTokenRenewalTimer()
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
        request.timeoutInterval = 10 // 10 second timeout to prevent hanging

        // Get auth token with automatic refresh
        do {
            let session = try await supabase.client.auth.session
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            print("[AssemblyAI Live] Using authenticated session for live transcription")
        } catch {
            // Token might be expired, try to refresh
            print("[AssemblyAI Live] Session expired or invalid, attempting to refresh token...")
            do {
                let refreshedSession = try await supabase.client.auth.refreshSession()
                request.setValue("Bearer \(refreshedSession.accessToken)", forHTTPHeaderField: "Authorization")
                print("[AssemblyAI Live] Token refreshed successfully")
            } catch {
                print("[AssemblyAI Live] Token refresh failed: \(error.localizedDescription)")
                // Don't continue without auth - throw error instead
                throw NSError(domain: "AuthError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication required. Please sign in to use live transcription."])
            }
        }

        let (data, response) = try await NetworkRetry.withExponentialBackoff(maxAttempts: 2) {
            try await URLSession.shared.data(for: request)
        }

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

        // Use v3 streaming API endpoint with query parameters
        guard let url = URL(string: "https://streaming.assemblyai.com/v3/token?expires_in_seconds=600&max_session_duration_seconds=10800") else {
            throw NSError(domain: "InvalidURL", code: 1, userInfo: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(AssemblyAIConfig.apiKey, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10 // 10 second timeout to prevent hanging

        let (data, response) = try await NetworkRetry.withExponentialBackoff(maxAttempts: 2) {
            try await URLSession.shared.data(for: request)
        }

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
        // Ensure we have a session token
        guard let token = sessionToken else {
            throw NSError(domain: "NoSessionToken", code: 1, userInfo: [NSLocalizedDescriptionKey: "No session token available"])
        }

        // Determine the actual sample rate we'll be sending
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        let inputSampleRate = recordingFormat.sampleRate

        // Use input sample rate if supported by AssemblyAI, otherwise use target rate
        let supportedRates: [Double] = [8000, 16000, 22050, 44100, 48000]
        let actualSampleRate = supportedRates.contains(inputSampleRate) ? inputSampleRate : sampleRate

        // Connect to Universal-Streaming v3 using the session token
        var urlComponents = URLComponents(string: "wss://streaming.assemblyai.com/v3/ws")!
        urlComponents.queryItems = [
            URLQueryItem(name: "sample_rate", value: String(Int(actualSampleRate))),
            URLQueryItem(name: "encoding", value: "pcm_s16le"),
            URLQueryItem(name: "token", value: token)
        ]

        guard let url = urlComponents.url else {
            throw NSError(domain: "InvalidWebSocketURL", code: 1, userInfo: nil)
        }

        print("[AssemblyAI Live] Connecting to Universal-Streaming v3 with \(Int(actualSampleRate))Hz using session token")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)

        let request = URLRequest(url: url)
        // No Authorization header needed when using token query parameter

        webSocketTask = session.webSocketTask(with: request)

        // Add connection state tracking
        webSocketTask?.resume()

        // Record session start time for token renewal
        sessionStartTime = Date()

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
                self?.handleWebSocketDisconnection(error: error)
                // Don't continue listening on failure
            }
        }
    }

    private func handleWebSocketDisconnection(error: Error) {
        print("[AssemblyAI Live] Handling WebSocket disconnection: \(error.localizedDescription)")

        // Stop audio capture immediately to prevent further send attempts
        stopAudioCapture()

        // Close the WebSocket connection
        closeWebSocketConnection()

        Task { @MainActor in
            self.isConnected = false

            // Determine if it's a network error
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                self.wasInterrupted = true // Mark for reconnection when network returns
                self.error = "Network connection lost. Recording continues, will reconnect when network returns."
                print("[AssemblyAI Live] Network error detected, will attempt reconnection when network is available")
            } else {
                self.error = error.localizedDescription
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
        guard isConnected, webSocketTask != nil else {
            // Silently skip if not connected or WebSocket is nil
            return
        }

        let frameLength = Int(buffer.frameLength)

        // Validate frame length is reasonable (not 0 and not absurdly large)
        guard frameLength > 0 && frameLength <= 65536 else {
            print("[AssemblyAI Live] ⚠️ Invalid frame length: \(frameLength)")
            return
        }

        // Handle both PCM16 and Float32 formats
        let data: Data

        if buffer.format.commonFormat == .pcmFormatInt16 {
            // PCM16 format (preferred for Universal-Streaming)
            guard let channelData = buffer.int16ChannelData?[0] else {
                print("[AssemblyAI Live] No PCM16 channel data available in buffer")
                return
            }

            // Validate the pointer is not null and copy data immediately
            let byteCount = frameLength * 2 // 2 bytes per sample for 16-bit int
            guard byteCount > 0 && byteCount <= 131072 else { // Max ~64K frames * 2 bytes
                print("[AssemblyAI Live] Invalid byte count: \(byteCount)")
                return
            }

            data = Data(bytes: channelData, count: byteCount)

        } else {
            // Float32 format (fallback)
            guard let channelData = buffer.floatChannelData?[0] else {
                print("[AssemblyAI Live] No Float32 channel data available in buffer")
                return
            }

            // Validate and copy data immediately
            let byteCount = frameLength * 4 // 4 bytes per sample for 32-bit float
            guard byteCount > 0 && byteCount <= 262144 else { // Max ~64K frames * 4 bytes
                print("[AssemblyAI Live] Invalid byte count: \(byteCount)")
                return
            }

            data = Data(bytes: channelData, count: byteCount)
        }

        // Log occasionally to monitor without spam
        if Int.random(in: 1...100) == 1 {
            print("[AssemblyAI Live] Sending audio data: \(data.count) bytes (\(frameLength) frames)")
        }

        // Send binary audio data directly (AssemblyAI Universal-Streaming expects PCM16 binary data)
        webSocketTask?.send(.data(data)) { [weak self] error in
            if let error = error {
                print("[AssemblyAI Live] Failed to send audio data: \(error)")
                guard let self = self else { return }
                Task { @MainActor in
                    self.isConnected = false
                    self.wasInterrupted = true
                }
            }
        }
    }
    
    private func stopAudioCapture() {
        print("[AssemblyAI Live] Stopping audio capture")

        // Stop the audio engine first to prevent new callbacks
        if audioEngine.isRunning {
            audioEngine.stop()
            print("[AssemblyAI Live] Audio engine stopped")
        }

        // Remove the tap synchronously to ensure no more callbacks fire
        // This must be done even if the engine is not running to clean up properly
        audioEngine.inputNode.removeTap(onBus: 0)
        print("[AssemblyAI Live] Audio tap removed")

        // Don't deactivate the audio session since RecordingService is still using it
        print("[AssemblyAI Live] Leaving audio session active for RecordingService")
    }
    
    private func closeWebSocketConnection() {
        print("[AssemblyAI Live] Closing WebSocket connection")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        // Set isConnected directly if on main thread, otherwise skip during deallocation
        if Thread.isMainThread {
            isConnected = false
        } else {
            // Don't dispatch to main thread during deallocation - can cause crashes
            // The published property will be cleaned up with the object
            print("[AssemblyAI Live] Skipping isConnected update (not on main thread)")
        }
    }
    
    private func setupAudioInterruptionObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            print("[AssemblyAI Live] Audio session interrupted (phone call, alarm, etc.)")
            if isConnected && audioEngine.isRunning {
                // Mark that we were interrupted
                wasInterrupted = true

                // Stop the audio engine
                audioEngine.stop()
                audioEngine.inputNode.removeTap(onBus: 0)
                print("[AssemblyAI Live] Audio engine stopped due to interruption")
            }

        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                print("[AssemblyAI Live] Interruption ended but no options provided")
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            if options.contains(.shouldResume) && wasInterrupted && isConnected {
                print("[AssemblyAI Live] Resuming audio engine after interruption")
                do {
                    // Reactivate audio session
                    try AVAudioSession.sharedInstance().setActive(true)

                    // Restart audio capture
                    try startAudioCapture()

                    wasInterrupted = false
                    print("[AssemblyAI Live] Audio engine resumed successfully")
                } catch {
                    print("[AssemblyAI Live] Failed to resume audio engine after interruption: \(error)")
                    DispatchQueue.main.async {
                        self.error = "Failed to resume live transcription after interruption"
                    }
                }
            } else {
                print("[AssemblyAI Live] Interruption ended but should not resume")
                wasInterrupted = false
            }

        @unknown default:
            break
        }
    }

    // MARK: - Token Renewal

    private func startTokenRenewalTimer() {
        print("[AssemblyAI Live] Starting token renewal timer (will renew every \(tokenRenewalInterval) seconds)")
        stopTokenRenewalTimer() // Ensure no duplicate timers

        tokenRenewalTimer = Timer.scheduledTimer(withTimeInterval: tokenRenewalInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            print("[AssemblyAI Live] Token renewal timer fired")
            Task {
                await self.renewSessionToken()
            }
        }
    }

    private func stopTokenRenewalTimer() {
        tokenRenewalTimer?.invalidate()
        tokenRenewalTimer = nil
        sessionStartTime = nil
        print("[AssemblyAI Live] Token renewal timer stopped")
    }

    private func renewSessionToken() async {
        guard isConnected else {
            print("[AssemblyAI Live] Skipping token renewal - not connected")
            return
        }

        print("[AssemblyAI Live] Renewing session token...")

        do {
            // Get a new session token
            let oldToken = sessionToken
            try await getSessionToken()

            // Only reconnect if we got a new token
            if sessionToken != oldToken, let newToken = sessionToken {
                print("[AssemblyAI Live] Got new session token, reconnecting WebSocket...")

                // Close old WebSocket
                webSocketTask?.cancel(with: .goingAway, reason: nil)
                webSocketTask = nil

                // Reconnect with new token
                try await startWebSocketConnection()

                print("[AssemblyAI Live] ✅ Session token renewed and reconnected successfully")
            }
        } catch {
            print("[AssemblyAI Live] ⚠️ Failed to renew session token: \(error)")
            // Don't stop transcription on renewal failure - the existing token might still work
            // The WebSocket will handle disconnection if the token expires
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopTokenRenewalTimer()
        stopLiveTranscription()
        networkObservationTask?.cancel()
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
