import SwiftUI

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
            // Thin progress bar at the top
            Rectangle()
                .fill(Color.recordingRed.opacity(0.3))
                .frame(height: 2)
                .overlay(
                    HStack {
                        Rectangle()
                            .fill(Color.recordingRed)
                            .frame(height: 2)
                            .animation(.easeInOut(duration: 0.3), value: duration)
                        Spacer()
                    }
                )

            // Main mini-player content
            HStack(spacing: 12) {
                // Waveform indicator
                WaveformView(isRecording: isRecording && !isPaused)
                    .frame(width: 40, height: 20)

                // Recording info
                VStack(alignment: .leading, spacing: 2) {
                    Text(serviceType)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
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
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(formatDuration(duration))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Control buttons
                HStack(spacing: 8) {
                    // Play/Pause button
                    Button(action: onPlayPause) {
                        Image(systemName: playPauseIcon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 32, height: 32)
                            .background(Color.adaptiveBackground)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.adaptiveBorder, lineWidth: 1)
                            )
                    }

                    // Stop button
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.recordingRed)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.adaptiveBackground)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
        }
        .background(Color.adaptiveBackground)
        .overlay(
            Rectangle()
                .fill(Color.adaptiveBorder)
                .frame(height: 1),
            alignment: .top
        )
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
    }

    // MARK: - Computed Properties

    private var recordingStatusColor: Color {
        if !isRecording {
            return .gray
        } else if isPaused {
            return .orange
        } else {
            return .recordingRed
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