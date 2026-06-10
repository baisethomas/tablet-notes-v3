import SwiftUI
import AVFoundation
import SwiftData
import Combine

// MARK: - Processing State

struct ProcessingStateView: View {
    let title: String
    let subtitle: String
    let icon: String

    @State private var animationOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.SV.onSurface.opacity(0.1), lineWidth: 2)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(Color.SV.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(animationOffset))
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Color.SV.primary.opacity(0.7))
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        animationOffset = 360
                    }
                }
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.SV.onSurface)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error State

struct SermonErrorStateView: View {
    let title: String
    let subtitle: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.SV.tertiary.opacity(0.7))

                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.SV.onSurface)
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.SV.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Color.SV.primary.opacity(0.08))
                        .clipShape(.rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sermon Detail View

struct SermonDetailView: View {
    var sermonService: SermonService
    var authManager: AuthenticationManager
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
    @State private var summaryTextSnapshot: String = "No summary available."

    private let processingCoordinator = SermonProcessingCoordinator.shared
    @State private var isRetryingTranscription = false
    @State private var summaryCancellables = Set<AnyCancellable>()

    private let chatService = ChatService.shared

    enum Tab: String, CaseIterable {
        case summary    = "Summary"
        case transcript = "Transcript"
        case notes      = "Notes"
        case chat       = "AI Chat"
    }

    // MARK: - Computed Data

    var sermon: Sermon? {
        sermonService.sermons.first(where: { $0.id == sermonID })
    }

    /// Cached sorted segments — avoids O(n log n) on every render.
    var sortedTranscriptSegments: [TranscriptSegment] {
        guard let transcript = sermon?.transcript else { return [] }
        return transcript.segments.sorted { $0.startTime < $1.startTime }
    }

    /// Cached sorted notes — avoids O(n log n) on every render.
    var sortedNotes: [Note] {
        guard let sermon else { return [] }
        return sermon.notes.sorted { $0.timestamp < $1.timestamp }
    }

    private var formattedDate: String {
        DateFormatter.localizedString(from: sermon?.date ?? Date(), dateStyle: .medium, timeStyle: .none)
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let sermon {
                VStack(spacing: 0) {
                    svNavBar(sermon: sermon)
                    svMasthead(sermon: sermon)
                    svTabBar
                    svTabContent(sermon: sermon)
                }
                .background(Color.SV.surface.ignoresSafeArea())
                .onAppear {
                    editableTitle = sermon.title
                    editableSpeaker = sermon.speaker ?? ""
                    setupAudioPlayer()
                    refreshSummaryTextSnapshot()
                    print("[SermonDetailView] onAppear: '\(sermon.title)' — \(sermon.notes.count) notes")
                }
                .onReceive(NotificationCenter.default.publisher(for: TranscriptionRetryService.transcriptionCompletedNotification)) { notification in
                    if let completedID = notification.object as? UUID, completedID == sermon.id {
                        scheduleSummaryTextSnapshotRefresh()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: SummaryRetryService.summaryCompletedNotification)) { notification in
                    guard let completedID = notification.object as? UUID, completedID == sermon.id else { return }
                    print("[SermonDetailView] Summary completed for \(completedID)")
                    sermonService.fetchSermons()
                    scheduleSummaryTextSnapshotRefresh()
                }
                .onChange(of: sermon.summaryStatus) { _, _ in scheduleSummaryTextSnapshotRefresh() }
                .onChange(of: sermon.transcriptionStatus) { _, newStatus in
                    if newStatus != "pending" { isRetryingTranscription = false }
                }
                .onChange(of: sermon.updatedAt ?? Date.distantPast) { _, _ in scheduleSummaryTextSnapshotRefresh() }
                .onDisappear { cleanup() }
            } else {
                svNotFoundState
                    .background(Color.SV.surface.ignoresSafeArea())
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Navigation Bar

    @ViewBuilder
    private func svNavBar(sermon: Sermon) -> some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onBack?()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.6))
            }
            .buttonStyle(.plain)

            Spacer()

            Menu {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) { isEditingTitle = true }
                } label: {
                    Label("Edit Title", systemImage: "pencil")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.SV.surface)
    }

    // MARK: - Masthead

    @ViewBuilder
    private func svMasthead(sermon: Sermon) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Metadata row: service type chip + date
            HStack(spacing: 12) {
                Text(sermon.serviceType.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.SV.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.SV.primary.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 4))

                Text(formattedDate)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.45))
            }

            // Large serif title (tappable to edit)
            if isEditingTitle {
                TextField("Sermon title", text: $editableTitle)
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundStyle(Color.SV.onSurface)
                    .onSubmit { saveTitle() }
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) { isEditingTitle = true }
                } label: {
                    Text(editableTitle.isEmpty ? "Untitled" : editableTitle)
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(Color.SV.onSurface)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            // Speaker (editorial italic, editable)
            if isEditingSpeaker {
                HStack(spacing: 8) {
                    TextField("Speaker name", text: $editableSpeaker)
                        .font(.system(size: 15, design: .serif))
                        .italic()
                        .foregroundStyle(Color.SV.primary)
                        .onSubmit { saveSpeaker() }
                    Button("Save") { saveSpeaker() }
                        .font(.system(size: 13))
                        .foregroundStyle(Color.SV.primary)
                    Button("Cancel") {
                        editableSpeaker = sermon.speaker ?? ""
                        isEditingSpeaker = false
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.4))
                }
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) { isEditingSpeaker = true }
                } label: {
                    Text(editableSpeaker.isEmpty ? "Add speaker" : editableSpeaker)
                        .font(.system(size: 15, design: .serif))
                        .italic()
                        .foregroundStyle(
                            editableSpeaker.isEmpty
                                ? Color.SV.onSurface.opacity(0.28)
                                : Color.SV.primary.opacity(0.8)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .background(Color.SV.surface)
    }

    // MARK: - Tab Bar

    private var svTabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 8) {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(
                                    selectedTab == tab
                                        ? Color.SV.onSurface
                                        : Color.SV.onSurface.opacity(0.4)
                                )
                            Rectangle()
                                .fill(selectedTab == tab ? Color.SV.primary : Color.clear)
                                .frame(height: 1.5)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .background(Color.SV.surface)

            Rectangle()
                .fill(Color.SV.onSurface.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func svTabContent(sermon: Sermon) -> some View {
        Group {
            switch selectedTab {
            case .summary:    summaryTabView
            case .transcript: transcriptTabView
            case .notes:      notesTabView
            case .chat:       chatTabView
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
    }

    // MARK: - Not Found State

    private var svNotFoundState: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.SV.onSurface.opacity(0.2))

            VStack(spacing: 8) {
                Text("Sermon Not Found")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.SV.onSurface)
                Text("This sermon may have been deleted or is no longer available.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onBack?()
            } label: {
                Text("Back to Sermons")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.SV.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(Color.SV.primary.opacity(0.08))
                    .clipShape(.rect(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Summary Tab

    var summaryTabView: some View {
        Group {
            if let sermon {
                switch sermon.summaryStatus {
                case "processing":
                    if isProcessingStuck(since: sermon.updatedAt) {
                        SermonErrorStateView(
                            title: "Summary Is Taking Too Long",
                            subtitle: "This is taking longer than expected. You can retry now or check back later.",
                            actionTitle: "Retry",
                            action: { generateSummaryForSermon(sermon) }
                        )
                    } else {
                        ProcessingStateView(
                            title: "Generating Summary",
                            subtitle: "AI is analyzing your sermon content to create a comprehensive summary.",
                            icon: "doc.text"
                        )
                    }
                case "failed":
                    SermonErrorStateView(
                        title: "Summary Generation Failed",
                        subtitle: "We couldn't generate a summary for this sermon. Please try again.",
                        actionTitle: "Retry",
                        action: {
                            print("[SermonDetailView] Retry summary for \(sermon.id)")
                            generateSummaryForSermon(sermon)
                        }
                    )
                default:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            SummaryTextView(
                                summaryText: summaryTextSnapshot,
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
                    .foregroundStyle(Color.SV.onSurface.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Transcript Tab

    var transcriptTabView: some View {
        VStack(spacing: 0) {
            if let sermon {
                svAudioPlayer

                switch sermon.transcriptionStatus {
                case "processing":
                    if isProcessingStuck(since: sermon.updatedAt) {
                        SermonErrorStateView(
                            title: "Transcription Is Taking Too Long",
                            subtitle: "This is taking longer than expected. You can retry now or check back later.",
                            actionTitle: isRetryingTranscription ? "Retrying..." : "Retry",
                            action: isRetryingTranscription ? nil : { retryTranscription(for: sermon) }
                        )
                    } else {
                        ProcessingStateView(
                            title: "Transcribing Audio",
                            subtitle: "Converting your sermon audio to text. This may take a few minutes.",
                            icon: "text.bubble"
                        )
                    }
                case "failed", "pending":
                    SermonErrorStateView(
                        title: sermon.transcriptionStatus == "pending" ? "Transcription Pending" : "Transcription Failed",
                        subtitle: sermon.transcriptionStatus == "pending"
                            ? "This recording was saved for later processing. Tap retry when you're back online."
                            : "We couldn't transcribe this sermon. Please check your audio file and try again.",
                        actionTitle: isRetryingTranscription ? "Retrying..." : "Retry",
                        action: isRetryingTranscription ? nil : { retryTranscription(for: sermon) }
                    )
                default:
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if let transcript = sermon.transcript {
                                if !transcript.segments.isEmpty {
                                    ForEach(sortedTranscriptSegments, id: \.id) { segment in
                                        svTranscriptSegment(segment)
                                    }
                                } else {
                                    Text(transcript.text)
                                        .font(.system(size: 16, design: .serif))
                                        .foregroundStyle(Color.SV.onSurface)
                                        .lineSpacing(8)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 20)
                                }
                            } else {
                                Text("No transcript available.")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.SV.onSurface.opacity(0.4))
                                    .padding(32)
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
            } else {
                Text("No transcript available.")
                    .foregroundStyle(Color.SV.onSurface.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var svAudioPlayer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: togglePlayback) {
                    ZStack {
                        Circle()
                            .fill(Color.SV.primary)
                            .frame(width: 28, height: 28)
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: isPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)

                Text(timeString(from: currentTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.5))
                    .frame(width: 34, alignment: .trailing)

                Slider(
                    value: Binding(get: { currentTime }, set: { seekToTime($0) }),
                    in: 0...(duration > 0 ? duration : 1)
                )
                .tint(Color.SV.primary)

                Text(timeString(from: duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.5))
                    .frame(width: 34, alignment: .leading)

                Button {
                    seekToTime(min(currentTime + 15, duration))
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.SV.surfaceContainerLow)

            Rectangle()
                .fill(Color.SV.onSurface.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func svTranscriptSegment(_ segment: TranscriptSegment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                playFromTimestamp(segment.startTime)
            } label: {
                Text(timeString(from: segment.startTime))
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(Color.SV.primary.opacity(0.6))
            }
            .buttonStyle(.plain)

            Text(segment.text)
                .font(.system(size: 16, design: .serif))
                .foregroundStyle(Color.SV.onSurface)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Notes Tab

    var notesTabView: some View {
        Group {
            if let sermon, !sermon.notes.isEmpty {
                let _ = print("[SermonDetailView] \(sermon.notes.count) notes for '\(sermon.title)'")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        ForEach(sortedNotes) { note in
                            svNoteRow(note)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .padding(.bottom, 60)
                }
            } else {
                let _ = print("[SermonDetailView] No notes for '\(sermon?.title ?? "unknown")'")
                EmptyStateView(
                    title: "No Notes",
                    subtitle: "Notes taken during recording will appear here.",
                    systemImage: "note.text",
                    actionTitle: nil,
                    action: nil
                )
            }
        }
    }

    @ViewBuilder
    private func svNoteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("At \(timeString(from: note.timestamp))")
                .font(.system(size: 11, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(Color.SV.onSurface.opacity(0.35))

            Text(note.text)
                .font(.system(size: 16, design: .serif))
                .foregroundStyle(Color.SV.onSurface)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Chat Tab

    var chatTabView: some View {
        Group {
            if let sermon {
                ChatTabView(
                    chatService: chatService,
                    authManager: authManager,
                    sermon: sermon
                )
            } else {
                EmptyStateView(
                    title: "Chat Unavailable",
                    subtitle: "Chat requires a sermon to be loaded.",
                    systemImage: "bubble.left.and.bubble.right",
                    actionTitle: nil,
                    action: nil
                )
            }
        }
    }

    // MARK: - Helper Methods

    private func setupAudioPlayer() {
        guard let sermon else { return }
        print("[AudioPlayer] Setting up on view appear")
        setupAudioPlayerForPlayback(sermon: sermon)
        setupAudioSessionForPlayback()
    }

    private func scheduleSummaryTextSnapshotRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard self.sermon?.id == self.sermonID else { return }
            self.refreshSummaryTextSnapshot()
        }
    }

    private func refreshSummaryTextSnapshot() {
        guard let sermon else {
            summaryTextSnapshot = "No summary available."
            return
        }
        guard sermon.summaryStatus == "complete" else {
            summaryTextSnapshot = "No summary available."
            return
        }
        let raw = sermon.summary?.text ?? "No summary available."
        summaryTextSnapshot = raw.replacingOccurrences(of: "**", with: "")
    }

    private func setupAudioSessionForPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowBluetooth])
            try session.setActive(true)
            print("[AudioPlayer] Audio session configured for playback")
        } catch {
            print("[AudioPlayer] Failed to configure audio session: \(error)")
        }
    }

    private func saveTitle() {
        guard let sermon else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        withAnimation(.easeInOut(duration: 0.3)) { isEditingTitle = false }
    }

    private func saveSpeaker() {
        guard let sermon else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let trimmed = editableSpeaker.trimmingCharacters(in: .whitespacesAndNewlines)
        sermonService.saveSermon(
            title: sermon.title,
            audioFileURL: sermon.audioFileURL,
            date: sermon.date,
            serviceType: sermon.serviceType,
            speaker: trimmed.isEmpty ? nil : trimmed,
            transcript: sermon.transcript,
            notes: sermon.notes,
            summary: sermon.summary,
            transcriptionStatus: sermon.transcriptionStatus,
            summaryStatus: sermon.summaryStatus,
            id: sermon.id
        )
        withAnimation(.easeInOut(duration: 0.3)) { isEditingSpeaker = false }
    }

    private func cleanup() {
        timer?.invalidate()
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }

    // MARK: - Audio Playback

    private func togglePlayback() {
        guard let sermon else { return }
        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            if audioPlayer == nil {
                print("[AudioPlayer] Player is nil — setting up")
                setupAudioPlayerForPlayback(sermon: sermon)
            }
            guard let player = audioPlayer else {
                print("[AudioPlayer] Failed to create player")
                return
            }
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
        guard let sermon else { return }
        if audioPlayer == nil { setupAudioPlayerForPlayback(sermon: sermon) }
        guard let player = audioPlayer else {
            print("[AudioPlayer] Failed to create player for timestamp")
            return
        }
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
        print("[AudioPlayer] Loading: \(sermon.audioFileURL)")
        let path = sermon.audioFileURL.path
        let exists = FileManager.default.fileExists(atPath: path)
        let readable = FileManager.default.isReadableFile(atPath: path)
        print("[AudioPlayer] Exists: \(exists), readable: \(readable)")

        guard exists, readable else {
            print("[AudioPlayer] File not accessible at: \(path)")
            return
        }

        do {
            audioPlayer?.stop()
            audioPlayer = nil
            audioPlayer = try AVAudioPlayer(contentsOf: sermon.audioFileURL)
            duration = audioPlayer?.duration ?? 0
            audioPlayer?.prepareToPlay()
            print("[AudioPlayer] Loaded. Duration: \(duration)s")
        } catch {
            print("[AudioPlayer] Failed to load: \(error)")
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

    /// A "processing" state with no progress for this long is presumed stuck,
    /// and the UI offers a Retry instead of an indefinite spinner.
    private func isProcessingStuck(since lastUpdate: Date?) -> Bool {
        guard let lastUpdate else { return true }
        return Date().timeIntervalSince(lastUpdate) > TranscriptionRetryService.processingStuckTimeout
    }

    private func retryTranscription(for sermon: Sermon) {
        isRetryingTranscription = true
        if !processingCoordinator.retryTranscription(for: sermon.id) {
            isRetryingTranscription = false
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if isRetryingTranscription, self.sermon?.transcriptionStatus == "pending" {
                isRetryingTranscription = false
            }
        }
    }

    private func generateSummaryForSermon(_ sermon: Sermon) {
        guard let transcript = sermon.transcript, !transcript.text.isEmpty else {
            print("[SermonDetailView] No transcript for summary generation")
            return
        }
        print("[SermonDetailView] Generating summary via coordinator")
        processingCoordinator.retrySummary(for: sermon.id)
    }
}

// MARK: - Preview

#Preview {
    SermonDetailView(
        sermonService: SermonService(modelContext: try! ModelContext(ModelContainer(
            for: Sermon.self, Note.self, Transcript.self, Summary.self,
            ProcessingJob.self, TranscriptSegment.self
        ))),
        authManager: AuthenticationManager.shared,
        sermonID: UUID()
    )
}
