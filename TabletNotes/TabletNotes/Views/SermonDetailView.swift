import SwiftUI
import AVFoundation
import SwiftData

struct SermonDetailView: View {
    let sermon: Sermon
    var onBack: (() -> Void)?
    @State private var selectedTab: Tab = .summary
    @State private var audioPlayer: AVAudioPlayer? = nil
    @State private var isPlaying: Bool = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var timer: Timer? = nil
    
    enum Tab: String, CaseIterable {
        case summary = "Summary"
        case transcript = "Transcript"
        case notes = "Notes"
    }
    
    var body: some View {
        return VStack(spacing: 0) {
            // Top Bar
            HStack(alignment: .center) {
                Button(action: { onBack?() }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.black)
                }
                .padding(.trailing, 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sermon.title)
                        .font(.headline)
                        .foregroundColor(.black)
                    HStack(spacing: 8) {
                        Text(formattedDate)
                        Text(formattedTime)
                        if duration > 0 {
                            Text("\(Int(duration / 60)) min")
                        }
                        // Speaker could be added here in the future
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
                    ScrollView {
                        let cleanSummary = (sermon.summary?.text ?? "No summary available.").replacingOccurrences(of: "**", with: "")
                        Text(cleanSummary).padding()
                    }
                case .transcript:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let segments = sermon.transcript?.segments, !segments.isEmpty {
                                ForEach(segments, id: \.id) { segment in
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
                                                .frame(width: 60, alignment: .leading)
                                        }
                                        Text(segment.text)
                                            .font(.body)
                                            .background(
                                                (audioPlayer?.isPlaying == true && abs((audioPlayer?.currentTime ?? 0) - segment.startTime) < 0.5) ? Color.yellow.opacity(0.2) : Color.clear
                                            )
                                    }
                                }
                            } else {
                                Text(sermon.transcript?.text ?? "No transcript available.")
                                    .padding(.top, 8)
                            }
                            Spacer(minLength: 24)
                            // Audio Player UI at the bottom
                            let url = sermon.audioFileURL
                            VStack(spacing: 8) {
                                // Progress bar with scrubbing
                                Slider(value: Binding(
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
                                            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                                                currentTime = audioPlayer?.currentTime ?? 0
                                                if let player = audioPlayer, !player.isPlaying {
                                                    isPlaying = false
                                                    timer?.invalidate()
                                                }
                                            }
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
                        }.padding()
                    }
                case .notes:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(sermon.notes) { note in
                                Text(note.text)
                                    .font(.body)
                            }
                        }.padding()
                    }
                }
                Spacer()
                // Bottom Tab Bar
                HStack {
                    VStack {
                        Image(systemName: "house.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("Home").font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    Button(action: {}) {
                        ZStack {
                            Circle().fill(Color.blue).frame(width: 56, height: 56)
                            Image(systemName: "mic.fill").foregroundColor(.white).font(.title2)
                        }
                    }
                    .offset(y: -16)
                    VStack {
                        Image(systemName: "person")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("Account").font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(Color.white.shadow(radius: 2))
            }
            .background(Color.white.ignoresSafeArea())
            .onAppear {
                if duration == 0 {
                    let url = sermon.audioFileURL
                    do {
                        let player = try AVAudioPlayer(contentsOf: url)
                        duration = player.duration
                    } catch {
                        print("Failed to load audio for duration: \(error)")
                    }
                }
            }
            .onDisappear {
                timer?.invalidate()
                audioPlayer?.stop()
                audioPlayer = nil
            }
        }
    }
    
    private var formattedDate: String {
        DateFormatter.localizedString(from: sermon.date, dateStyle: .medium, timeStyle: .none)
    }
    private var formattedTime: String {
        DateFormatter.localizedString(from: sermon.date, dateStyle: .none, timeStyle: .short)
    }
    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
