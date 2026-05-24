import SwiftUI

// MARK: - Waveform View
// Moved here from RecordingView — MiniPlayer is its only consumer.
struct WaveformView: View {
    let isRecording: Bool
    @State private var animationPhase: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isRecording ? Color.SV.tertiary : Color.SV.onSurface.opacity(0.2))
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(
                        isRecording ?
                            .easeInOut(duration: 0.5 + Double(index) * 0.1).repeatForever(autoreverses: true) :
                            .easeInOut(duration: 0.3),
                        value: isRecording
                    )
            }
        }
        .onAppear { startAnimation() }
        .onChange(of: isRecording) { _, newValue in
            if newValue { startAnimation() }
        }
    }

    private func startAnimation() {
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            animationPhase = 1
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 4
        let maxHeight: CGFloat = 24
        guard isRecording else { return baseHeight }
        let phase = animationPhase * 2 * .pi + Double(index) * 0.8
        let variation = sin(phase) * 0.5 + 0.5
        return baseHeight + (maxHeight - baseHeight) * variation
    }
}

// MARK: - Mini Player

struct MiniPlayer: View {
    let serviceType: String
    let duration: TimeInterval
    let isRecording: Bool
    let isPaused: Bool
    let onTap: () -> Void
    let onPlayPause: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Tonal separator
            Rectangle()
                .fill(Color.SV.onSurface.opacity(0.06))
                .frame(height: 0.5)

            // Thin progress bar at the top
            Rectangle()
                .fill(Color.SV.tertiary.opacity(0.12))
                .frame(height: 2)
                .overlay(
                    HStack {
                        Rectangle()
                            .fill(Color.SV.tertiary)
                            .frame(height: 2)
                            .animation(.easeInOut(duration: 0.3), value: duration)
                        Spacer()
                    }
                )

            // Main mini-player content
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // Waveform indicator
                    WaveformView(isRecording: isRecording && !isPaused)
                        .frame(width: 40, height: 20)

                    // Recording info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(serviceType)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.SV.onSurface)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            // Recording status indicator
                            Circle()
                                .fill(recordingStatusColor)
                                .frame(width: 6, height: 6)
                                .scaleEffect(isRecording && !isPaused ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isRecording && !isPaused)

                            Text(recordingStatusText)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.SV.onSurface.opacity(0.5))

                            Spacer()

                            Text(formatDuration(duration))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.SV.onSurface.opacity(0.5))
                        }
                    }

                    Spacer()

                    // Control buttons
                    HStack(spacing: 8) {
                        // Play/Pause button
                        Button(action: onPlayPause) {
                            Image(systemName: playPauseIcon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.SV.onSurface)
                                .frame(width: 32, height: 32)
                                .background(Color.SV.onSurface.opacity(0.07))
                                .clipShape(Circle())
                        }

                        // Stop button
                        Button(action: onStop) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.SV.tertiary)
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.SV.surface)
        }
        .background(Color.SV.surface)
        .shadow(color: Color.SV.onSurface.opacity(0.08), radius: 8, x: 0, y: -2)
    }

    // MARK: - Computed Properties

    private var recordingStatusColor: Color {
        if !isRecording {
            return Color.SV.onSurface.opacity(0.3)
        } else if isPaused {
            return Color.SV.tertiary.opacity(0.6)
        } else {
            return Color.SV.tertiary
        }
    }

    private var recordingStatusText: String {
        if !isRecording {
            return "Recording stopped"
        } else if isPaused {
            return "Paused"
        } else {
            return "Recording"
        }
    }

    private var playPauseIcon: String {
        if !isRecording {
            return "play.fill"
        } else if isPaused {
            return "play.fill"
        } else {
            return "pause.fill"
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()

        MiniPlayer(
            serviceType: "Sunday Service",
            duration: 185, // 3:05
            isRecording: true,
            isPaused: false,
            onTap: { print("Mini-player tapped") },
            onPlayPause: { print("Play/pause tapped") },
            onStop: { print("Stop tapped") }
        )
    }
    .background(Color.gray.opacity(0.1))
}

#Preview("Paused State") {
    VStack {
        Spacer()

        MiniPlayer(
            serviceType: "Bible Study",
            duration: 1285, // 21:25
            isRecording: true,
            isPaused: true,
            onTap: { print("Mini-player tapped") },
            onPlayPause: { print("Play/pause tapped") },
            onStop: { print("Stop tapped") }
        )
    }
    .background(Color.gray.opacity(0.1))
}
