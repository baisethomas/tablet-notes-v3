import SwiftUI
import AVFoundation
import Combine
import SwiftData
import Foundation

struct TimestampedNote: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: TimeInterval
}

// MARK: - Sacred Vellum Recording Indicator
// Soft breathing pulse using tertiary purple — 3s cycle per design spec.
private struct SVRecordingIndicator: View {
    let isPaused: Bool
    @State private var isBreathing = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.SV.tertiary)
                .frame(width: 7, height: 7)
                .opacity(isPaused ? 0.35 : (isBreathing ? 0.35 : 1.0))
                .animation(
                    isPaused ? .none : .easeInOut(duration: 3).repeatForever(autoreverses: true),
                    value: isBreathing
                )

            Text("REC")
                .font(.system(size: 12, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(Color.SV.onSurface.opacity(isPaused ? 0.35 : 0.6))
        }
        .onAppear { isBreathing = true }
    }
}

// MARK: - Recording View

enum RecordingFocus: Equatable {
    case split, notes, transcript
}

struct RecordingView: View {
    let serviceType: String
    @ObservedObject var noteService: NoteService
    var onNext: ((UUID) -> Void)?
    var sermonService: SermonService
    var recordingService: RecordingService
    @ObservedObject var transcriptionService: TranscriptionService

    private let recordingSessionId = UUID().uuidString

    @State private var showPermissionAlert = false
    @State private var permissionMessage = ""

    #if canImport(AVFoundation) && os(iOS)
    @StateObject private var scriptureAnalysisService = ScriptureAnalysisService()
    @State private var isRecordingStarted = false
    @State private var isPaused = false
    @State private var noteText: String = ""
    @State private var noteSaveTask: Task<Void, Never>? = nil
    @State private var transcript: String = ""
    @State private var detectedReferences: [ScriptureReference] = []
    @State private var selectedReference: ScriptureReference? = nil
    @State private var cancellables = Set<AnyCancellable>()
    @State private var notes: [Note] = []
    @State private var audioFileURL: URL? = nil
    @State private var isProcessingTranscript = false
    @State private var transcriptProcessingError: String? = nil
    @State private var sectionFocus: RecordingFocus = .split
    @FocusState private var isNotesFocused: Bool
    private let processingCoordinator = SermonProcessingCoordinator.shared
    #endif

    var body: some View {
        #if canImport(AVFoundation) && os(iOS)
        ZStack {
            Color.SV.surface.ignoresSafeArea()

            VStack(spacing: 0) {
                svTopBar
                svErrorBanner
                svNotesArea
                svAmbientTranscript
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .alert("Permission Required", isPresented: $showPermissionAlert) {
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(permissionMessage)
        }
        .onReceive(recordingService.isRecordingPublisher) { recording in
            withAnimation(.easeInOut(duration: 0.3)) {
                isRecordingStarted = recording
                if !recording { isPaused = false }
            }
            if !recording && !isProcessingTranscript {
                transcriptProcessingError = "Recording was interrupted. The audio may have been saved."
            }
        }
        .onReceive(recordingService.isPausedPublisher) { paused in
            withAnimation(.easeInOut(duration: 0.3)) {
                isPaused = paused
            }
        }
        .onReceive(recordingService.recordingStoppedPublisher) { (audioURL, wasAutoStopped) in
            if wasAutoStopped {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    isPaused = false
                    isRecordingStarted = false
                }
                transcriptionService.stopTranscription()
                if let url = audioURL {
                    let title = "Sermon on " + DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
                    processTranscription(title: title, date: Date(), url: url)
                }
            }
        }
        .onReceive(recordingService.audioFileURLPublisher) { url in
            audioFileURL = url
        }
        .onReceive(transcriptionService.transcriptPublisher) { newTranscript in
            withAnimation(.easeInOut(duration: 0.3)) {
                transcript = newTranscript
            }
            detectedReferences = scriptureAnalysisService.analyzeScriptureReferences(in: newTranscript)
        }
        .onReceive(noteService.notesPublisher) { updatedNotes in
            notes = updatedNotes
            // Load existing note text on first arrival (only if user hasn't typed anything)
            if noteText.isEmpty, let firstNote = updatedNotes.first {
                noteText = firstNote.text
            }
        }
        .onAppear {
            if recordingService.isRecording {
                isRecordingStarted = true
                isPaused = recordingService.isPaused
                try? transcriptionService.startTranscription()
            } else if isRecordingStarted {
                isRecordingStarted = false
                isPaused = false
                transcriptProcessingError = "Recording was interrupted. Please start a new recording."
            }
            // Load existing note
            if let existingNote = noteService.currentNotes.first {
                noteText = existingNote.text
            }
        }
        .sheet(item: $selectedReference) { ref in
            NavigationStack {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "book.closed")
                            .font(.largeTitle)
                            .foregroundStyle(Color.SV.primary)
                        Text(ref.raw)
                            .font(.system(size: 20, design: .serif))
                            .foregroundStyle(Color.SV.onSurface)
                        Text("Scripture Reference Detected")
                            .font(.caption)
                            .foregroundStyle(Color.SV.onSurface.opacity(0.5))
                    }
                    .padding()
                    Spacer()
                    Button("Add to Notes") {
                        noteText += noteText.isEmpty ? "📖 \(ref.raw)" : "\n\n📖 \(ref.raw)"
                        saveNoteText(noteText)
                        selectedReference = nil
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.SV.primary)
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 8))
                    .padding()
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { selectedReference = nil }
                    }
                }
            }
        }
        #else
        VStack {
            Text("Recording is not available on this platform")
                .foregroundStyle(.adaptiveSecondaryText)
        }
        #endif
    }

    // MARK: - Sacred Vellum Layout

    #if canImport(AVFoundation) && os(iOS)

    /// Minimal 3-element top bar: pause | ● REC | ✓
    private var svTopBar: some View {
        HStack {
            Button(action: handlePauseResume) {
                Image(systemName: isPaused ? "play" : "pause")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.7))
                    .frame(width: 44, height: 44)
            }

            Spacer()

            VStack(spacing: 4) {
                SVRecordingIndicator(isPaused: isPaused)
                if let remaining = recordingService.remainingTime, remaining < 300 {
                    Text(timeString(from: remaining) + " left")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.SV.error.opacity(0.8))
                        .transition(.opacity)
                }
            }

            Spacer()

            Button(action: handleDone) {
                if isProcessingTranscript {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.SV.primary))
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.SV.primary)
                        .frame(width: 44, height: 44)
                }
            }
            .disabled(isProcessingTranscript)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.SV.surface)
    }

    /// Subtle error/processing feedback strip shown below the top bar.
    @ViewBuilder
    private var svErrorBanner: some View {
        if let error = transcriptProcessingError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.SV.error)
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.SV.error.opacity(0.8))
                    .lineLimit(1)
                Spacer()
                if let url = audioFileURL {
                    Button("Retry") {
                        let title = "Sermon on " + DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
                        processTranscription(title: title, date: Date(), url: url)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.SV.primary)
                }
                Button {
                    withAnimation { transcriptProcessingError = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.4))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.SV.error.opacity(0.07))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Primary content: full-screen serif TextEditor with placeholder, focus-aware.
    @ViewBuilder
    private var svNotesArea: some View {
        if sectionFocus == .transcript {
            // Collapsed strip — notes is minimized
            HStack(spacing: 12) {
                Text("NOTES")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Color.SV.onSurface.opacity(0.35))
                Text(noteText.isEmpty ? "Tap to write notes" : noteText)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.25))
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
            .background(Color.SV.surface)
            .contentShape(Rectangle())
            .onTapGesture { handleFocusTap(tapped: .notes) }
        } else {
            // Full editor (split or notes-focused)
            VStack(spacing: 0) {
                HStack {
                    Text("NOTES")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(Color.SV.onSurface.opacity(0.35))
                    Spacer()
                    if sectionFocus == .notes {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.SV.onSurface.opacity(0.25))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture { handleFocusTap(tapped: .notes) }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $noteText)
                        .focused($isNotesFocused)
                        .font(.system(size: 20, design: .serif))
                        .foregroundStyle(Color.SV.onSurface)
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)

                    if noteText.isEmpty {
                        Text("Untitled Reflection")
                            .font(.system(size: 20, design: .serif))
                            .italic()
                            .foregroundStyle(Color.SV.onSurface.opacity(0.22))
                            .allowsHitTesting(false)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                }
                .padding(.horizontal, 20)
                .onChange(of: noteText) { _, newText in
                    scheduleNoteSave(newText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.SV.surface)
        }
    }

    /// Ambient transcription section with gradient fade divider, focus-aware.
    @ViewBuilder
    private var svAmbientTranscript: some View {
        if sectionFocus == .notes {
            // Collapsed strip — transcript is minimized
            HStack(spacing: 12) {
                Text("AMBIENT TRANSCRIPTION")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Color.SV.onSurface.opacity(0.35))
                Text(transcript.isEmpty ? "..." : transcript)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.35))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.25))
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
            .background(Color.SV.surfaceContainerLow)
            .contentShape(Rectangle())
            .onTapGesture { handleFocusTap(tapped: .transcript) }
        } else {
            // Full transcript (split or transcript-focused)
            VStack(spacing: 0) {
                // Gradient fade — only shown in split mode
                if sectionFocus == .split {
                    LinearGradient(
                        colors: [Color.SV.surface.opacity(0), Color.SV.surfaceContainerLow],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 36)
                }

                HStack {
                    Text("AMBIENT TRANSCRIPTION")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(Color.SV.onSurface.opacity(0.35))
                    Spacer()
                    if sectionFocus == .transcript {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.SV.onSurface.opacity(0.25))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.SV.surfaceContainerLow)
                .contentShape(Rectangle())
                .onTapGesture { handleFocusTap(tapped: .transcript) }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(transcript.isEmpty ? "...spoken words will appear here..." : transcript)
                                .font(.system(size: 15, design: .serif))
                                .foregroundStyle(Color.SV.onSurface.opacity(transcript.isEmpty ? 0.28 : 0.5))
                                .italic(transcript.isEmpty)
                                .lineSpacing(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 8)

                            // Sentinel view — always at the true bottom of content
                            Color.clear
                                .frame(height: 1)
                                .id("transcriptEnd")
                        }
                    }
                    .onChange(of: transcript) { _, _ in
                        DispatchQueue.main.async {
                            proxy.scrollTo("transcriptEnd", anchor: .bottom)
                        }
                    }
                }
                .frame(maxHeight: sectionFocus == .transcript ? .infinity : 220)
                .background(Color.SV.surfaceContainerLow)
                .mask(
                    LinearGradient(
                        colors: [.black, .black, .black.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }

    // MARK: - Interaction Handlers

    private func handleFocusTap(tapped: RecordingFocus) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        let next: RecordingFocus = sectionFocus == tapped ? .split : tapped

        if next != .notes { isNotesFocused = false }

        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            sectionFocus = next
        }

        if next == .notes {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isNotesFocused = true
            }
        }
    }

    private func handlePauseResume() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        if !isRecordingStarted {
            checkPermissions()
        } else if isPaused {
            resumeRecording()
        } else {
            pauseRecording()
        }
    }

    private func handleDone() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        noteSaveTask?.cancel()
        saveNoteText(noteText)
        stopRecording()
    }

    // MARK: - Note Persistence

    private func scheduleNoteSave(_ text: String) {
        noteSaveTask?.cancel()
        noteSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            await MainActor.run { saveNoteText(text) }
        }
    }

    private func saveNoteText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existingNote = notes.first {
            noteService.updateNote(id: existingNote.id, newText: trimmed.isEmpty ? " " : trimmed)
        } else if !trimmed.isEmpty {
            noteService.addNote(text: trimmed, timestamp: recordingService.recordingDuration)
        }
    }

    #endif

    // MARK: - Utilities

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

    // MARK: - Recording Control

    #if canImport(AVFoundation) && canImport(Speech) && os(iOS)

    private func checkPermissions() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                handleMicrophonePermission(granted: granted)
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                handleMicrophonePermission(granted: granted)
            }
        }
    }

    private func handleMicrophonePermission(granted: Bool) {
        guard granted else {
            permissionMessage = "Microphone access is required to record sermons. Please enable it in Settings."
            showPermissionAlert = true
            return
        }
        startRecording()
    }

    private func startRecording() {
        guard !recordingService.isRecording else { return }
        Task {
            let (canStart, reason) = await recordingService.canStartRecording()
            guard canStart else {
                await MainActor.run {
                    permissionMessage = reason ?? "Recording limit exceeded"
                    showPermissionAlert = true
                }
                return
            }
            do {
                recordingService.prepareRecoverySession(sessionId: noteService.sessionId)
                try await recordingService.startRecording(serviceType: serviceType)
                await MainActor.run {
                    do {
                        try transcriptionService.startTranscription()
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            isRecordingStarted = true
                        }
                    } catch {
                        permissionMessage = "Failed to start transcription: \(error.localizedDescription)"
                        showPermissionAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    let msg = (error as? RecordingError)?.localizedDescription ?? "Failed to start recording: \(error.localizedDescription)"
                    permissionMessage = msg
                    showPermissionAlert = true
                }
            }
        }
    }

    private func pauseRecording() {
        do {
            try recordingService.pauseRecording()
            withAnimation(.easeInOut(duration: 0.3)) { isPaused = true }
        } catch {
            print("[RecordingView] Failed to pause: \(error)")
        }
    }

    private func resumeRecording() {
        do {
            try recordingService.resumeRecording()
            withAnimation(.easeInOut(duration: 0.3)) { isPaused = false }
        } catch {
            print("[RecordingView] Failed to resume: \(error)")
        }
    }

    private func stopRecording() {
        let audioURL = recordingService.stopRecording()
        transcriptionService.stopTranscription()
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            isPaused = false
            isRecordingStarted = false
        }
        let title = "Sermon on " + DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        if let url = audioURL {
            processTranscription(title: title, date: Date(), url: url)
        }
    }

    private func processTranscription(title: String, date: Date, url: URL) {
        withAnimation(.easeInOut(duration: 0.5)) {
            isProcessingTranscript = true
            transcriptProcessingError = nil
        }
        let latestNotes = noteService.currentNotes
        processingCoordinator.handleCompletedRecording(
            audioURL: url,
            title: title,
            date: date,
            serviceType: serviceType,
            notes: latestNotes
        ) { savedId in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isProcessingTranscript = false
                    transcriptProcessingError = nil
                    transcript = ""
                    detectedReferences = []
                }
                onNext?(savedId)
            }
        }
    }

    #endif
}

#Preview {
    RecordingView(
        serviceType: "Sermon",
        noteService: NoteService(sessionId: UUID().uuidString),
        sermonService: SermonService(
            modelContext: try! ModelContext(ModelContainer(for: Sermon.self, Note.self, Transcript.self, Summary.self, ProcessingJob.self, TranscriptSegment.self)),
            authManager: AuthenticationManager.shared
        ),
        recordingService: RecordingService(),
        transcriptionService: TranscriptionService()
    )
}
