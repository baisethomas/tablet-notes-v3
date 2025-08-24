import SwiftUI

enum FooterTab {
    case home, record, account
}

struct FooterView: View {
    var selectedTab: FooterTab
    var isRecording: Bool = false
    var isPaused: Bool = false
    var onHome: (() -> Void)? = nil
    var onRecord: (() -> Void)? = nil
    var onAccount: (() -> Void)? = nil
    
    // Computed properties for button appearance
    private var buttonColor: Color {
        if !isRecording {
            return .recordingRed    // Red color for starting recording (matches RecordingView)
        } else if isPaused {
            return .successGreen    // Green for resume (matches RecordingView)
        } else {
            return .warningOrange   // Orange for pause (matches RecordingView)
        }
    }
    
    private var buttonIcon: String {
        if !isRecording {
            return "mic.fill"      // Microphone for start recording
        } else if isPaused {
            return "play.fill"     // Play icon for resume
        } else {
            return "pause.fill"    // Pause icon for pause
        }
    }
    
    private var accessibilityLabel: String {
        if !isRecording {
            return "Record"
        } else if isPaused {
            return "Resume Recording"
        } else {
            return "Pause Recording"
        }
    }
    
    var body: some View {
        HStack {
            Button(action: { onHome?() }) {
                VStack {
                    Image(systemName: "house.fill")
                        .font(.title2)
                        .foregroundColor(selectedTab == .home ? .adaptiveAccent : .adaptiveSecondaryText)
                    Text("Home")
                        .font(.caption)
                        .foregroundColor(selectedTab == .home ? .adaptiveAccent : .adaptiveSecondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(buttonColor)
                    .frame(width: 56, height: 56)
                Button(action: { onRecord?() }) {
                    Image(systemName: buttonIcon)
                        .foregroundColor(.white)
                        .font(.title2)
                        .accessibilityLabel(accessibilityLabel)
                }
            }
            .offset(y: -16)
            .frame(maxWidth: .infinity)
            Button(action: { onAccount?() }) {
                VStack {
                    Image(systemName: "person")
                        .font(.title2)
                        .foregroundColor(selectedTab == .account ? .adaptiveAccent : .adaptiveSecondaryText)
                    Text("Account")
                        .font(.caption)
                        .foregroundColor(selectedTab == .account ? .adaptiveAccent : .adaptiveSecondaryText)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(Color.navigationBackground)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: -1)
    }
}

#Preview {
    FooterView(selectedTab: .home)
} 