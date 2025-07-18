import Foundation
import StoreKit

// MARK: - Subscription Tiers
enum SubscriptionTier: String, CaseIterable {
    case free = "free"
    case pro = "pro"
    case premium = "premium"
    
    var displayName: String {
        switch self {
        case .free:
            return "Free"
        case .pro:
            return "Pro"
        case .premium:
            return "Premium"
        }
    }
    
    var description: String {
        switch self {
        case .free:
            return "Basic features with limitations"
        case .pro:
            return "All features with cloud sync"
        case .premium:
            return "Everything in Pro plus priority support"
        }
    }
    
    var color: String {
        switch self {
        case .free:
            return "gray"
        case .pro:
            return "blue"
        case .premium:
            return "purple"
        }
    }
}

// MARK: - Subscription Features
enum SubscriptionFeature: String, CaseIterable {
    // Core Features
    case audioRecording = "audio_recording"
    case basicNotes = "basic_notes"
    case localStorage = "local_storage"
    
    // Pro Features
    case cloudSync = "cloud_sync"
    case unlimitedRecordings = "unlimited_recordings"
    case backgroundSync = "background_sync"
    case autoBackup = "auto_backup"
    case priorityTranscription = "priority_transcription"
    
    // Premium Features
    case prioritySupport = "priority_support"
    case advancedSummaries = "advanced_summaries"
    case customExports = "custom_exports"
    case teamSharing = "team_sharing"
    case bulkOperations = "bulk_operations"
    
    var displayName: String {
        switch self {
        case .audioRecording:
            return "Audio Recording"
        case .basicNotes:
            return "Basic Notes"
        case .localStorage:
            return "Local Storage"
        case .cloudSync:
            return "Cloud Sync"
        case .unlimitedRecordings:
            return "Unlimited Recordings"
        case .backgroundSync:
            return "Background Sync"
        case .autoBackup:
            return "Auto Backup"
        case .priorityTranscription:
            return "Priority Transcription"
        case .prioritySupport:
            return "Priority Support"
        case .advancedSummaries:
            return "Advanced AI Summaries"
        case .customExports:
            return "Custom Export Formats"
        case .teamSharing:
            return "Team Sharing"
        case .bulkOperations:
            return "Bulk Operations"
        }
    }
    
    var description: String {
        switch self {
        case .audioRecording:
            return "Record sermons and meetings"
        case .basicNotes:
            return "Take notes during recordings"
        case .localStorage:
            return "Store recordings on device"
        case .cloudSync:
            return "Sync across all your devices"
        case .unlimitedRecordings:
            return "No limit on number of recordings"
        case .backgroundSync:
            return "Sync automatically in background"
        case .autoBackup:
            return "Automatic cloud backup"
        case .priorityTranscription:
            return "Faster transcription processing"
        case .prioritySupport:
            return "Priority customer support"
        case .advancedSummaries:
            return "Detailed AI-powered summaries"
        case .customExports:
            return "Export in multiple formats"
        case .teamSharing:
            return "Share with team members"
        case .bulkOperations:
            return "Batch operations on recordings"
        }
    }
    
    var icon: String {
        switch self {
        case .audioRecording:
            return "mic.fill"
        case .basicNotes:
            return "note.text"
        case .localStorage:
            return "internaldrive"
        case .cloudSync:
            return "icloud"
        case .unlimitedRecordings:
            return "infinity"
        case .backgroundSync:
            return "arrow.triangle.2.circlepath"
        case .autoBackup:
            return "clock.arrow.circlepath"
        case .priorityTranscription:
            return "waveform.path.ecg"
        case .prioritySupport:
            return "person.fill.questionmark"
        case .advancedSummaries:
            return "brain.head.profile"
        case .customExports:
            return "square.and.arrow.up"
        case .teamSharing:
            return "person.2.fill"
        case .bulkOperations:
            return "rectangle.stack.fill"
        }
    }
}

// MARK: - Usage Limits
struct UsageLimits {
    let maxRecordings: Int?        // nil = unlimited
    let maxRecordingMinutes: Int?  // nil = unlimited
    let maxStorageGB: Double?      // nil = unlimited
    let maxNotesPerRecording: Int? // nil = unlimited
    let maxExportsPerMonth: Int?   // nil = unlimited
    
    static let free = UsageLimits(
        maxRecordings: 5,
        maxRecordingMinutes: 60,
        maxStorageGB: 1.0,
        maxNotesPerRecording: 20,
        maxExportsPerMonth: 3
    )
    
    static let pro = UsageLimits(
        maxRecordings: nil,
        maxRecordingMinutes: nil,
        maxStorageGB: nil,
        maxNotesPerRecording: nil,
        maxExportsPerMonth: nil
    )
    
    static let premium = UsageLimits(
        maxRecordings: nil,
        maxRecordingMinutes: nil,
        maxStorageGB: nil,
        maxNotesPerRecording: nil,
        maxExportsPerMonth: nil
    )
}

// MARK: - Subscription Plans
struct SubscriptionPlan {
    let tier: SubscriptionTier
    let productId: String
    let displayPrice: String
    let actualPrice: Decimal
    let period: SubscriptionPeriod
    let features: [SubscriptionFeature]
    let limits: UsageLimits
    let isPopular: Bool
    
    static let allPlans: [SubscriptionPlan] = [
        .free,
        .proMonthly,
        .proAnnual,
        .premiumMonthly,
        .premiumAnnual
    ]
    
    static let free = SubscriptionPlan(
        tier: .free,
        productId: "free",
        displayPrice: "Free",
        actualPrice: 0.00,
        period: .none,
        features: [
            .audioRecording,
            .basicNotes,
            .localStorage
        ],
        limits: .free,
        isPopular: false
    )
    
    static let proMonthly = SubscriptionPlan(
        tier: .pro,
        productId: "com.tabletnotes.pro.monthly",
        displayPrice: "$4.99",
        actualPrice: 4.99,
        period: .monthly,
        features: [
            .audioRecording,
            .basicNotes,
            .localStorage,
            .cloudSync,
            .unlimitedRecordings,
            .backgroundSync,
            .autoBackup,
            .priorityTranscription
        ],
        limits: .pro,
        isPopular: false
    )
    
    static let proAnnual = SubscriptionPlan(
        tier: .pro,
        productId: "com.tabletnotes.pro.annual",
        displayPrice: "$39.99",
        actualPrice: 39.99,
        period: .annual,
        features: [
            .audioRecording,
            .basicNotes,
            .localStorage,
            .cloudSync,
            .unlimitedRecordings,
            .backgroundSync,
            .autoBackup,
            .priorityTranscription
        ],
        limits: .pro,
        isPopular: true
    )
    
    static let premiumMonthly = SubscriptionPlan(
        tier: .premium,
        productId: "com.tabletnotes.premium.monthly",
        displayPrice: "$9.99",
        actualPrice: 9.99,
        period: .monthly,
        features: SubscriptionFeature.allCases,
        limits: .premium,
        isPopular: false
    )
    
    static let premiumAnnual = SubscriptionPlan(
        tier: .premium,
        productId: "com.tabletnotes.premium.annual",
        displayPrice: "$79.99",
        actualPrice: 79.99,
        period: .annual,
        features: SubscriptionFeature.allCases,
        limits: .premium,
        isPopular: false
    )
    
    var annualSavings: String? {
        guard period == .annual else { return nil }
        
        let monthlyEquivalent: Decimal
        switch tier {
        case .pro:
            monthlyEquivalent = SubscriptionPlan.proMonthly.actualPrice * 12
        case .premium:
            monthlyEquivalent = SubscriptionPlan.premiumMonthly.actualPrice * 12
        case .free:
            return nil
        }
        
        let savings = monthlyEquivalent - actualPrice
        let savingsPercentage = (savings / monthlyEquivalent) * 100
        
        return "\(Int(NSDecimalNumber(decimal: savingsPercentage).intValue))% off"
    }
}

// MARK: - Subscription Period
enum SubscriptionPeriod: String, CaseIterable {
    case none = "none"
    case monthly = "monthly"
    case annual = "annual"
    
    var displayName: String {
        switch self {
        case .none:
            return "One-time"
        case .monthly:
            return "Monthly"
        case .annual:
            return "Annual"
        }
    }
    
    var shortDisplayName: String {
        switch self {
        case .none:
            return ""
        case .monthly:
            return "/month"
        case .annual:
            return "/year"
        }
    }
}

// MARK: - Subscription Status
enum SubscriptionStatus: String {
    case active = "active"
    case expired = "expired"
    case cancelled = "cancelled"
    case pending = "pending"
    case failed = "failed"
    case free = "free"
    
    var displayName: String {
        switch self {
        case .active:
            return "Active"
        case .expired:
            return "Expired"
        case .cancelled:
            return "Cancelled"
        case .pending:
            return "Pending"
        case .failed:
            return "Failed"
        case .free:
            return "Free"
        }
    }
    
    var color: String {
        switch self {
        case .active:
            return "green"
        case .expired, .cancelled, .failed:
            return "red"
        case .pending:
            return "orange"
        case .free:
            return "gray"
        }
    }
}