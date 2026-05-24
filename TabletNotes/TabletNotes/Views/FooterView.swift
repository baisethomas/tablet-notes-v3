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
            return Color.SV.primary
        } else {
            return Color.SV.tertiary
        }
    }

    private var buttonIcon: String {
        if !isRecording {
            return "mic.fill"
        } else if isPaused {
            return "play.fill"
        } else {
            return "pause.fill"
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
                        .foregroundStyle(selectedTab == .home ? Color.SV.primary : Color.SV.onSurface.opacity(0.35))
                    Text("Home")
                        .font(.caption)
                        .foregroundStyle(selectedTab == .home ? Color.SV.primary : Color.SV.onSurface.opacity(0.35))
                }
            }
            .frame(maxWidth: .infinity)
            ZStack {
                Rectangle()
                    .fill(buttonColor)
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 16, style: .continuous))
                Button(action: { onRecord?() }) {
                    Image(systemName: buttonIcon)
                        .foregroundStyle(.white)
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
                        .foregroundStyle(selectedTab == .account ? Color.SV.primary : Color.SV.onSurface.opacity(0.35))
                    Text("Account")
                        .font(.caption)
                        .foregroundStyle(selectedTab == .account ? Color.SV.primary : Color.SV.onSurface.opacity(0.35))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(Color.SV.surface)
        .shadow(color: Color.SV.onSurface.opacity(0.06), radius: 2, x: 0, y: -1)
    }
}

#Preview {
    FooterView(selectedTab: .home)
}
