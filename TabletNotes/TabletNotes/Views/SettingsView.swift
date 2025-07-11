import SwiftUI
import StoreKit

struct SettingsView: View {
    @StateObject private var settings = SettingsService.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var showingResetAlert = false
    @State private var showingAbout = false
    @State private var showingSubscriptionPrompt = false
    
    var onNext: (() -> Void)?
    var onShowOnboarding: (() -> Void)?
    var onNavigateToAccount: (() -> Void)?
    var sermonService: SermonService?
    
    var body: some View {
        VStack(spacing: 0) {
            HeaderView(title: "Settings", showLogo: false, showSearch: false, showSyncStatus: false, showBack: true, onBack: {
                onNext?()
            })
            
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Recording Settings
                    SettingsSection(title: "Recording") {
                        VStack(spacing: 0) {
                            SettingsPicker(
                                icon: "waveform.circle",
                                title: "Audio Quality",
                                subtitle: settings.audioQuality.description,
                                selection: $settings.audioQuality
                            )
                            
                            SettingsDivider()
                            
                            SettingsToggle(
                                icon: "text.bubble",
                                title: "Auto-Transcription",
                                subtitle: "Start transcribing while recording",
                                isOn: $settings.autoTranscription
                            )
                            
                            SettingsDivider()
                            
                            SettingsRow(icon: "clock", title: "Auto-Stop Timer", subtitle: "Minutes until recording stops automatically") {
                                Picker("", selection: $settings.autoStopMinutes) {
                                    Text("30 min").tag(30)
                                    Text("60 min").tag(60)
                                    Text("90 min").tag(90)
                                    Text("120 min").tag(120)
                                    Text("Never").tag(0)
                                }
                                .pickerStyle(MenuPickerStyle())
                                .labelsHidden()
                            }
                            
                            SettingsDivider()
                            
                            SettingsRow(icon: "doc.text", title: "Default Service Type", subtitle: "Type of service for new recordings") {
                                Picker("", selection: $settings.defaultServiceType) {
                                    Text("Sermon").tag("Sermon")
                                    Text("Bible Study").tag("Bible Study")
                                    Text("Prayer Meeting").tag("Prayer Meeting")
                                    Text("Other").tag("Other")
                                }
                                .pickerStyle(MenuPickerStyle())
                                .labelsHidden()
                            }
                        }
                    }
                    
                    // Transcription Settings
                    SettingsSection(title: "Transcription") {
                        VStack(spacing: 0) {
                            SettingsPicker(
                                icon: "brain.head.profile",
                                title: "Transcription Provider",
                                subtitle: settings.transcriptionProvider.description,
                                selection: $settings.transcriptionProvider
                            )
                            
                            SettingsDivider()
                            
                            SettingsRow(icon: "globe", title: "Language", subtitle: "Primary language for transcription") {
                                Picker("", selection: $settings.transcriptionLanguage) {
                                    Text("English (US)").tag("en-US")
                                    Text("English (UK)").tag("en-GB")
                                    Text("Spanish").tag("es")
                                    Text("French").tag("fr")
                                    Text("German").tag("de")
                                }
                                .pickerStyle(MenuPickerStyle())
                                .labelsHidden()
                            }
                            
                            SettingsDivider()
                            
                            SettingsToggle(
                                icon: "textformat",
                                title: "Auto-Punctuation",
                                subtitle: "Automatically add punctuation to transcripts",
                                isOn: $settings.autoPunctuation
                            )
                            
                            SettingsDivider()
                            
                            SettingsToggle(
                                icon: "person.2",
                                title: "Speaker Detection",
                                subtitle: "Identify different speakers in recordings",
                                isOn: $settings.speakerDetection
                            )
                        }
                    }
                    
                    // Storage & Sync Settings
                    SettingsSection(title: "Storage & Sync") {
                        VStack(spacing: 0) {
                            SettingsSlider(
                                icon: "internaldrive",
                                title: "Max Local Storage",
                                subtitle: "Maximum storage for recordings and transcripts",
                                value: $settings.maxLocalStorageGB,
                                range: 1...20,
                                step: 0.5
                            )
                            
                            SettingsDivider()
                            
                            SettingsPicker(
                                icon: "trash.circle",
                                title: "Auto-Delete Period",
                                subtitle: "Automatically delete old recordings",
                                selection: $settings.autoDeletePeriod
                            )
                            
                            SettingsDivider()
                            
                            CloudSyncSettingRow(
                                authManager: authManager,
                                sermonService: sermonService,
                                showingSubscriptionPrompt: $showingSubscriptionPrompt
                            )
                            
                            SettingsDivider()
                            
                            SettingsNavigationRow(
                                icon: "archivebox",
                                title: "Archived Sermons",
                                subtitle: "View and manage archived sermons",
                                action: {
                                    // Navigate to archived sermons view
                                    // For now, just provide haptic feedback
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                }
                            )
                            
                        }
                    }
                    
                    // Privacy & Data Settings
                    SettingsSection(title: "Privacy & Data") {
                        VStack(spacing: 0) {
                            SettingsToggle(
                                icon: "chart.bar",
                                title: "Usage Analytics",
                                subtitle: "Share anonymous usage data to improve the app",
                                isOn: $settings.analyticsEnabled
                            )
                            
                            SettingsDivider()
                            
                            SettingsToggle(
                                icon: "location",
                                title: "Location Tagging",
                                subtitle: "Add location information to recordings",
                                isOn: $settings.locationTagging
                            )
                            
                            SettingsDivider()
                            
                            SettingsToggle(
                                icon: "square.and.arrow.up",
                                title: "Research Data Sharing",
                                subtitle: "Allow sharing anonymized data for research",
                                isOn: $settings.dataSharingEnabled
                            )
                            
                            SettingsDivider()
                            
                            SettingsToggle(
                                icon: "wifi.slash",
                                title: "Offline Mode",
                                subtitle: "Disable network features to save data",
                                isOn: $settings.offlineMode
                            )
                        }
                    }
                    
                    // Appearance Settings
                    SettingsSection(title: "Appearance") {
                        VStack(spacing: 0) {
                            SettingsPicker(
                                icon: "paintbrush",
                                title: "Theme",
                                subtitle: "Choose light, dark, or system theme",
                                selection: $settings.appTheme
                            )
                            
                            SettingsDivider()
                            
                            SettingsPicker(
                                icon: "textformat.size",
                                title: "Font Size",
                                subtitle: "Adjust text size throughout the app",
                                selection: $settings.fontSize
                            )
                            
                            SettingsDivider()
                            
                            SettingsToggle(
                                icon: "motion.disable",
                                title: "Reduce Animations",
                                subtitle: "Minimize visual effects and animations",
                                isOn: $settings.reduceAnimations
                            )
                            
                            SettingsDivider()
                            
                            SettingsToggle(
                                icon: "rectangle.compress.vertical",
                                title: "Compact Mode",
                                subtitle: "Show more content in less space",
                                isOn: $settings.compactMode
                            )
                        }
                    }
                    
                    // Export & Backup Settings
                    SettingsSection(title: "Export & Backup") {
                        VStack(spacing: 0) {
                            SettingsRow(icon: "doc.text", title: "Default Export Format", subtitle: "Format for exported transcripts and notes") {
                                Picker("", selection: $settings.defaultExportFormat) {
                                    Text("PDF").tag("PDF")
                                    Text("Word").tag("DOCX")
                                    Text("Text").tag("TXT")
                                    Text("Markdown").tag("MD")
                                }
                                .pickerStyle(MenuPickerStyle())
                                .labelsHidden()
                            }
                            
                            SettingsDivider()
                            
                            SettingsToggle(
                                icon: "waveform",
                                title: "Include Audio in Export",
                                subtitle: "Bundle audio files with exported documents",
                                isOn: $settings.includeAudioInExport
                            )
                            
                            SettingsDivider()
                            
                            SettingsToggle(
                                icon: "clock.arrow.circlepath",
                                title: "Auto-Backup",
                                subtitle: "Automatically backup to iCloud weekly",
                                isOn: $settings.autoBackupEnabled
                            )
                        }
                    }
                    
                    // Advanced Settings
                    SettingsSection(title: "Advanced") {
                        VStack(spacing: 0) {
                            SettingsNavigationRow(
                                icon: "questionmark.circle",
                                title: "App Tutorial",
                                subtitle: "Learn how to use TabletNotes features"
                            ) {
                                onShowOnboarding?()
                            }
                            
                            SettingsDivider()
                            
                            SettingsNavigationRow(
                                icon: "info.circle",
                                title: "About TabletNotes",
                                subtitle: "App version, features, and technical info"
                            ) {
                                showingAbout = true
                            }
                            
                            SettingsDivider()
                            
                            SettingsButton(
                                icon: "arrow.clockwise",
                                title: "Reset All Settings",
                                subtitle: "Restore default app settings",
                                style: .destructive
                            ) {
                                showingResetAlert = true
                            }
                        }
                    }
                    
                    // Account Settings
                    SettingsSection(title: "Account") {
                        VStack(spacing: 0) {
                            SettingsNavigationRow(
                                icon: "person.circle",
                                title: "Account & Profile",
                                subtitle: "Manage your account, notifications, and privacy"
                            ) {
                                onNavigateToAccount?()
                            }
                        }
                    }
                }
                .padding(.vertical, 24)
            }
        }
        .background(Color(red: 0.97, green: 0.97, blue: 0.97))
        .alert("Reset Settings", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
            }
        } message: {
            Text("This will reset all settings to their default values. This action cannot be undone.")
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .sheet(isPresented: $showingSubscriptionPrompt) {
            SubscriptionPromptView()
        }
    }
}

// MARK: - About View
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // App Info
                    VStack(alignment: .center, spacing: 16) {
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .cornerRadius(16)
                        
                        VStack(spacing: 8) {
                            Text("TabletNotes")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("AI-powered sermon transcription and note-taking")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Text("Version 1.0.0")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                    
                    // Technical Details
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Technical Information")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            FeatureRow(icon: "mic", title: "Audio Recording", description: "High-quality AAC encoding at configurable bitrates")
                            FeatureRow(icon: "text.bubble", title: "Transcription Engine", description: "AssemblyAI API with speaker diarization")
                            FeatureRow(icon: "brain.head.profile", title: "AI Summarization", description: "OpenAI GPT-powered content analysis")
                            FeatureRow(icon: "icloud", title: "Cloud Storage", description: "Secure Supabase backend with encryption")
                            FeatureRow(icon: "phone", title: "iOS Compatibility", description: "Supports iOS 17.0 and later")
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Version Information
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Build Information")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Version: 1.0.0 (Build 1)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("Build Date: July 2025")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("Target: iOS 17.0+")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer()
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Feature Row Component
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Cloud Sync Setting Row
struct CloudSyncSettingRow: View {
    @ObservedObject var authManager: AuthenticationManager
    let sermonService: SermonService?
    @Binding var showingSubscriptionPrompt: Bool
    
    private var canSync: Bool {
        authManager.currentUser?.canSync ?? false
    }
    
    private var subscriptionTier: String {
        authManager.currentUser?.subscriptionTier ?? "free"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "icloud")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cloud Sync")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(syncSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if canSync {
                    Button(action: {
                        sermonService?.syncAllData()
                    }) {
                        Text("Sync Now")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                } else {
                    Button(action: {
                        showingSubscriptionPrompt = true
                    }) {
                        Text("Upgrade")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            if !canSync {
                        HStack {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    
                    Text("Sync requires a paid subscription")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    
                            Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
    
    private var syncSubtitle: String {
        if canSync {
            return "Sync recordings and notes across devices"
        } else {
            return "Available with Pro subscription"
        }
    }
}

// MARK: - Subscription Prompt View
struct SubscriptionPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionService = SubscriptionService(
        authManager: AuthenticationManager.shared,
        supabaseService: SupabaseService()
    )
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        
                        Text("Upgrade to Pro")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Unlock powerful features and sync across all your devices")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)
                    
                    // Current Plan Status
                    if let user = AuthenticationManager.shared.currentUser {
                        CurrentPlanStatusView(user: user)
                    }
                    
                    // Features Comparison
                    FeatureComparisonView()
                    
                    // Pricing
                    if subscriptionService.isLoading {
                        ProgressView("Loading subscription options...")
                            .padding(.vertical, 40)
                    } else if !subscriptionService.availableProducts.isEmpty {
                        SubscriptionPlansView(subscriptionService: subscriptionService)
                    } else {
                        VStack(spacing: 16) {
                            Text("Choose Your Plan")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            VStack(spacing: 12) {
                                StaticPricingCard(plan: .proMonthly)
                                StaticPricingCard(plan: .proAnnual, isRecommended: true)
                                StaticPricingCard(plan: .premiumAnnual)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    
                    // Error message
                    if let errorMessage = subscriptionService.errorMessage {
                        Text(errorMessage)
                                .font(.caption)
                            .foregroundColor(.red)
                            .padding()
                    }
                    
                    // Restore purchases
                    Button("Restore Purchases") {
                        Task {
                            await subscriptionService.restorePurchases()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await subscriptionService.loadProducts()
            }
        }
    }
}

// MARK: - Current Plan Status View
struct CurrentPlanStatusView: View {
    let user: User
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: user.isPaidUser ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(user.isPaidUser ? .green : .gray)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Plan")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(user.currentPlan.tier.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                Text(user.subscriptionDisplayStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // Usage limits for free users
            if user.currentPlan.tier == .free {
                UsageLimitsView(user: user)
            }
                }
                .padding(.horizontal, 24)
    }
}

// MARK: - Usage Limits View
struct UsageLimitsView: View {
    let user: User
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Current Usage")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            VStack(spacing: 6) {
                if let remaining = user.remainingRecordings() {
                    UsageBarView(
                        title: "Recordings",
                        current: user.monthlyRecordingCount,
                        max: user.usageLimits.maxRecordings!,
                        remaining: remaining
                    )
                }
                
                if let remaining = user.remainingRecordingMinutes() {
                    UsageBarView(
                        title: "Recording Time",
                        current: user.monthlyRecordingMinutes,
                        max: user.usageLimits.maxRecordingMinutes!,
                        remaining: remaining,
                        suffix: "min"
                    )
                }
                
                if let remaining = user.remainingStorageGB() {
                    UsageBarView(
                        title: "Storage",
                        current: user.currentStorageUsedGB,
                        max: user.usageLimits.maxStorageGB!,
                        remaining: remaining,
                        suffix: "GB",
                        isDouble: true
                    )
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Usage Bar View
struct UsageBarView: View {
    let title: String
    let current: any Numeric
    let max: any Numeric
    let remaining: any Numeric
    let suffix: String
    let isDouble: Bool
    
    init(title: String, current: Int, max: Int, remaining: Int, suffix: String = "") {
        self.title = title
        self.current = current
        self.max = max
        self.remaining = remaining
        self.suffix = suffix
        self.isDouble = false
    }
    
    init(title: String, current: Double, max: Double, remaining: Double, suffix: String = "", isDouble: Bool = true) {
        self.title = title
        self.current = current
        self.max = max
        self.remaining = remaining
        self.suffix = suffix
        self.isDouble = isDouble
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if isDouble {
                    Text("\(String(format: "%.1f", current as! Double))/\(String(format: "%.1f", max as! Double)) \(suffix)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(current)/\(max) \(suffix)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                        .cornerRadius(2)
                    
                    Rectangle()
                        .fill(progressColor)
                        .frame(width: progressWidth(geometry.size.width), height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)
        }
    }
    
    private func progressWidth(_ totalWidth: CGFloat) -> CGFloat {
        let progress: Double
        if isDouble {
            progress = (current as! Double) / (max as! Double)
        } else {
            progress = Double(current as! Int) / Double(max as! Int)
        }
        return totalWidth * min(progress, 1.0)
    }
    
    private var progressColor: Color {
        let progress: Double
        if isDouble {
            progress = (current as! Double) / (max as! Double)
        } else {
            progress = Double(current as! Int) / Double(max as! Int)
        }
        
        if progress >= 0.9 {
            return .red
        } else if progress >= 0.7 {
            return .orange
        } else {
            return .blue
        }
    }
}

// MARK: - Feature Comparison View
struct FeatureComparisonView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("What You Get")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureComparisonRow(
                    feature: .cloudSync,
                    freeTier: false,
                    proTier: true,
                    premiumTier: true
                )
                
                FeatureComparisonRow(
                    feature: .unlimitedRecordings,
                    freeTier: false,
                    proTier: true,
                    premiumTier: true
                )
                
                FeatureComparisonRow(
                    feature: .backgroundSync,
                    freeTier: false,
                    proTier: true,
                    premiumTier: true
                )
                
                FeatureComparisonRow(
                    feature: .priorityTranscription,
                    freeTier: false,
                    proTier: true,
                    premiumTier: true
                )
                
                FeatureComparisonRow(
                    feature: .advancedSummaries,
                    freeTier: false,
                    proTier: false,
                    premiumTier: true
                )
                
                FeatureComparisonRow(
                    feature: .prioritySupport,
                    freeTier: false,
                    proTier: false,
                    premiumTier: true
                )
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Feature Comparison Row
struct FeatureComparisonRow: View {
    let feature: SubscriptionFeature
    let freeTier: Bool
    let proTier: Bool
    let premiumTier: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: feature.icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(feature.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Image(systemName: freeTier ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundColor(freeTier ? .green : .gray)
                    .font(.caption)
                
                Image(systemName: proTier ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundColor(proTier ? .green : .gray)
                    .font(.caption)
                
                Image(systemName: premiumTier ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundColor(premiumTier ? .green : .gray)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Subscription Plans View
struct SubscriptionPlansView: View {
    @ObservedObject var subscriptionService: SubscriptionService
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Choose Your Plan")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                ForEach(SubscriptionPlan.allPlans.filter { $0.tier != .free }, id: \.productId) { plan in
                    if let product = subscriptionService.getProduct(for: plan) {
                        LivePricingCard(
                            plan: plan,
                            product: product,
                            subscriptionService: subscriptionService
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Live Pricing Card
struct LivePricingCard: View {
    let plan: SubscriptionPlan
    let product: Product
    @ObservedObject var subscriptionService: SubscriptionService
    @State private var isPurchasing = false
    
    var body: some View {
                VStack(spacing: 16) {
            if plan.isPopular {
                Text("MOST POPULAR")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
            
            VStack(spacing: 8) {
                Text(plan.tier.displayName + " " + plan.period.displayName)
                        .font(.headline)
                    .fontWeight(.semibold)
                
                HStack(alignment: .bottom, spacing: 4) {
                    Text(product.displayPrice)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(plan.period.shortDisplayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let savings = plan.annualSavings {
                    Text(savings)
                        .font(.caption)
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                }
            }
                    
                    VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(plan.features.prefix(4)), id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        
                        Text(feature.displayName)
                            .font(.caption)
                        
                        Spacer()
                    }
                }
                
                if plan.features.count > 4 {
                    Text("+ \(plan.features.count - 4) more features")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Button(action: {
                Task {
                    isPurchasing = true
                    await subscriptionService.purchase(product)
                    isPurchasing = false
                }
            }) {
                HStack {
                    if isPurchasing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    
                    Text(subscriptionService.isProductPurchased(product) ? "Purchased" : "Subscribe")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(subscriptionService.isProductPurchased(product) ? Color.green : Color.accentColor)
                .cornerRadius(8)
            }
            .disabled(isPurchasing || subscriptionService.isProductPurchased(product))
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(plan.isPopular ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Static Pricing Card (Fallback)
struct StaticPricingCard: View {
    let plan: SubscriptionPlan
    let isRecommended: Bool
    
    init(plan: SubscriptionPlan, isRecommended: Bool = false) {
        self.plan = plan
        self.isRecommended = isRecommended || plan.isPopular
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if isRecommended {
                Text("MOST POPULAR")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
            
            VStack(spacing: 8) {
                Text(plan.tier.displayName + " " + plan.period.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                HStack(alignment: .bottom, spacing: 4) {
                    Text(plan.displayPrice)
                            .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(plan.period.shortDisplayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let savings = plan.annualSavings {
                    Text(savings)
                        .font(.caption)
                        .foregroundColor(.green)
                            .fontWeight(.semibold)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(plan.features.prefix(4)), id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        
                        Text(feature.displayName)
                            .font(.caption)
                        
                        Spacer()
                    }
                }
                
                if plan.features.count > 4 {
                    Text("+ \(plan.features.count - 4) more features")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Button(action: {
                // Handle subscription purchase - would open App Store
            }) {
                Text("Coming Soon")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray)
                    .cornerRadius(8)
            }
            .disabled(true)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isRecommended ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}

#Preview {
    SettingsView()
}
