import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsService.shared
    @State private var showingResetAlert = false
    @State private var showingAbout = false
    
    var onNext: (() -> Void)?
    var onShowOnboarding: (() -> Void)?
    var onNavigateToAccount: (() -> Void)?
    
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
                            
                            SettingsToggle(
                                icon: "icloud",
                                title: "Cloud Sync",
                                subtitle: "Sync recordings and notes to iCloud",
                                isOn: $settings.cloudSyncEnabled
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

#Preview {
    SettingsView()
}
