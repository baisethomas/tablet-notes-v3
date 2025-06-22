import SwiftUI
import AVFoundation
#if canImport(Speech)
import Speech
#endif
import Combine
import SwiftData
import Foundation

// Add these imports if needed for model and service types
// import TabletNotes.Models // Uncomment if models are in a separate module
// import TabletNotes.Services // Uncomment if services are in a separate module
// Ensure TabletNotes/TabletNotes/Models/Sermon.swift is included in the build target
// Ensure TabletNotes/TabletNotes/Services/SermonService.swift is included in the build target

struct TimestampedNote: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: TimeInterval
}

struct RecordingView: View {
    let serviceType: String
    @ObservedObject var noteService: NoteService
    var onNext: ((Sermon) -> Void)?
    @ObservedObject var sermonService: SermonService
    @State private var showPermissionAlert = false
    @State private var permissionMessage = ""
    #if canImport(AVFoundation) && os(iOS)
    @StateObject private var recordingService = RecordingService()
    @StateObject private var transcriptionService = TranscriptionService()
    @StateObject private var scriptureAnalysisService = ScriptureAnalysisService()
    @State private var timer: Timer? = nil
    @State private var elapsedTime: TimeInterval = 0
    @State private var isRecordingStarted = false
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

    var body: some View {
        #if canImport(AVFoundation) && os(iOS)
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                HeaderView(title: "Recording", showLogo: true, showSearch: false, showSettings: true, showBack: false)
                // Recorder controls at the top
                if recordingService.isRecording {
                    HStack(alignment: .center, spacing: 16) {
                        Button(action: { /* Pause/Resume logic here if needed */ }) {
                            Image(systemName: "pause.fill")
                                .font(.title2)
                        }
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                        Text(timeString(from: elapsedTime))
                            .font(.title2)
                            .foregroundColor(.red)
                        Spacer()
                        Button(action: { stopRecording() }) {
                            Image(systemName: "stop.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding([.horizontal, .top], 16)
                } else {
                    HStack {
                        Text("Not Recording")
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding([.horizontal, .top], 16)
                }
                // Transcription area fills available space
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcript:")
                        .font(.headline)
                    ScrollView {
                        Text(transcript)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 100)
                    }
                    .frame(maxHeight: .infinity)
                    if !detectedReferences.isEmpty {
                        Divider()
                        Text("Scripture References Detected:")
                            .font(.headline)
                        ForEach(detectedReferences) { ref in
                            Button(action: {
                                selectedReference = ref
                            }) {
                                Text(ref.raw)
                                    .foregroundColor(.blue)
                                    .underline()
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                Spacer(minLength: 0)
            }
            // Floating action button for notes
            Button(action: {
                showNoteSheet = true
            }) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 56, height: 56)
                        .shadow(radius: 4)
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                        .font(.title)
                }
            }
            .padding(.trailing, 24)
            .padding(.bottom, 80)
            .accessibilityLabel("Add Note")
            // Sheet for adding a note (no timestamp)
            .sheet(isPresented: $showNoteSheet, onDismiss: {
                // No need to clear noteText; keep it for this recording session
            }) {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button(action: { showNoteSheet = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                    TextEditor(text: $noteText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal)
                        .onChange(of: noteText) { oldValue, newValue in
                            if let noteID = currentNoteID {
                                noteService.updateNote(id: noteID, newText: newValue)
                            } else if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                noteService.addNote(text: newValue, timestamp: 0)
                                // Find the new note and track its ID
                                if let newNote = notes.first {
                                    currentNoteID = newNote.id
                                }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
                .onAppear {
                    // Load the note for this recording session if it exists
                    if let existingNote = notes.first {
                        noteText = existingNote.text
                        currentNoteID = existingNote.id
                    } else {
                        noteText = ""
                        currentNoteID = nil
                    }
                }
            }
            // Scripture reference sheet
            .sheet(item: $selectedReference) { ref in
                VStack(spacing: 16) {
                    Text(ref.raw)
                        .font(.title2)
                        .bold()
                    Text("Book: \(ref.book)")
                    Text("Chapter: \(ref.chapter)")
                    Text("Verse: \(ref.verseStart)" + (ref.verseEnd != nil ? "-\(ref.verseEnd!)" : ""))
                    Button("Close") {
                        selectedReference = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            print("[RecordingView] onAppear")
            checkPermissions()
            #if canImport(Combine)
            transcriptionService.transcriptPublisher
                .receive(on: RunLoop.main)
                .sink { value in
                    transcript = value
                    detectedReferences = scriptureAnalysisService.analyzeScriptureReferences(in: value)
                }
                .store(in: &cancellables)
            noteService.notesPublisher
                .receive(on: RunLoop.main)
                .sink { value in
                    notes = value
                }
                .store(in: &cancellables)
            recordingService.audioFileURLPublisher
                .receive(on: RunLoop.main)
                .sink { url in
                    audioFileURL = url
                    print("[RecordingView] Captured audioFileURL: \(String(describing: url))")
                }
                .store(in: &cancellables)
            // Load the note for this recording session if it exists
            if let existingNote = notes.first {
                noteText = existingNote.text
            } else {
                noteText = ""
            }
            summaryService.summaryPublisher
                .receive(on: RunLoop.main)
                .sink { summaryText in
                    latestSummaryText = summaryText
                }
                .store(in: &cancellables)
#endif
        }
        .onDisappear {
            timer?.invalidate()
        }
        .alert(isPresented: $showPermissionAlert) {
            Alert(title: Text("Permission Required"), message: Text(permissionMessage), dismissButton: .default(Text("OK")))
        }
        #else
        VStack {
            Text("Recording is only available on iOS devices.")
                .foregroundColor(.gray)
        }
        #endif
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
            isRecordingStarted = true
            elapsedTime = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { _ in
                elapsedTime += 1
            })
            print("[RecordingView] Recording started")
        } catch {
            permissionMessage = "Failed to start recording: \(error.localizedDescription)"
            showPermissionAlert = true
            print("[RecordingView] Failed to start recording: \(error)")
        }
    }

    private func stopRecording() {
        recordingService.stopRecording()
        transcriptionService.stopTranscription()
        timer?.invalidate()
        let title = "Sermon on " + DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        let date = Date()
        if let url = audioFileURL {
            isProcessingTranscript = true
            transcriptProcessingError = nil
            transcriptionService.transcribeAudioFile(url: url) { text, segments in
                print("[RecordingView] Vercel transcription callback fired.")
                DispatchQueue.main.async {
                    isProcessingTranscript = false
                    if let text = text {
                        print("[RecordingView] Vercel transcription succeeded. Text length: \(text.count), Segments count: \(segments.count)")
                        transcript = text
                        detectedReferences = scriptureAnalysisService.analyzeScriptureReferences(in: text)
                        // Save the sermon after successful transcription!
                        handleTranscriptionResult(title: title, date: date, url: url)(text, segments)
                    } else {
                        print("[RecordingView] Vercel transcription failed.")
                        // Optionally show an error to the user
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
            let newSermon = Sermon(
                title: title,
                audioFileURL: url,
                date: date,
                serviceType: serviceType,
                transcript: transcriptModel,
                notes: notes,
                summary: summaryModel,
                syncStatus: "localOnly",
                transcriptionStatus: "complete",
                summaryStatus: "processing"
            )
            print("[DEBUG] handleTranscriptionResult: newSermon.transcriptionStatus = \(newSermon.transcriptionStatus)")
            sermonService.saveSermon(
                title: newSermon.title,
                audioFileURL: newSermon.audioFileURL,
                date: newSermon.date,
                serviceType: newSermon.serviceType,
                transcript: newSermon.transcript,
                notes: newSermon.notes,
                summary: newSermon.summary,
                transcriptionStatus: "complete",
                summaryStatus: newSermon.summaryStatus,
                id: newSermon.id
            )
            onNext?(newSermon)
            summaryService.generateSummary(for: text, type: serviceType)
            var summaryCancellable: AnyCancellable? = nil
            summaryCancellable = summaryService.statusSubject
                .receive(on: RunLoop.main)
                .sink { status in
                    if status == "complete" {
                        if let summaryText = latestSummaryText, !summaryText.isEmpty {
                            newSermon.summary?.text = summaryText
                            newSermon.summary?.status = "complete"
                            newSermon.summaryStatus = "complete"
                            // Persist the updated summary and status
                            sermonService.saveSermon(
                                title: newSermon.title,
                                audioFileURL: newSermon.audioFileURL,
                                date: newSermon.date,
                                serviceType: newSermon.serviceType,
                                transcript: newSermon.transcript,
                                notes: newSermon.notes,
                                summary: newSermon.summary,
                                transcriptionStatus: newSermon.transcriptionStatus,
                                summaryStatus: "complete",
                                id: newSermon.id
                            )
                        }
                        summaryCancellable?.cancel()
                    } else if status == "failed" {
                        newSermon.summary?.status = "failed"
                        newSermon.summaryStatus = "failed"
                        // Persist the failed status
                        sermonService.saveSermon(
                            title: newSermon.title,
                            audioFileURL: newSermon.audioFileURL,
                            date: newSermon.date,
                            serviceType: newSermon.serviceType,
                            transcript: newSermon.transcript,
                            notes: newSermon.notes,
                            summary: newSermon.summary,
                            transcriptionStatus: newSermon.transcriptionStatus,
                            summaryStatus: "failed",
                            id: newSermon.id
                        )
                        summaryCancellable?.cancel()
                    }
                }
        }
    }

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    #endif
}

#Preview {
    RecordingView(
        serviceType: "Sermon",
        noteService: NoteService(),
        onNext: { _ in },
        sermonService: SermonService(modelContext: try! ModelContext(ModelContainer(for: Sermon.self)))
    )
}
