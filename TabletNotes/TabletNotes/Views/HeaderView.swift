import SwiftUI

struct HeaderView: View {
    let title: String
    let showLogo: Bool
    let showSearch: Bool
    let showSettings: Bool
    var onSearch: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            if showLogo {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 36)
                    .accessibilityLabel("TabletNotes Logo")
                    .padding(.trailing, 8)
            }
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .accessibilityAddTraits(.isHeader)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            if showSearch {
                Button(action: { onSearch?() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(hex: "#F7F7F7"))
                            .frame(width: 40, height: 40)
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                            .accessibilityLabel("Search")
                    }
                }
            }
            if showSettings {
                Button(action: { onSettings?() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(hex: "#F7F7F7"))
                            .frame(width: 40, height: 40)
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                            .accessibilityLabel("Settings")
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(Color.white.opacity(0.95))
    }
}

#Preview {
    VStack(spacing: 0) {
        HeaderView(title: "TabletNotes", showLogo: true, showSearch: true, showSettings: true)
        Divider()
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
} 