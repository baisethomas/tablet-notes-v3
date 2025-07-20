import SwiftUI
import AVFoundation
#if canImport(Speech)
import Speech
#endif
import Combine
import SwiftData
import Foundation

struct TimestampedNote: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: TimeInterval
}

// MARK: - Animated Waveform Component
struct WaveformView: View {
    let isRecording: Bool
    @State private var animationPhase: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isRecording ? Color.recordingRed : Color.adaptiveTertiaryText.opacity(0.3))
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(
                        isRecording ? 
                        Animation.easeInOut(duration: 0.5 + Double(index) * 0.1)
                            .repeatForever(autoreverses: true) : 
                        Animation.easeInOut(duration: 0.3),
                        value: isRecording
                    )
            }
        }
        .onAppear {
            startAnimation()
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startAnimation()
            }
        }
    }
    
    private func startAnimation() {
        withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
            animationPhase = 1
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 4
        let maxHeight: CGFloat = 24
        
        if !isRecording {
            return baseHeight
        }
        
        let phase = animationPhase * 2 * .pi + Double(index) * 0.8
        let variation = sin(phase) * 0.5 + 0.5
        return baseHeight + (maxHeight - baseHeight) * variation
    }
}

// MARK: - Loading State Component
struct LoadingStateView: View {
    let title: String
    let subtitle: String?
    @State private var rotation: Double = 0
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.adaptiveTertiaryText.opacity(0.3), lineWidth: 4)
                    .frame(width: 50, height: 50)
                
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.adaptiveAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(rotation))
                    .animation(Animation.linear(duration: 1).repeatForever(autoreverses: false), value: rotation)
            }
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.adaptivePrimaryText)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.adaptiveSecondaryText)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .onAppear {
            rotation = 360
        }
    }
}

// MARK: - Pulse Button Component
struct PulseButton: View {
    let action: () -> Void
    let isActive: Bool
    let systemImage: String
    let size: CGFloat
    let color: Color
    
    @State private var isPulsing = false
    
    var body: some View {
        Button(action: {
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            action()
        }) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: size + 20, height: size + 20)
                    .scaleEffect(isPulsing && isActive ? 1.2 : 1.0)
                    .opacity(isPulsing && isActive ? 0.3 : 0.2)
                    .animation(
                        isActive ? 
                        Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true) : 
                        Animation.easeInOut(duration: 0.3),
                        value: isPulsing
                    )
                
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            isPulsing = isActive
        }
        .onChange(of: isActive) { _, newValue in
            isPulsing = newValue
        }
    }
}

struct RecordingView: View {
    let serviceType: String
    @ObservedObject var noteService: NoteService
    var onNext: ((Sermon) -> Void)?
    @ObservedObject var sermonService: SermonService
    @ObservedObject var recordingService: RecordingService
    private let recordingSessionId = UUID().uuidString
    @State private var showPermissionAlert = false
    @State private var permissionMessage = ""
    #if canImport(AVFoundation) && os(iOS)
    @StateObject private var transcriptionService = TranscriptionService()
    @StateObject private var scriptureAnalysisService = ScriptureAnalysisService()
    @State private var timer: Timer? = nil
    @State private var elapsedTime: TimeInterval = 0
    @State private var isRecordingStarted = false
    @State private var isPaused = false
    @State private var showNoteSheet = false
    @State private var noteText: String = ""
    @State private var currentNoteID: UUID? = nil
    @State private var transcript: String = ""
    @State private var detectedReferences: [ScriptureReference] = []
    @State private var selectedReference: ScriptureReference? = nil
    @State private var cancellables = Set<AnyCancellable>()
    @State private var notes: [Note] = []
    @State private var audioFileURL: URL? = nil
    @State private var isProcessingTranscript = false
    @State private var transcriptProcessingError: String? = nil
    @StateObject private var summaryService = SummaryService()
    @State private var latestSummaryText: String? = nil
    #endif
    
    // Computed properties for the main button
    private var buttonColor: Color {
        if !isRecordingStarted {
            return .recordingRed
        } else if isPaused {
            return .successGreen
        } else {
            return .warningOrange
        }
    }
    
    private var buttonIcon: String {
        if !isRecordingStarted {
            return "mic.fill"
        } else if isPaused {
            return "play.fill"
        } else {
            return "pause.fill"
        }
    }

    var body: some View {
        #if canImport(AVFoundation) && os(iOS)
        ZStack {
            Color.recordingBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                HeaderView(title: "Recording", showLogo: true, showSearch: false, showSyncStatus: false, showBack: false)
                
                // Top controls bar
                HStack(spacing: 16) {
                    // Record/Pause button
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        
                        if !isRecordingStarted {
                            checkPermissions()
                        } else if isPaused {
                            resumeRecording()
                        } else {
                            pauseRecording()
                        }
                    }) {
                        Circle()
                            .fill(buttonColor)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: buttonIcon)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                            )
                    }
                    
                    // Animated waveform
                    WaveformView(isRecording: isRecordingStarted && !isPaused)
                        .frame(height: 20)
                    
                    Spacer()
                    
                    // Timer
                    Text(timeString(from: elapsedTime))
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundColor(isRecordingStarted ? .recordingRed : .adaptivePrimaryText)
                    
                    // Stop button (when recording)
                    if isRecordingStarted {
                        Button(action: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            stopRecording()
                        }) {
                            Circle()
                                .stroke(Color.red, lineWidth: 2)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.red)
                                        .frame(width: 12, height: 12)
                                )
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.adaptiveSecondaryBackground.opacity(0.3))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isRecordingStarted)
                
                // Live transcript area
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if transcript.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 48))
                                    .foregroundColor(.adaptiveSecondaryText.opacity(0.5))
                                
                                VStack(spacing: 8) {
                                    Text("Live Transcript")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.adaptivePrimaryText)
                                    
                                    Text(isRecordingStarted ? "Start speaking to see live transcription..." : "Tap record to begin")
                                        .font(.subheadline)
                                        .foregroundColor(.adaptiveSecondaryText)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "text.bubble.fill")
                                        .foregroundColor(.adaptiveAccent)
                                    Text("Live Transcript")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.adaptivePrimaryText)
                                    Spacer()
                                    Text("Live")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.successGreen)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.successGreen.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                
                                Text(transcript)
                                    .font(.body)
                                    .foregroundColor(.adaptivePrimaryText)
                                    .lineSpacing(4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .padding()
                            .background(Color.transcriptionBackground)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                        }
                        
                        // Processing state
                        if isProcessingTranscript {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .adaptiveAccent))
                                Text("Processing final transcript...")
                                    .font(.subheadline)
                                    .foregroundColor(.adaptiveSecondaryText)
                                Spacer()
                            }
                            .padding()
                            .background(Color.adaptiveSecondaryBackground.opacity(0.5))
                            .cornerRadius(12)
                            .transition(.opacity.combined(with: .scale))
                        }
                        
                        if let error = transcriptProcessingError {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.warningOrange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Processing Failed")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.adaptivePrimaryText)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.adaptiveSecondaryText)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Color.warningOrange.opacity(0.1))
                            .cornerRadius(12)
                            .transition(.opacity.combined(with: .scale))
                        }
                    }
                    .padding()
                    .padding(.bottom, 100)
                }
                .background(Color.adaptiveBackground)
            }
            
            // Floating Action Button for notes
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        showNoteSheet = true
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.adaptiveAccent)
                                .frame(width: 56, height: 56)
                                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                            
                            Image(systemName: "note.text")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                            
                            // Badge for note count
                            if !notes.isEmpty {
                                Circle()
                                    .fill(Color.recordingRed)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Text("\(notes.count)")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                    )
                                    .offset(x: 20, y: -20)
                            }
                        }
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 120)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .alert("Permission Required", isPresented: $showPermissionAlert) {
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(permissionMessage)
        }
        .onReceive(recordingService.isRecordingPublisher) { isRecording in
            // Handle recording state changes
        }
        .onReceive(recordingService.audioFileURLPublisher) { url in
            audioFileURL = url
            print("[RecordingView] Captured audioFileURL: \(url)")
        }
        .onReceive(transcriptionService.transcriptPublisher) { newTranscript in
            withAnimation(.easeInOut(duration: 0.3)) {
                transcript = newTranscript
            }
            detectedReferences = scriptureAnalysisService.analyzeScriptureReferences(in: newTranscript)
        }
        .onReceive(noteService.notesPublisher) { updatedNotes in
            withAnimation(.easeInOut(duration: 0.3)) {
                notes = updatedNotes
            }
        }
        .sheet(isPresented: $showNoteSheet) {
            NavigationView {
                ZStack(alignment: .bottomTrailing) {
                    VStack(spacing: 0) {
                        // Clean minimal header
                        HStack {
                            Image(systemName: "note.text")
                                .foregroundColor(.adaptiveAccent)
                            Text("Notes")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.adaptivePrimaryText)
                            Spacer()
                            Text(timeString(from: elapsedTime))
                                .font(.caption)
                                .foregroundColor(.adaptiveSecondaryText)
                        }
                        .padding()
                        
                        // Clean text editor - no outline, no background
                        TextEditor(text: $noteText)
                            .font(.body)
                            .padding()
                            .background(Color.clear)
                            .scrollContentBackground(.hidden)
                        
                        // Action buttons
                        HStack(spacing: 16) {
                            Button("Cancel") {
                                showNoteSheet = false
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.adaptiveSecondaryBackground)
                            .foregroundColor(.adaptivePrimaryText)
                            .cornerRadius(12)
                            
                            Button("Save") {
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                
                                let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    // Update the single continuous note
                                    if let existingNote = notes.first {
                                        noteService.updateNote(id: existingNote.id, newText: trimmed)
                                    } else {
                                        noteService.addNote(text: trimmed, timestamp: elapsedTime)
                                    }
                                }
                                showNoteSheet = false
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.adaptiveAccent)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding()
                    }
                    
                    // Bible FAB positioned in bottom right of the sheet
                    BibleFAB { reference, content in
                        insertScriptureIntoNote(reference: reference, content: content)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 100)
                }
                .navigationTitle("")
                .navigationBarHidden(true)
                .onAppear {
                    // Load the single continuous note
                    if let existingNote = notes.first {
                        noteText = existingNote.text
                    } else {
                        noteText = ""
                    }
                }
            }
        }
        // Scripture reference sheet with improved styling
        .sheet(item: $selectedReference) { ref in
            NavigationView {
                VStack(spacing: 20) {
                    // Reference header
                    VStack(spacing: 8) {
                        Image(systemName: "book.closed")
                            .font(.largeTitle)
                            .foregroundColor(.adaptiveAccent)
                        Text(ref.raw)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.adaptivePrimaryText)
                        Text("Scripture Reference Detected")
                            .font(.caption)
                            .foregroundColor(.adaptiveSecondaryText)
                    }
                    .padding()
                    .background(Color.adaptiveAccent.opacity(0.1))
                    .cornerRadius(16)
                    
                    // Context
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Context")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.adaptivePrimaryText)
                        Text(ref.raw) // Display scripture reference
                            .font(.body)
                            .foregroundColor(.adaptivePrimaryText)
                            .padding()
                            .background(Color.adaptiveSecondaryBackground)
                            .cornerRadius(12)
                    }
                    
                    Spacer()
                    
                    // Action button
                    Button("Add to Notes") {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        
                        noteService.addNote(text: "Scripture: \(ref.raw)", timestamp: elapsedTime)
                        selectedReference = nil
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.adaptiveAccent)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding()
                }
                .padding()
                .navigationTitle("Scripture Reference")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            selectedReference = nil
                        }
                    }
                }
            }
        }
        .onAppear {
            // Check if recording is already in progress from MainAppView
            if recordingService.isRecording {
                print("[RecordingView] Recording already in progress, setting up UI state")
                isRecordingStarted = true
                try? transcriptionService.startTranscription()
                startTimer()
            }
        }
        #else
        VStack {
            Text("Recording is not available on this platform")
                .foregroundColor(.adaptiveSecondaryText)
        }
        #endif
    }

    private func timeString(from interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = Int(interval) % 3600 / 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    #if canImport(AVFoundation) && canImport(Speech) && os(iOS)
    private func checkPermissions() {
        print("[RecordingView] checkPermissions called")
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                print("[RecordingView] Microphone permission granted: \(granted)")
                handleMicrophonePermission(granted: granted)
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                print("[RecordingView] Microphone permission granted: \(granted)")
                handleMicrophonePermission(granted: granted)
            }
        }
    }

    private func handleMicrophonePermission(granted: Bool) {
        if !granted {
            print("[RecordingView] Microphone permission denied")
            permissionMessage = "Microphone access is required to record sermons. Please enable it in Settings."
            showPermissionAlert = true
            return
        }
        SFSpeechRecognizer.requestAuthorization { authStatus in
            print("[RecordingView] Speech recognition status: \(authStatus.rawValue)")
            if authStatus != .authorized {
                permissionMessage = "Speech recognition access is required to transcribe sermons. Please enable it in Settings."
                showPermissionAlert = true
            } else {
                DispatchQueue.main.async {
                    print("[RecordingView] Permissions granted, starting recording...")
                    startRecording()
                }
            }
        }
    }

    private func startRecording() {
        print("[RecordingView] startRecording called")
        guard !recordingService.isRecording else { print("[RecordingView] Already recording"); return }
        do {
            try recordingService.startRecording(serviceType: serviceType)
            try transcriptionService.startTranscription()
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isRecordingStarted = true
            }
            elapsedTime = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { _ in
                // Only increment time if recording and not paused
                if isRecordingStarted && !isPaused {
                    elapsedTime += 1
                }
            })
            print("[RecordingView] Recording started")
        } catch {
            permissionMessage = "Failed to start recording: \(error.localizedDescription)"
            showPermissionAlert = true
            print("[RecordingView] Failed to start recording: \(error)")
        }
    }

    private func pauseRecording() {
        do {
            try recordingService.pauseRecording()
            withAnimation(.easeInOut(duration: 0.3)) {
                isPaused = true
            }
        } catch {
            print("[RecordingView] Failed to pause recording: \(error)")
        }
    }
    
    private func resumeRecording() {
        do {
            try recordingService.resumeRecording()
            withAnimation(.easeInOut(duration: 0.3)) {
                isPaused = false
            }
        } catch {
            print("[RecordingView] Failed to resume recording: \(error)")
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            // Only increment time if recording and not paused
            if isRecordingStarted && !isPaused {
                elapsedTime += 1
            }
        }
    }
    
    private func stopRecording() {
        recordingService.stopRecording()
        transcriptionService.stopTranscription()
        timer?.invalidate()
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            isPaused = false
            isRecordingStarted = false
        }
        
        let title = "Sermon on " + DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        let date = Date()
        if let url = audioFileURL {
            withAnimation(.easeInOut(duration: 0.5)) {
                isProcessingTranscript = true
                transcriptProcessingError = nil
            }
            
            transcriptionService.transcribeAudioFile(url: url) { text, segments in
                print("[RecordingView] Vercel transcription callback fired.")
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        isProcessingTranscript = false
                    }
                    
                    if let text = text {
                        print("[RecordingView] Vercel transcription succeeded. Text length: \(text.count), Segments count: \(segments.count)")
                        transcript = text
                        detectedReferences = scriptureAnalysisService.analyzeScriptureReferences(in: text)
                        handleTranscriptionResult(title: title, date: date, url: url)(text, segments)
                    } else {
                        print("[RecordingView] Vercel transcription failed.")
                        withAnimation(.easeInOut(duration: 0.5)) {
                            transcriptProcessingError = "Failed to process audio. Please try again."
                        }
                    }
                }
            }
        }
    }

    private func handleTranscriptionResult(title: String, date: Date, url: URL) -> (String?, [TranscriptSegment]) -> Void {
        return { text, segments in
            guard let text = text else { return }
            let transcriptModel = Transcript(text: text, segments: segments)
            let summaryModel = Summary(text: "", type: serviceType, status: "processing")
            let sermonId = UUID()
            print("[DEBUG] handleTranscriptionResult: creating sermon with transcriptionStatus = complete")
            sermonService.saveSermon(
                title: title,
                audioFileURL: url,
                date: date,
                serviceType: serviceType,
                speaker: nil, // Default nil speaker for new recordings
                transcript: transcriptModel,
                notes: notes,
                summary: summaryModel,
                transcriptionStatus: "complete",
                summaryStatus: "processing",
                id: sermonId
            )
            
            // 🔥 TRIGGER SUMMARIZATION - This was missing!
            print("[RecordingView] Starting summarization for transcript length: \(text.count)")
            let summaryService = SummaryService()
            summaryService.generateSummary(for: text, type: serviceType)
            
            // Listen for summary completion and update the sermon
            summaryService.summaryPublisher
                .combineLatest(summaryService.statusPublisher)
                .sink { summaryText, status in
                    print("[RecordingView] Summary status update: \(status)")
                    if status == "complete", let summaryText = summaryText {
                        print("[RecordingView] Summary completed, updating sermon...")
                        let updatedSummary = Summary(text: summaryText, type: serviceType, status: "complete")
                        sermonService.saveSermon(
                            title: title,
                            audioFileURL: url,
                            date: date,
                            serviceType: serviceType,
                            speaker: nil,
                            transcript: transcriptModel,
                            notes: notes,
                            summary: updatedSummary,
                            transcriptionStatus: "complete",
                            summaryStatus: "complete",
                            id: sermonId
                        )
                    } else if status == "failed" {
                        print("[RecordingView] Summary failed, updating sermon status...")
                        let failedSummary = Summary(text: summaryText ?? "Summary generation failed", type: serviceType, status: "failed")
                        sermonService.saveSermon(
                            title: title,
                            audioFileURL: url,
                            date: date,
                            serviceType: serviceType,
                            speaker: nil,
                            transcript: transcriptModel,
                            notes: notes,
                            summary: failedSummary,
                            transcriptionStatus: "complete",
                            summaryStatus: "failed",
                            id: sermonId
                        )
                    }
                }
                .store(in: &cancellables)
            
            // Create a minimal sermon object for the callback
            // Note: This is just for the callback - the actual sermon is saved via SermonService
            Task { @MainActor in
                if let currentUser = AuthenticationManager.shared.currentUser {
                    let callbackSermon = Sermon(
                        id: sermonId,
                        title: title,
                        audioFileURL: url,
                        date: date,
                        serviceType: serviceType,
                        speaker: nil,
                        transcript: transcriptModel,
                        notes: notes,
                        summary: summaryModel,
                        transcriptionStatus: "complete",
                        summaryStatus: "processing",
                        userId: currentUser.id
                    )
                    
                    onNext?(callbackSermon)
                }
            }
        }
    }
    
    // MARK: - Scripture Insertion
    
    private func insertScriptureIntoNote(reference: ScriptureReference, content: String) {
        let scriptureText = """
        📖 \(reference.displayText)
        \(content)
        """
        
        // Insert scripture into the note text
        if noteText.isEmpty {
            noteText = scriptureText
        } else {
            // Add some spacing and append the scripture
            noteText += "\n\n" + scriptureText
        }
        
        // Save the updated note immediately
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if let existingNote = notes.first {
                noteService.updateNote(id: existingNote.id, newText: trimmed)
            } else {
                noteService.addNote(text: trimmed, timestamp: elapsedTime)
            }
        }
        
        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    #endif
}

#Preview {
    RecordingView(serviceType: "Sermon", noteService: NoteService(sessionId: UUID().uuidString), sermonService: SermonService(modelContext: try! ModelContext(ModelContainer(for: Sermon.self)), authManager: AuthenticationManager.shared), recordingService: RecordingService())
}
