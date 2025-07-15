import SwiftUI

struct HeaderView: View {
    let title: String
    let showLogo: Bool
    let showSearch: Bool
    let showSyncStatus: Bool
    let showBack: Bool
    let syncStatus: SyncStatus
    var onBack: (() -> Void)? = nil
    var onSearch: (() -> Void)? = nil
    var onSyncStatus: (() -> Void)? = nil
    
    // Convenience initializer with default sync status
    init(title: String, showLogo: Bool = false, showSearch: Bool = false, showSyncStatus: Bool = false, showBack: Bool = false, syncStatus: SyncStatus = .synced, onBack: (() -> Void)? = nil, onSearch: (() -> Void)? = nil, onSyncStatus: (() -> Void)? = nil) {
        self.title = title
        self.showLogo = showLogo
        self.showSearch = showSearch
        self.showSyncStatus = showSyncStatus
        self.showBack = showBack
        self.syncStatus = syncStatus
        self.onBack = onBack
        self.onSearch = onSearch
        self.onSyncStatus = onSyncStatus
    }
    
    enum SyncStatus {
        case synced
        case syncing
        case error
        case localOnly
        case offline
    }
    
    var body: some View {
        HStack {
            if showBack {
                Button(action: { onBack?() }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.adaptiveAccent)
                        .accessibilityLabel("Back")
                }
                .padding(.trailing, 8)
            }
            if showLogo {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 48)
                    .accessibilityLabel("TabletNotes Logo")
                    .padding(.trailing, 8)
            }
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.adaptivePrimaryText)
                .accessibilityAddTraits(.isHeader)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            if showSearch {
                Button(action: { onSearch?() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.adaptiveInputBackground)
                            .frame(width: 40, height: 40)
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.adaptiveAccent)
                            .accessibilityLabel("Search")
                    }
                }
            }
            if showSyncStatus {
                Button(action: { onSyncStatus?() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.adaptiveInputBackground)
                            .frame(width: 40, height: 40)
                        
                        if syncStatus == .syncing {
                            // Show loading spinner for syncing
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(CircularProgressViewStyle(tint: syncStatusColor))
                        } else {
                            Image(systemName: syncStatusIcon)
                                .font(.title2)
                                .foregroundColor(syncStatusColor)
                        }
                    }
                }
                .accessibilityLabel(syncStatusAccessibilityLabel)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(Color.navigationBackground)
    }
    
    private var syncStatusIcon: String {
        switch syncStatus {
        case .synced:
            return "checkmark.icloud"
        case .syncing:
            return "icloud"
        case .error:
            return "exclamationmark.icloud"
        case .localOnly:
            return "icloud.slash"
        case .offline:
            return "wifi.slash"
        }
    }
    
    private var syncStatusColor: Color {
        switch syncStatus {
        case .synced:
            return .successGreen
        case .syncing:
            return .warningOrange
        case .error:
            return .recordingRed
        case .localOnly:
            return .adaptiveSecondaryText
        case .offline:
            return .adaptiveSecondaryText
        }
    }
    
    private var syncStatusAccessibilityLabel: String {
        switch syncStatus {
        case .synced:
            return "All data synced"
        case .syncing:
            return "Syncing data"
        case .error:
            return "Sync error - tap for details"
        case .localOnly:
            return "Local data only"
        case .offline:
            return "Offline mode"
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        HeaderView(title: "TabletNotes", showLogo: true, showSearch: true, showSyncStatus: true, showBack: true, syncStatus: HeaderView.SyncStatus.synced, onBack: {})
        Divider()
        HeaderView(title: "Syncing...", showLogo: true, showSyncStatus: true, syncStatus: HeaderView.SyncStatus.syncing)
        Divider()
        HeaderView(title: "Error", showLogo: true, showSyncStatus: true, syncStatus: HeaderView.SyncStatus.error)
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