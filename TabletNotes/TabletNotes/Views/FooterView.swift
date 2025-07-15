import SwiftUI

enum FooterTab {
    case home, record, account
}

struct FooterView: View {
    var selectedTab: FooterTab
    var onHome: (() -> Void)? = nil
    var onRecord: (() -> Void)? = nil
    var onAccount: (() -> Void)? = nil
    
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
                    .fill(Color.adaptiveAccent)
                    .frame(width: 56, height: 56)
                Button(action: { onRecord?() }) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.white)
                        .font(.title2)
                        .accessibilityLabel("Record")
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