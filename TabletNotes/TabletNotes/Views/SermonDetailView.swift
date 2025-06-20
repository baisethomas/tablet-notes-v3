import SwiftUI
import AVFoundation
import SwiftData
// Add these imports if needed for model and view types
// import TabletNotes.Models // Uncomment if models are in a separate module
// import TabletNotes.Services // Uncomment if services are in a separate module
// Ensure TabletNotes/TabletNotes/Models/Sermon.swift and TabletNotes/TabletNotes/Views/HeaderView.swift are included in the build target
// Ensure TabletNotes/TabletNotes/Models/Sermon.swift is included in the build target for this file to resolve 'Sermon' in scope.
// import TabletNotes.Models // Removed because the module does not exist and causes a build error.

struct SermonDetailView: View {
    @ObservedObject var sermonService: SermonService
    let sermonID: UUID
    var onBack: (() -> Void)?
    @State private var selectedTab: Tab = .summary
    @State private var audioPlayer: AVAudioPlayer? = nil
    @State private var isPlaying: Bool = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var timer: Timer? = nil
    @State private var editableTitle: String = ""
    
    enum Tab: String, CaseIterable {
        case summary = "Summary"
        case transcript = "Transcript"
        case notes = "Notes"
    }
    
    var sermon: Sermon? {
        sermonService.sermons.first(where: { $0.id == sermonID })
    }
    
    var body: some View {
        let sermon = sermon
        if sermon != nil {
            let sermon = sermon! // safe because of the check above
            VStack(spacing: 0) {
                HeaderView(
                    title: "",
                    showLogo: false,
                    showSearch: false,
                    showSettings: true,
                    showBack: true,
                    onBack: onBack
                )
                // Top Bar
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Title", text: $editableTitle, onCommit: {
                            sermonService.saveSermon(
                                title: editableTitle,
                                audioFileURL: sermon.audioFileURL,
                                date: sermon.date,
                                serviceType: sermon.serviceType,
                                transcript: sermon.transcript,
                                notes: sermon.notes,
                                summary: sermon.summary,
                                transcriptionStatus: sermon.transcriptionStatus,
                                summaryStatus: sermon.summaryStatus,
                                id: sermon.id
                            )
                        })
                        .font(.headline)
                        .foregroundColor(.black)
                        HStack(spacing: 8) {
                            Text(formattedDate)
                            Text(formattedTime)
                            if duration > 0 {
                                Text("\(Int(duration / 60)) min")
                            }
                            Text(sermon.serviceType)
                        }
                        .font(.caption)
                        .foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding([.top, .horizontal])
                // Segmented Control
                HStack {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Button(action: { selectedTab = tab }) {
                            VStack {
                                Text(tab.rawValue)
                                    .font(.subheadline)
                                    .foregroundColor(selectedTab == tab ? Color.blue : Color.primary)
                                Rectangle()
                                    .frame(height: 2)
                                    .foregroundColor(selectedTab == tab ? Color.blue : Color.clear)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 8)
                .background(Color.white)
                Divider()
                // Content Area
                Group {
                    switch selectedTab {
                    case .summary:
                        summaryTabView
                    case .transcript:
                        transcriptTabView
                    case .notes:
                        notesTabView
                    }
                    Spacer()
                }
                .onAppear {
                    editableTitle = sermon.title
                    if duration == 0 {
                        let url = sermon.audioFileURL
                        do {
                            let player = try AVAudioPlayer(contentsOf: url)
                            duration = player.duration
                        } catch {
                            print("Failed to load audio for duration: \(error)")
                        }
                    }
                    print("[DEBUG] SermonDetailView onAppear: transcriptionStatus = \(sermon.transcriptionStatus)")
                }
                .onChange(of: sermon.transcriptionStatus) { oldValue, newValue in
                    print("[DEBUG] SermonDetailView transcriptionStatus changed: \(oldValue) -> \(newValue)")
                }
                .onDisappear {
                    timer?.invalidate()
                    audioPlayer?.stop()
                    audioPlayer = nil
                }
            }
        } else {
            VStack {
                Text("This sermon was deleted or is no longer available.")
                    .foregroundColor(.secondary)
                    .padding()
                Button("Back to Sermons") {
                    onBack?()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var formattedDate: String {
        DateFormatter.localizedString(from: sermon?.date ?? Date(), dateStyle: .medium, timeStyle: .none)
    }
    private var formattedTime: String {
        DateFormatter.localizedString(from: sermon?.date ?? Date(), dateStyle: .none, timeStyle: .short)
    }
    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var summaryTabView: some View {
        if let sermon = sermon {
            if sermon.summaryStatus == "processing" {
                return AnyView(VStack { ProgressView("Generating summary...") }.padding())
            } else if sermon.summaryStatus == "failed" {
                return AnyView(VStack { Text("Summary generation failed.").foregroundColor(.red) }.padding())
            } else {
                let cleanSummary = (sermon.summary?.text ?? "No summary available.").replacingOccurrences(of: "**", with: "")
                return AnyView(ScrollView { Text(cleanSummary).padding().padding(.bottom, 100) })
            }
        } else {
            return AnyView(Text("No summary available.").padding())
        }
    }

    var transcriptTabView: some View {
        if let sermon = sermon {
            if sermon.transcriptionStatus == "processing" {
                return AnyView(VStack { ProgressView("Transcribing audio...") }.padding())
            } else if sermon.transcriptionStatus == "failed" {
                return AnyView(VStack { Text("Transcription failed.").foregroundColor(.red) }.padding())
            } else {
                return AnyView(
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let segments = sermon.transcript?.segments, !segments.isEmpty {
                                ForEach(segments.sorted(by: { $0.startTime < $1.startTime }), id: \.id) { segment in
                                    HStack(alignment: .top, spacing: 8) {
                                        Button(action: {
                                            if audioPlayer == nil {
                                                let url = sermon.audioFileURL
                                                do {
                                                    audioPlayer = try AVAudioPlayer(contentsOf: url)
                                                    duration = audioPlayer?.duration ?? 0
                                                    audioPlayer?.prepareToPlay()
                                                } catch {
                                                    print("Failed to load audio: \(error)")
                                                }
                                            }
                                            audioPlayer?.currentTime = segment.startTime
                                            audioPlayer?.play()
                                            isPlaying = true
                                            timer?.invalidate()
                                            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                                                currentTime = audioPlayer?.currentTime ?? 0
                                                if let player = audioPlayer, !player.isPlaying {
                                                    isPlaying = false
                                                    timer?.invalidate()
                                                }
                                            }
                                        }) {
                                            Text("[\(timeString(from: segment.startTime))]")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                                .underline()
                                        }
                                        Text(segment.text)
                                            .font(.body)
                                    }
                                }
                            } else {
                                Text(sermon.transcript?.text ?? "No transcript available.")
                                    .padding(.top, 8)
                            }
                            Spacer(minLength: 24)
                            VStack(spacing: 8) {
                                Slider(value: Binding<Double>(
                                    get: { currentTime },
                                    set: { newValue in
                                        currentTime = newValue
                                        audioPlayer?.currentTime = newValue
                                    }
                                ), in: 0...(duration > 0 ? duration : 1))
                                .accentColor(.blue)
                                HStack(spacing: 16) {
                                    Button(action: {
                                        if isPlaying {
                                            audioPlayer?.pause()
                                            isPlaying = false
                                            timer?.invalidate()
                                        } else {
                                            if audioPlayer == nil {
                                                let url = sermon.audioFileURL
                                                do {
                                                    audioPlayer = try AVAudioPlayer(contentsOf: url)
                                                    duration = audioPlayer?.duration ?? 0
                                                    audioPlayer?.prepareToPlay()
                                                } catch {
                                                    print("Failed to load audio: \(error)")
                                                }
                                            }
                                            audioPlayer?.play()
                                            isPlaying = true
                                            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true, block: { _ in
                                                currentTime = audioPlayer?.currentTime ?? 0
                                                if let player = audioPlayer, !player.isPlaying {
                                                    isPlaying = false
                                                    timer?.invalidate()
                                                }
                                            })
                                        }
                                    }) {
                                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .resizable()
                                            .frame(width: 40, height: 40)
                                            .foregroundColor(.blue)
                                    }
                                    Text("\(timeString(from: currentTime)) / \(timeString(from: duration))")
                                        .font(.caption)
                                }
                            }
                            .padding(.top, 16)
                        }.padding().padding(.bottom, 100)
                    }
                )
            }
        } else {
            return AnyView(Text("No transcript available.").padding())
        }
    }

    var notesTabView: some View {
        if let sermon = sermon {
            return AnyView(
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sermon.notes as [Note], id: \.id) { note in
                            Text(note.text)
                                .font(.body)
                        }
                    }.padding().padding(.bottom, 100)
                }
            )
        } else {
            return AnyView(Text("No notes available.").padding())
        }
    }
}

