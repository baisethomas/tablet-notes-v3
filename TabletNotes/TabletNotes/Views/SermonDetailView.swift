import SwiftUI
import AVFoundation
import SwiftData
import Combine
// Add these imports if needed for model and view types
// import TabletNotes.Models // Uncomment if models are in a separate module
// import TabletNotes.Services // Uncomment if services are in a separate module
// Ensure TabletNotes/TabletNotes/Models/Sermon.swift and TabletNotes/TabletNotes/Views/HeaderView.swift are included in the build target
// Ensure TabletNotes/TabletNotes/Models/Sermon.swift is included in the build target for this file to resolve 'Sermon' in scope.
// import TabletNotes.Models // Removed because the module does not exist and causes a build error.

// MARK: - Enhanced Loading State Component
struct ProcessingStateView: View {
    let title: String
    let subtitle: String
    let icon: String
    
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                    .frame(width: 60, height: 60)
                
                // Animated progress circle
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(animationOffset))
                
                // Icon
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .frame(width: 60, height: 60)
            .onAppear {
                // Delay the animation start to ensure proper layout
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        animationOffset = 360
                    }
                }
            }
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Enhanced Error State Component
struct SermonErrorStateView: View {
    let title: String
    let subtitle: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                VStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .cornerRadius(25)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Enhanced Tab Button Component
struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                
                Rectangle()
                    .frame(height: 2)
                    .foregroundColor(isSelected ? .accentColor : .clear)
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
            }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }
}

// MARK: - Enhanced Audio Player Component
struct AudioPlayerView: View {
    @Binding var isPlaying: Bool
    @Binding var currentTime: TimeInterval
    @Binding var duration: TimeInterval
    let onPlayPause: () -> Void
    let onSeek: (TimeInterval) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Progress bar
            VStack(spacing: 8) {
                Slider(value: Binding<Double>(
                    get: { currentTime },
                    set: { newValue in
                        onSeek(newValue)
                    }
                ), in: 0...(duration > 0 ? duration : 1))
                .accentColor(.accentColor)
                .background(Color.gray.opacity(0.2))
                
                // Time labels
                HStack {
                    Text(timeString(from: currentTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    
                    Spacer()
                    
                    Text(timeString(from: duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            
            // Play/pause button
            Button(action: onPlayPause) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 60, height: 60)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .offset(x: isPlaying ? 0 : 2) // Slight offset for play icon
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(isPlaying ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isPlaying)
        }
        .padding()
        .cornerRadius(16)
    }
    
    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Clean Transcript Segment Component
struct TranscriptSegmentView: View {
    let segment: TranscriptSegment
    let onTimestampTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Clean timestamp - no bubble
            Button(action: {
                onTimestampTap()
            }) {
                Text(timeString(from: segment.startTime))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            // Clean text - no outline
            Text(segment.text)
                .font(.body)
                .foregroundColor(.primary)
                .lineSpacing(4)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
    }
    
    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    

}

struct SermonDetailView: View {
    @ObservedObject var sermonService: SermonService
    @ObservedObject var authManager: AuthenticationManager
    let sermonID: UUID
    var onBack: (() -> Void)?
    @State private var selectedTab: Tab = .summary
    @State private var audioPlayer: AVAudioPlayer? = nil
    @State private var isPlaying: Bool = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var timer: Timer? = nil
    @State private var editableTitle: String = ""
    @State private var isEditingTitle = false
    @State private var editableSpeaker: String = ""
    @State private var isEditingSpeaker = false

    // Transcription retry
    @StateObject private var transcriptionRetryService = TranscriptionRetryService.shared
    @State private var isRetryingTranscription = false
    @State private var summaryCancellables = Set<AnyCancellable>()

    // Chat service
    @StateObject private var chatService = ChatService.shared
    
    enum Tab: String, CaseIterable {
        case summary = "Summary"
        case transcript = "Transcript"
        case notes = "Notes"
        case chat = "AI Chat"

        var icon: String {
            switch self {
            case .summary: return "doc.text"
            case .transcript: return "text.bubble"
            case .notes: return "note.text"
            case .chat: return "sparkles"
            }
        }
    }
    
    var sermon: Sermon? {
        // Fetch from sermonService which uses SwiftData
        sermonService.sermons.first(where: { $0.id == sermonID })
    }

    // MARK: - Performance Optimizations: Cached sorted arrays (no inline sorting in ForEach)

    /// Sorted transcript segments (cached - avoids O(n log n) on every render)
    var sortedTranscriptSegments: [TranscriptSegment] {
        guard let transcript = sermon?.transcript else { return [] }
        return transcript.segments.sorted(by: { $0.startTime < $1.startTime })
    }

    /// Sorted notes (cached - avoids O(n log n) on every render)
    var sortedNotes: [Note] {
        guard let sermon = sermon else { return [] }
        return sermon.notes.sorted(by: { $0.timestamp < $1.timestamp })
    }

    var body: some View {
        NavigationView {
            ZStack { // <-- Add ZStack to allow background color
                Color.adaptiveBackground.ignoresSafeArea() // Navy dark mode background
                if let sermon = sermon {
                    VStack(spacing: 0) {
                        HeaderView(
                            title: "",
                            showLogo: false,
                            showSearch: false,
                            showSyncStatus: false,
                            showBack: true,
                            onBack: onBack
                        )
                        
                        // Enhanced header section
                        VStack(spacing: 16) {
                            // Title section
                            VStack(spacing: 8) {
                                if isEditingTitle {
                                    TextField("Sermon Title", text: $editableTitle)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .onSubmit {
                                            saveTitle()
                                        }
                                } else {
                                    HStack {
                                        Text(editableTitle)
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.adaptivePrimaryText) // navy dark mode text
                                            .lineLimit(2)
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                            impactFeedback.impactOccurred()
                                            isEditingTitle = true
                                        }) {
                                            Image(systemName: "pencil")
                                                .font(.caption)
                                                .foregroundColor(.adaptiveSecondaryText)
                                                .padding(8)
                                                .cornerRadius(8)
                                        }
                                    }
                                    .onTapGesture {
                                        isEditingTitle = true
                                    }
                                }
                            }
                            
                            // Metadata section
                            VStack(spacing: 12) {
                                HStack(spacing: 16) {
                                    Label(formattedDate, systemImage: "calendar")
                                        .foregroundColor(.adaptiveSecondaryText)
                                    Label(formattedTime, systemImage: "clock")
                                        .foregroundColor(.adaptiveSecondaryText)
                                    if duration > 0 {
                                        Label("\(Int(duration / 60)) min", systemImage: "timer")
                                            .foregroundColor(.adaptiveSecondaryText)
                                    }
                                    Label(sermon.serviceType, systemImage: "church.fill")
                                        .foregroundColor(.adaptiveSecondaryText)
                                }
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // Speaker section
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "person.circle")
                                            .font(.caption)
                                            .foregroundColor(.adaptiveAccent)
                                        Text("Speaker")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.adaptiveSecondaryText)
                                        Spacer()
                                    }
                                    
                                    if isEditingSpeaker {
                                        HStack {
                                            TextField("Enter speaker name", text: $editableSpeaker)
                                                .font(.subheadline)
                                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                                .onSubmit {
                                                    saveSpeaker()
                                                }
                                            
                                            Button("Save") {
                                                saveSpeaker()
                                            }
                                            .font(.caption)
                                            .foregroundColor(.adaptiveAccent)
                                            
                                            Button("Cancel") {
                                                editableSpeaker = sermon.speaker ?? ""
                                                isEditingSpeaker = false
                                            }
                                            .font(.caption)
                                            .foregroundColor(.adaptiveSecondaryText)
                                        }
                                    } else {
                                        HStack {
                                            Text(editableSpeaker.isEmpty ? "Tap to add speaker" : editableSpeaker)
                                                .font(.subheadline)
                                                .foregroundColor(editableSpeaker.isEmpty ? .adaptiveSecondaryText : .adaptivePrimaryText)
                                                .italic(editableSpeaker.isEmpty)
                                            
                                            Spacer()
                                            
                                            Button(action: {
                                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                                impactFeedback.impactOccurred()
                                                isEditingSpeaker = true
                                            }) {
                                                Image(systemName: "pencil")
                                                    .font(.caption)
                                                    .foregroundColor(.adaptiveSecondaryText)
                                                    .padding(6)
                                                    .cornerRadius(6)
                                            }
                                        }
                                        .onTapGesture {
                                            isEditingSpeaker = true
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                        
                        // Enhanced tab section
                        HStack(spacing: 0) {
                            ForEach(Tab.allCases, id: \.self) { tab in
                                TabButton(
                                    title: tab.rawValue,
                                    isSelected: selectedTab == tab
                                ) {
                                    selectedTab = tab
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        Divider()
                        
                        // Enhanced content area
                        Group {
                            switch selectedTab {
                            case .summary:
                                summaryTabView
                            case .transcript:
                                transcriptTabView
                            case .notes:
                                notesTabView
                            case .chat:
                                chatTabView
                            }
                        }
                        .animation(.easeInOut(duration: 0.3), value: selectedTab)
                    }
                    .background(Color.clear) // VStack background clear, ZStack handles bg
                    .onAppear {
                        editableTitle = sermon.title
                        editableSpeaker = sermon.speaker ?? ""
                        setupAudioPlayer()

                        // Log note count for debugging
                        print("[SermonDetailView] onAppear: Sermon '\(sermon.title)' has \(sermon.notes.count) notes")
                        for (index, note) in sermon.notes.enumerated() {
                            print("[SermonDetailView]   Note \(index): '\(note.text)' at \(note.timestamp)s")
                        }

                        // Retry transcription if needed
                        transcriptionRetryService.retryTranscriptionIfNeeded(for: sermon)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: TranscriptionRetryService.transcriptionCompletedNotification)) { notification in
                        // Refresh sermon data when transcription completes
                        if let completedSermonId = notification.object as? UUID,
                           completedSermonId == sermon.id {
                            // The sermon will automatically refresh through the @ObservedObject sermonService
                        }
                    }
                    .onDisappear {
                        cleanup()
                    }
                } else {
                    // Enhanced not found state
                    VStack(spacing: 20) {
                        Image(systemName: "doc.questionmark")
                            .font(.system(size: 64))
                            .foregroundColor(.adaptiveSecondaryText)
                        
                        VStack(spacing: 8) {
                            Text("Sermon Not Found")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.adaptivePrimaryText)
                            
                            Text("This sermon may have been deleted or is no longer available.")
                                .font(.subheadline)
                                .foregroundColor(.adaptiveSecondaryText)
                                .multilineTextAlignment(.center)
                        }
                        
                        Button(action: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            onBack?()
                        }) {
                            Text("Back to Sermons")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.adaptiveAccent)
                                .cornerRadius(25)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationBarHidden(true)
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            if let sermon = sermon {
                editableTitle = sermon.title
                editableSpeaker = sermon.speaker ?? ""
                setupAudioPlayer()
            }
        }
        .onDisappear {
            // Clean up audio player when leaving the view
            stopPlayback()
            audioPlayer = nil
            timer?.invalidate()
        }
    }
    
    // MARK: - Helper Methods
    private func setupAudioPlayer() {
        guard let sermon = sermon else { return }
        
        print("[AudioPlayer] Setting up audio player on view appear")
        setupAudioPlayerForPlayback(sermon: sermon)
        
        // Reset audio session to playback mode after potential recording
        setupAudioSessionForPlayback()
    }
    
    private func setupAudioSessionForPlayback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.allowBluetooth])
            try audioSession.setActive(true)
            print("[AudioPlayer] Audio session configured for playback")
        } catch {
            print("[AudioPlayer] Failed to configure audio session: \(error)")
        }
    }
    
    private func saveTitle() {
        guard let sermon = sermon else { return }
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        sermonService.saveSermon(
            title: editableTitle,
            audioFileURL: sermon.audioFileURL,
            date: sermon.date,
            serviceType: sermon.serviceType,
            speaker: sermon.speaker,
            transcript: sermon.transcript,
            notes: sermon.notes,
            summary: sermon.summary,
            transcriptionStatus: sermon.transcriptionStatus,
            summaryStatus: sermon.summaryStatus,
            id: sermon.id
        )
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isEditingTitle = false
        }
    }
    
    private func saveSpeaker() {
        guard let sermon = sermon else { return }
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        let trimmedSpeaker = editableSpeaker.trimmingCharacters(in: .whitespacesAndNewlines)
        sermonService.saveSermon(
            title: sermon.title,
            audioFileURL: sermon.audioFileURL,
            date: sermon.date,
            serviceType: sermon.serviceType,
            speaker: trimmedSpeaker.isEmpty ? nil : trimmedSpeaker,
            transcript: sermon.transcript,
            notes: sermon.notes,
            summary: sermon.summary,
            transcriptionStatus: sermon.transcriptionStatus,
            summaryStatus: sermon.summaryStatus,
            id: sermon.id
        )
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isEditingSpeaker = false
        }
    }
    
    private func cleanup() {
        timer?.invalidate()
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    private var formattedDate: String {
        DateFormatter.localizedString(from: sermon?.date ?? Date(), dateStyle: .medium, timeStyle: .none)
    }
    
    private var formattedTime: String {
        DateFormatter.localizedString(from: sermon?.date ?? Date(), dateStyle: .none, timeStyle: .short)
    }
    
    // MARK: - Tab Views
    var summaryTabView: some View {
        Group {
            if let sermon = sermon {
                switch sermon.summaryStatus {
                case "processing":
                    ProcessingStateView(
                        title: "Generating Summary",
                        subtitle: "AI is analyzing your sermon content to create a comprehensive summary.",
                        icon: "doc.text"
                    )
                case "failed":
                    SermonErrorStateView(
                        title: "Summary Generation Failed",
                        subtitle: "We couldn't generate a summary for this sermon. Please try again.",
                        actionTitle: "Retry",
                        action: {
                            print("[SermonDetailView] Retry button pressed - regenerating summary")
                            generateSummaryForSermon(sermon)
                        }
                    )
                default:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            let cleanSummary = (sermon.summary?.text ?? "No summary available.").replacingOccurrences(of: "**", with: "")
                            
                            SummaryTextView(
                                summaryText: cleanSummary,
                                serviceType: sermon.serviceType
                            )
                            .padding(.horizontal)
                        }
                        .padding()
                        .padding(.bottom, 100)
                    }
                }
            } else {
                Text("No summary available.")
                    .foregroundColor(.adaptiveSecondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    var transcriptTabView: some View {
        VStack(spacing: 0) {
            // Compact single-line audio player at the top - always visible when there's a sermon
            if let sermon = sermon {
                VStack(spacing: 0) {
                    // Single-line audio player
                    HStack(spacing: 12) {
                        // Play/pause button
                        Button(action: togglePlayback) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 28, height: 28)
                                
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white)
                                    .offset(x: isPlaying ? 0 : 1) // Slight offset for play icon
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Current time
                        Text(timeString(from: currentTime))
                            .font(.caption2)
                            .foregroundColor(.adaptiveSecondaryText)
                            .monospacedDigit()
                            .frame(width: 35, alignment: .trailing)
                        
                        // Progress slider
                        Slider(value: Binding<Double>(
                            get: { currentTime },
                            set: { newValue in
                                seekToTime(newValue)
                            }
                        ), in: 0...(duration > 0 ? duration : 1))
                        .accentColor(.accentColor)
                        
                        // Total time
                        Text(timeString(from: duration))
                            .font(.caption2)
                            .foregroundColor(.adaptiveSecondaryText)
                            .monospacedDigit()
                            .frame(width: 35, alignment: .leading)
                        
                        // Skip forward button
                        Button(action: {
                            let newTime = min(currentTime + 15, duration)
                            seekToTime(newTime)
                        }) {
                            Image(systemName: "goforward.15")
                                .font(.system(size: 13))
                                .foregroundColor(.adaptiveSecondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.adaptiveCardBackground)
                    
                    Divider()
                }
                .background(Color.adaptiveCardBackground)
            }
            
            // Main content area
            if let sermon = sermon {
                switch sermon.transcriptionStatus {
                case "processing":
                    ProcessingStateView(
                        title: "Transcribing Audio",
                        subtitle: "Converting your sermon audio to text. This may take a few minutes.",
                        icon: "text.bubble"
                    )
                case "failed", "pending":
                    SermonErrorStateView(
                        title: sermon.transcriptionStatus == "pending" ? "Transcription Pending" : "Transcription Failed",
                        subtitle: sermon.transcriptionStatus == "pending" ? 
                            "This recording was saved for later processing. Tap retry when you're back online." :
                            "We couldn't transcribe this sermon. Please check your audio file and try again.",
                        actionTitle: isRetryingTranscription ? "Retrying..." : "Retry",
                        action: isRetryingTranscription ? nil : {
                            retryTranscription(for: sermon)
                        }
                    )
                default:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if let transcript = sermon.transcript {
                                // Display transcript segments with timestamps
                                if !transcript.segments.isEmpty {
                                    ForEach(sortedTranscriptSegments, id: \.id) { segment in
                                        VStack(alignment: .leading, spacing: 8) {
                                            // Clickable timestamp
                                            Button(action: {
                                                playFromTimestamp(segment.startTime)
                                            }) {
                                                Text(timeString(from: segment.startTime))
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(.adaptiveSecondaryText)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.adaptiveCardBackground)
                                                    .cornerRadius(6)
                                            }
                                            .buttonStyle(.plain)
                                            
                                            // Segment text
                                            Text(segment.text)
                                                .font(.body)
                                                .foregroundColor(.adaptivePrimaryText)
                                                .lineSpacing(6)
                                                .lineLimit(nil)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .padding(.vertical, 8)
                                    }
                                } else {
                                    // Fallback to full text if no segments
                                    Text(transcript.text)
                                        .font(.body)
                                        .foregroundColor(.adaptivePrimaryText)
                                        .lineSpacing(6)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } else {
                                Text("No transcript available.")
                                    .font(.body)
                                    .foregroundColor(.adaptiveSecondaryText)
                                    .padding()
                            }
                        }
                        .padding()
                        .padding(.bottom, 20) // Standard bottom padding
                    }
                }
            } else {
                Text("No transcript available.")
                    .foregroundColor(.adaptiveSecondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    var notesTabView: some View {
        Group {
            if let sermon = sermon, !sermon.notes.isEmpty {
                let _ = print("[DEBUG] SermonDetailView: Found \(sermon.notes.count) notes for sermon \(sermon.title)")
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(sortedNotes) { note in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "note.text")
                                        .font(.caption)
                                        .foregroundColor(.adaptiveAccent)
                                    
                                    Text("At \(timeString(from: note.timestamp))")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.adaptiveSecondaryText)
                                    
                                    Spacer()
                                }
                                
                                Text(note.text)
                                    .font(.body)
                                    .foregroundColor(.adaptivePrimaryText)
                                    .lineSpacing(2)
                            }
                            .padding()
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                    .padding(.bottom, 100)
                }
            } else {
                let _ = print("[DEBUG] SermonDetailView: No notes found for sermon \(sermon?.title ?? "unknown"). Notes count: \(sermon?.notes.count ?? 0)")
                VStack(spacing: 16) {
                    Image(systemName: "note.text")
                        .font(.system(size: 48))
                        .foregroundColor(.adaptiveSecondaryText)
                    
                    VStack(spacing: 8) {
                        Text("No Notes")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.adaptivePrimaryText)
                        
                        Text("Notes taken during recording will appear here.")
                            .font(.subheadline)
                            .foregroundColor(.adaptiveSecondaryText)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    var chatTabView: some View {
        Group {
            if let sermon = sermon {
                ChatTabView(
                    chatService: chatService,
                    authManager: authManager,
                    sermon: sermon
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundColor(.adaptiveSecondaryText)

                    VStack(spacing: 8) {
                        Text("Chat Unavailable")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.adaptivePrimaryText)

                        Text("Chat requires a sermon to be loaded.")
                            .font(.subheadline)
                            .foregroundColor(.adaptiveSecondaryText)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Audio Player Methods
    private func togglePlayback() {
        guard let sermon = sermon else { return }
        
        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            // Ensure audio player is set up and ready
            if audioPlayer == nil {
                print("[AudioPlayer] Audio player is nil, setting up for playback")
                setupAudioPlayerForPlayback(sermon: sermon)
            }
            
            // Verify audio player was successfully created
            guard let player = audioPlayer else {
                print("[AudioPlayer] Failed to create audio player, cannot play")
                return
            }
            
            // Ensure audio session is configured for playback
            setupAudioSessionForPlayback()
            
            player.play()
            isPlaying = true
            startTimer()
        }
    }
    
    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        currentTime = 0
        isPlaying = false
        timer?.invalidate()
    }
    
    private func playFromTimestamp(_ timestamp: TimeInterval) {
        guard let sermon = sermon else { return }
        
        if audioPlayer == nil {
            setupAudioPlayerForPlayback(sermon: sermon)
        }
        
        // Verify audio player was successfully created
        guard let player = audioPlayer else {
            print("[AudioPlayer] Failed to create audio player for timestamp playback")
            return
        }
        
        // Ensure audio session is configured for playback
        setupAudioSessionForPlayback()
        
        player.currentTime = timestamp
        player.play()
        isPlaying = true
        startTimer()
    }
    
    private func seekToTime(_ time: TimeInterval) {
        currentTime = time
        audioPlayer?.currentTime = time
    }
    
    private func setupAudioPlayerForPlayback(sermon: Sermon) {
        print("[AudioPlayer] Attempting to load audio from: \(sermon.audioFileURL)")
        print("[AudioPlayer] Full URL: \(sermon.audioFileURL.absoluteString)")
        
        // Check if file exists and is readable
        let fileExists = FileManager.default.fileExists(atPath: sermon.audioFileURL.path)
        let isReadable = FileManager.default.isReadableFile(atPath: sermon.audioFileURL.path)
        print("[AudioPlayer] File exists: \(fileExists), readable: \(isReadable)")
        
        if !fileExists {
            print("[AudioPlayer] ERROR: Audio file not found at path: \(sermon.audioFileURL.path)")
            print("[AudioPlayer] Checking if audio file exists with audioFileExists property: \(sermon.audioFileExists)")
            
            // Try to find the file in the AudioRecordings directory
            let audioDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("AudioRecordings")
            if let files = try? FileManager.default.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil) {
                let audioFileName = sermon.audioFileName
                if let foundFile = files.first(where: { $0.lastPathComponent == audioFileName }) {
                    print("[AudioPlayer] Found audio file at alternative location: \(foundFile.path)")
                } else {
                    print("[AudioPlayer] Audio file '\(audioFileName)' not found in AudioRecordings directory")
                    print("[AudioPlayer] Available files: \(files.map { $0.lastPathComponent })")
                }
            }
            return
        }
        
        if !isReadable {
            print("[AudioPlayer] ERROR: Audio file is not readable at path: \(sermon.audioFileURL.path)")
            return
        }
        
        // Get file attributes for debugging
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: sermon.audioFileURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            print("[AudioPlayer] File size: \(fileSize) bytes")
        } catch {
            print("[AudioPlayer] Could not get file attributes: \(error)")
        }
        
        do {
            // Clean up any existing player first
            audioPlayer?.stop()
            audioPlayer = nil
            
            audioPlayer = try AVAudioPlayer(contentsOf: sermon.audioFileURL)
            duration = audioPlayer?.duration ?? 0
            audioPlayer?.prepareToPlay()
            print("[AudioPlayer] Successfully loaded audio. Duration: \(duration) seconds")
        } catch {
            print("[AudioPlayer] Failed to load audio: \(error)")
            if let nsError = error as NSError? {
                print("[AudioPlayer] Error domain: \(nsError.domain), code: \(nsError.code)")
                print("[AudioPlayer] Error description: \(nsError.localizedDescription)")
                print("[AudioPlayer] User info: \(nsError.userInfo)")
            }
            audioPlayer = nil
        }
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            currentTime = audioPlayer?.currentTime ?? 0
            if let player = audioPlayer, !player.isPlaying {
                isPlaying = false
                timer?.invalidate()
            }
        }
    }
    
    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func retryTranscription(for sermon: Sermon) {
        // Set retry state
        isRetryingTranscription = true
        
        // Update sermon status to processing
        sermon.transcriptionStatus = "processing"
        
        // Create a transcription service to retry the processing
        let transcriptionService = TranscriptionService()
        
        transcriptionService.transcribeAudioFileWithResult(url: sermon.audioFileURL) { result in
            DispatchQueue.main.async {
                isRetryingTranscription = false
                
                switch result {
                case .success(let (text, segments)):
                    // Create or update transcript
                    if sermon.transcript == nil {
                        let transcript = Transcript(text: text)
                        
                        // Add transcript segments
                        for segment in segments {
                            let transcriptSegment = TranscriptSegment(
                                text: segment.text,
                                startTime: segment.startTime,
                                endTime: segment.endTime
                            )
                            transcript.segments.append(transcriptSegment)
                        }
                        
                        sermon.transcript = transcript
                    } else {
                        // Update existing transcript
                        sermon.transcript?.text = text
                        sermon.transcript?.segments.removeAll()
                        
                        for segment in segments {
                            let transcriptSegment = TranscriptSegment(
                                text: segment.text,
                                startTime: segment.startTime,
                                endTime: segment.endTime
                            )
                            sermon.transcript?.segments.append(transcriptSegment)
                        }
                    }
                    
                    // Update status
                    sermon.transcriptionStatus = "complete"
                    
                    // Save changes
                    sermonService.updateSermon(sermon)
                    
                    // Generate summary after successful transcription
                    generateSummaryForSermon(sermon)
                    
                case .failure(let error):
                    print("Transcription retry failed: \(error)")
                    sermon.transcriptionStatus = "failed"
                    sermonService.updateSermon(sermon)
                }
            }
        }
    }
    
    private func generateSummaryForSermon(_ sermon: Sermon) {
        guard let transcript = sermon.transcript, !transcript.text.isEmpty else {
            print("[SermonDetailView] No transcript available for summary generation")
            return
        }

        // Use service layer approach to ensure summary completion is handled
        print("[SermonDetailView] Generating summary via SermonService")
        sermonService.generateSummaryForSermon(sermon, transcript: transcript.text, serviceType: sermon.serviceType)
    }
}

#Preview {
    SermonDetailView(
        sermonService: SermonService(modelContext: try! ModelContext(ModelContainer(for: Sermon.self))),
        authManager: AuthenticationManager.shared,
        sermonID: UUID()
    )
}

