import Foundation
import SwiftUI

// MARK: - Settings Data Models
enum AudioQuality: String, CaseIterable {
    case high = "High"
    case medium = "Medium" 
    case low = "Low"
    
    var description: String {
        switch self {
        case .high: return "Best quality, larger files"
        case .medium: return "Balanced quality and size"
        case .low: return "Smaller files, lower quality"
        }
    }
}

enum TranscriptionProvider: String, CaseIterable {
    case assemblyAI = "AssemblyAI"
    case assemblyAILive = "AssemblyAI Live"
    case appleSpeech = "Apple Speech"
    
    var description: String {
        switch self {
        case .assemblyAI: return "Cloud-based, highly accurate"
        case .assemblyAILive: return "Real-time AI transcription (Pro/Premium)"
        case .appleSpeech: return "On-device, private"
        }
    }
    
    var requiresPremium: Bool {
        switch self {
        case .assemblyAILive: return true
        default: return false
        }
    }
}

enum AppTheme: String, CaseIterable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"
    
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

enum FontSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    case extraLarge = "Extra Large"
    
    var scale: CGFloat {
        switch self {
        case .small: return 0.85
        case .medium: return 1.0
        case .large: return 1.15
        case .extraLarge: return 1.3
        }
    }
}

enum AutoDeletePeriod: String, CaseIterable {
    case never = "Never"
    case oneWeek = "1 Week"
    case oneMonth = "1 Month"
    case threeMonths = "3 Months"
    case sixMonths = "6 Months"
    case oneYear = "1 Year"
    
    var days: Int? {
        switch self {
        case .never: return nil
        case .oneWeek: return 7
        case .oneMonth: return 30
        case .threeMonths: return 90
        case .sixMonths: return 180
        case .oneYear: return 365
        }
    }
}

// MARK: - Settings Service
class SettingsService: ObservableObject {
    static let shared = SettingsService()
    
    // MARK: - Recording Settings
    @Published var audioQuality: AudioQuality {
        didSet { UserDefaults.standard.set(audioQuality.rawValue, forKey: "audioQuality") }
    }
    
    @Published var autoTranscription: Bool {
        didSet { UserDefaults.standard.set(autoTranscription, forKey: "autoTranscription") }
    }
    
    @Published var defaultServiceType: String {
        didSet { UserDefaults.standard.set(defaultServiceType, forKey: "defaultServiceType") }
    }
    
    @Published var recordingFormat: String {
        didSet { UserDefaults.standard.set(recordingFormat, forKey: "recordingFormat") }
    }
    
    @Published var autoStopMinutes: Int {
        didSet { UserDefaults.standard.set(autoStopMinutes, forKey: "autoStopMinutes") }
    }
    
    // MARK: - Transcription Settings
    @Published var transcriptionProvider: TranscriptionProvider {
        didSet { UserDefaults.standard.set(transcriptionProvider.rawValue, forKey: "transcriptionProvider") }
    }
    
    @Published var transcriptionLanguage: String {
        didSet { UserDefaults.standard.set(transcriptionLanguage, forKey: "transcriptionLanguage") }
    }
    
    @Published var autoPunctuation: Bool {
        didSet { UserDefaults.standard.set(autoPunctuation, forKey: "autoPunctuation") }
    }
    
    @Published var speakerDetection: Bool {
        didSet { UserDefaults.standard.set(speakerDetection, forKey: "speakerDetection") }
    }
    
    // MARK: - Storage & Sync Settings
    @Published var maxLocalStorageGB: Double {
        didSet { UserDefaults.standard.set(maxLocalStorageGB, forKey: "maxLocalStorageGB") }
    }
    
    @Published var autoDeletePeriod: AutoDeletePeriod {
        didSet { UserDefaults.standard.set(autoDeletePeriod.rawValue, forKey: "autoDeletePeriod") }
    }
    
    @Published var cloudSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(cloudSyncEnabled, forKey: "cloudSyncEnabled") }
    }
    
    @Published var offlineMode: Bool {
        didSet { UserDefaults.standard.set(offlineMode, forKey: "offlineMode") }
    }
    
    // MARK: - Privacy Settings
    @Published var analyticsEnabled: Bool {
        didSet { UserDefaults.standard.set(analyticsEnabled, forKey: "analyticsEnabled") }
    }
    
    @Published var locationTagging: Bool {
        didSet { UserDefaults.standard.set(locationTagging, forKey: "locationTagging") }
    }
    
    @Published var dataSharingEnabled: Bool {
        didSet { UserDefaults.standard.set(dataSharingEnabled, forKey: "dataSharingEnabled") }
    }
    
    @Published var crashReportingEnabled: Bool {
        didSet { UserDefaults.standard.set(crashReportingEnabled, forKey: "crashReportingEnabled") }
    }
    
    // MARK: - Appearance Settings
    @Published var appTheme: AppTheme {
        didSet { UserDefaults.standard.set(appTheme.rawValue, forKey: "appTheme") }
    }
    
    @Published var fontSize: FontSize {
        didSet { UserDefaults.standard.set(fontSize.rawValue, forKey: "fontSize") }
    }
    
    @Published var reduceAnimations: Bool {
        didSet { UserDefaults.standard.set(reduceAnimations, forKey: "reduceAnimations") }
    }
    
    @Published var compactMode: Bool {
        didSet { UserDefaults.standard.set(compactMode, forKey: "compactMode") }
    }
    
    // MARK: - Export Settings
    @Published var defaultExportFormat: String {
        didSet { UserDefaults.standard.set(defaultExportFormat, forKey: "defaultExportFormat") }
    }
    
    @Published var includeAudioInExport: Bool {
        didSet { UserDefaults.standard.set(includeAudioInExport, forKey: "includeAudioInExport") }
    }
    
    @Published var autoBackupEnabled: Bool {
        didSet { UserDefaults.standard.set(autoBackupEnabled, forKey: "autoBackupEnabled") }
    }
    
    private init() {
        // Initialize with UserDefaults values or defaults
        self.audioQuality = AudioQuality(rawValue: UserDefaults.standard.string(forKey: "audioQuality") ?? "") ?? .high
        self.autoTranscription = UserDefaults.standard.object(forKey: "autoTranscription") as? Bool ?? true
        self.defaultServiceType = UserDefaults.standard.string(forKey: "defaultServiceType") ?? "Sermon"
        self.recordingFormat = UserDefaults.standard.string(forKey: "recordingFormat") ?? "M4A"
        self.autoStopMinutes = UserDefaults.standard.object(forKey: "autoStopMinutes") as? Int ?? 120
        
        self.transcriptionProvider = TranscriptionProvider(rawValue: UserDefaults.standard.string(forKey: "transcriptionProvider") ?? "") ?? .assemblyAILive
        self.transcriptionLanguage = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "en-US"
        self.autoPunctuation = UserDefaults.standard.object(forKey: "autoPunctuation") as? Bool ?? true
        self.speakerDetection = UserDefaults.standard.object(forKey: "speakerDetection") as? Bool ?? false
        
        self.maxLocalStorageGB = UserDefaults.standard.object(forKey: "maxLocalStorageGB") as? Double ?? 5.0
        self.autoDeletePeriod = AutoDeletePeriod(rawValue: UserDefaults.standard.string(forKey: "autoDeletePeriod") ?? "") ?? .threeMonths
        self.cloudSyncEnabled = UserDefaults.standard.object(forKey: "cloudSyncEnabled") as? Bool ?? true
        self.offlineMode = UserDefaults.standard.object(forKey: "offlineMode") as? Bool ?? false
        
        self.analyticsEnabled = UserDefaults.standard.object(forKey: "analyticsEnabled") as? Bool ?? true
        self.locationTagging = UserDefaults.standard.object(forKey: "locationTagging") as? Bool ?? false
        self.dataSharingEnabled = UserDefaults.standard.object(forKey: "dataSharingEnabled") as? Bool ?? false
        self.crashReportingEnabled = UserDefaults.standard.object(forKey: "crashReportingEnabled") as? Bool ?? true
        
        self.appTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? "") ?? .system
        self.fontSize = FontSize(rawValue: UserDefaults.standard.string(forKey: "fontSize") ?? "") ?? .medium
        self.reduceAnimations = UserDefaults.standard.object(forKey: "reduceAnimations") as? Bool ?? false
        self.compactMode = UserDefaults.standard.object(forKey: "compactMode") as? Bool ?? false
        
        self.defaultExportFormat = UserDefaults.standard.string(forKey: "defaultExportFormat") ?? "PDF"
        self.includeAudioInExport = UserDefaults.standard.object(forKey: "includeAudioInExport") as? Bool ?? false
        self.autoBackupEnabled = UserDefaults.standard.object(forKey: "autoBackupEnabled") as? Bool ?? false
    }
    
    // MARK: - Subscription-Aware Properties
    
    /// Returns the effective transcription provider based on user's subscription tier
    @MainActor var effectiveTranscriptionProvider: TranscriptionProvider {
        // Automatically determine the best transcription provider based on subscription tier
        guard let currentUser = AuthenticationManager.shared.currentUser else {
            return .appleSpeech
        }
        
        // Premium users get AssemblyAI Live (real-time transcription)
        if currentUser.subscriptionTier == "premium" {
            return .assemblyAILive
        }
        
        // Pro users get regular AssemblyAI (cloud-based, highly accurate)
        if currentUser.subscriptionTier == "pro" {
            return .assemblyAI
        }
        
        // Free/Basic users get Apple Speech
        return .appleSpeech
    }
    
    /// No longer needed - transcription provider is now automatically determined based on subscription tier
    @MainActor func validateTranscriptionProvider() {
        // Provider is now automatically determined by effectiveTranscriptionProvider
        // This method is kept for compatibility but no longer performs validation
        print("[SettingsService] Transcription provider is now automatically determined based on subscription tier")
        
        if let currentUser = AuthenticationManager.shared.currentUser {
            let provider = effectiveTranscriptionProvider
            print("[SettingsService] User tier: \(currentUser.subscriptionTier)")
            print("[SettingsService] User subscription product ID: \(currentUser.subscriptionProductId ?? "nil")")
            print("[SettingsService] User subscription tier enum: \(currentUser.subscriptionTierEnum)")
            print("[SettingsService] User current plan: \(currentUser.currentPlan.productId)")
            print("[SettingsService] Current plan features: \(currentUser.currentPlan.features.map { $0.rawValue })")
            print("[SettingsService] Can use priority transcription: \(currentUser.canUsePriorityTranscription)")
            print("[SettingsService] Auto-selected provider: \(provider.rawValue)")
        }
    }
    
    // MARK: - Data Consistency Methods
    
    /// Manually trigger subscription data consistency fix for the current user
    @MainActor func fixSubscriptionDataInconsistency() {
        guard let currentUser = AuthenticationManager.shared.currentUser else { 
            print("[SettingsService] No current user to fix")
            return 
        }
        
        print("[SettingsService] Manually fixing subscription data inconsistency")
        currentUser.fixSubscriptionDataInconsistency()
        
        // Re-validate transcription provider after fix
        validateTranscriptionProvider()
    }
    
    // MARK: - Helper Methods
    func resetToDefaults() {
        let defaults = UserDefaults.standard
        let keys = [
            "audioQuality", "autoTranscription", "defaultServiceType", "recordingFormat", "autoStopMinutes",
            "transcriptionProvider", "transcriptionLanguage", "autoPunctuation", "speakerDetection",
            "maxLocalStorageGB", "autoDeletePeriod", "cloudSyncEnabled", "offlineMode",
            "analyticsEnabled", "locationTagging", "dataSharingEnabled", "crashReportingEnabled",
            "appTheme", "fontSize", "reduceAnimations", "compactMode",
            "defaultExportFormat", "includeAudioInExport", "autoBackupEnabled"
        ]
        
        keys.forEach { defaults.removeObject(forKey: $0) }
        
        // Reinitialize with defaults
        audioQuality = .high
        autoTranscription = true
        defaultServiceType = "Sermon"
        recordingFormat = "M4A"
        autoStopMinutes = 120
        transcriptionProvider = .assemblyAILive
        transcriptionLanguage = "en-US"
        autoPunctuation = true
        speakerDetection = false
        maxLocalStorageGB = 5.0
        autoDeletePeriod = .threeMonths
        cloudSyncEnabled = true
        offlineMode = false
        analyticsEnabled = true
        locationTagging = false
        dataSharingEnabled = false
        crashReportingEnabled = true
        appTheme = .system
        fontSize = .medium
        reduceAnimations = false
        compactMode = false
        defaultExportFormat = "PDF"
        includeAudioInExport = false
        autoBackupEnabled = false
    }
    
    func exportSettings() -> [String: Any] {
        return [
            "audioQuality": audioQuality.rawValue,
            "autoTranscription": autoTranscription,
            "defaultServiceType": defaultServiceType,
            "recordingFormat": recordingFormat,
            "autoStopMinutes": autoStopMinutes,
            "transcriptionProvider": transcriptionProvider.rawValue,
            "transcriptionLanguage": transcriptionLanguage,
            "autoPunctuation": autoPunctuation,
            "speakerDetection": speakerDetection,
            "maxLocalStorageGB": maxLocalStorageGB,
            "autoDeletePeriod": autoDeletePeriod.rawValue,
            "cloudSyncEnabled": cloudSyncEnabled,
            "offlineMode": offlineMode,
            "analyticsEnabled": analyticsEnabled,
            "locationTagging": locationTagging,
            "dataSharingEnabled": dataSharingEnabled,
            "crashReportingEnabled": crashReportingEnabled,
            "appTheme": appTheme.rawValue,
            "fontSize": fontSize.rawValue,
            "reduceAnimations": reduceAnimations,
            "compactMode": compactMode,
            "defaultExportFormat": defaultExportFormat,
            "includeAudioInExport": includeAudioInExport,
            "autoBackupEnabled": autoBackupEnabled
        ]
    }
} 