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
                        .foregroundColor(selectedTab == .home ? .blue : .gray)
                    Text("Home")
                        .font(.caption)
                        .foregroundColor(selectedTab == .home ? .blue : .gray)
                }
            }
            .frame(maxWidth: .infinity)
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.blue)
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
                        .foregroundColor(selectedTab == .account ? .blue : .gray)
                    Text("Account")
                        .font(.caption)
                        .foregroundColor(selectedTab == .account ? .blue : .gray)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(Color.white.shadow(radius: 2))
    }
}

#Preview {
    FooterView(selectedTab: .home)
} 