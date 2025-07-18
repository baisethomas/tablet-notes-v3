import Foundation
import SwiftData

@Model
final class User {
    @Attribute(.unique) var id: UUID
    var email: String
    var name: String
    var profileImageURL: String?
    var createdAt: Date
    var isEmailVerified: Bool
    var subscriptionTier: String // "free", "pro", "premium"
    var subscriptionStatus: String // "active", "expired", "cancelled", "pending", "failed", "free"
    var subscriptionExpiry: Date?
    var subscriptionProductId: String? // StoreKit product ID
    var subscriptionPurchaseDate: Date?
    var subscriptionRenewalDate: Date?
    
    // Usage tracking for limits
    var monthlyRecordingCount: Int = 0
    var monthlyRecordingMinutes: Int = 0
    var currentStorageUsedGB: Double = 0.0
    var monthlyExportCount: Int = 0
    var lastUsageResetDate: Date?
    
    // User preferences
    var notificationSettings: UserNotificationSettings?
    
    // User's sermons relationship
    @Relationship(deleteRule: .cascade) var sermons: [Sermon] = []
    
    init(
        id: UUID = UUID(),
        email: String,
        name: String,
        profileImageURL: String? = nil,
        createdAt: Date = Date(),
        isEmailVerified: Bool = false,
        subscriptionTier: String = "pro",
        subscriptionStatus: String = "active",
        subscriptionExpiry: Date? = Calendar.current.date(byAdding: .day, value: 14, to: Date()),
        subscriptionProductId: String? = nil,
        subscriptionPurchaseDate: Date? = nil,
        subscriptionRenewalDate: Date? = nil,
        monthlyRecordingCount: Int = 0,
        monthlyRecordingMinutes: Int = 0,
        currentStorageUsedGB: Double = 0.0,
        monthlyExportCount: Int = 0,
        lastUsageResetDate: Date? = nil
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.profileImageURL = profileImageURL
        self.createdAt = createdAt
        self.isEmailVerified = isEmailVerified
        self.subscriptionTier = subscriptionTier
        self.subscriptionStatus = subscriptionStatus
        self.subscriptionExpiry = subscriptionExpiry
        self.subscriptionProductId = subscriptionProductId
        self.subscriptionPurchaseDate = subscriptionPurchaseDate
        self.subscriptionRenewalDate = subscriptionRenewalDate
        self.monthlyRecordingCount = monthlyRecordingCount
        self.monthlyRecordingMinutes = monthlyRecordingMinutes
        self.currentStorageUsedGB = currentStorageUsedGB
        self.monthlyExportCount = monthlyExportCount
        self.lastUsageResetDate = lastUsageResetDate
    }
}

// MARK: - User Notification Settings
@Model
final class UserNotificationSettings {
    @Attribute(.unique) var id: UUID
    var transcriptionComplete: Bool
    var summaryComplete: Bool
    var syncErrors: Bool
    var weeklyDigest: Bool
    var productUpdates: Bool
    
    init(
        id: UUID = UUID(),
        transcriptionComplete: Bool = true,
        summaryComplete: Bool = true,
        syncErrors: Bool = true,
        weeklyDigest: Bool = false,
        productUpdates: Bool = false
    ) {
        self.id = id
        self.transcriptionComplete = transcriptionComplete
        self.summaryComplete = summaryComplete
        self.syncErrors = syncErrors
        self.weeklyDigest = weeklyDigest
        self.productUpdates = productUpdates
    }
}

// MARK: - Authentication State
enum AuthState: Equatable {
    case loading
    case authenticated(User)
    case unauthenticated
    case error(AuthError)
    
    static func == (lhs: AuthState, rhs: AuthState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading):
            return true
        case (.authenticated(let user1), .authenticated(let user2)):
            return user1.id == user2.id
        case (.unauthenticated, .unauthenticated):
            return true
        case (.error(let error1), .error(let error2)):
            return error1 == error2
        default:
            return false
        }
    }
}

// MARK: - Authentication Errors
enum AuthError: LocalizedError, Equatable {
    case invalidCredentials
    case networkError
    case userNotFound
    case emailAlreadyExists
    case weakPassword
    case emailNotVerified
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError:
            return "Network connection error"
        case .userNotFound:
            return "User account not found"
        case .emailAlreadyExists:
            return "An account with this email already exists"
        case .weakPassword:
            return "Password must be at least 8 characters"
        case .emailNotVerified:
            return "Please verify your email before signing in"
        case .unknownError(let message):
            return message
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidCredentials:
            return "Please check your email and password and try again"
        case .networkError:
            return "Please check your internet connection"
        case .userNotFound:
            return "Create an account or check your email address"
        case .emailAlreadyExists:
            return "Try signing in instead or use a different email"
        case .weakPassword:
            return "Use a stronger password with letters, numbers, and symbols"
        case .emailNotVerified:
            return "Check your email for a verification link"
        case .unknownError:
            return "Please try again or contact support"
        }
    }
}

// MARK: - Sign Up Data
struct SignUpData {
    let email: String
    let password: String
    let name: String
    
    var isValid: Bool {
        return !email.isEmpty && 
               !password.isEmpty && 
               !name.isEmpty &&
               email.contains("@") &&
               password.count >= 8
    }
    
    var validationError: AuthError? {
        if email.isEmpty || !email.contains("@") {
            return .invalidCredentials
        }
        if password.count < 8 {
            return .weakPassword
        }
        if name.isEmpty {
            return .invalidCredentials
        }
        return nil
    }
}

// MARK: - Subscription Extensions
extension User {
    var subscriptionTierEnum: SubscriptionTier {
        return SubscriptionTier(rawValue: subscriptionTier) ?? .free
    }
    
    var subscriptionStatusEnum: SubscriptionStatus {
        return SubscriptionStatus(rawValue: subscriptionStatus) ?? .free
    }
    
    var isPaidUser: Bool {
        guard subscriptionTierEnum != .free else { return false }
        guard subscriptionStatusEnum == .active else { return false }
        
        // Check if subscription is still valid
        if let expiry = subscriptionExpiry {
            return Date() < expiry
        }
        
        // If no expiry date, assume it's valid (for legacy users)
        return subscriptionStatusEnum == .active
    }
    
    var currentPlan: SubscriptionPlan {
        if isPaidUser {
            return SubscriptionPlan.allPlans.first { plan in
                plan.tier == subscriptionTierEnum && plan.productId == (subscriptionProductId ?? "")
            } ?? SubscriptionPlan.free
        }
        return SubscriptionPlan.free
    }
    
    var usageLimits: UsageLimits {
        return currentPlan.limits
    }
    
    // MARK: - Feature Access
    
    func hasFeature(_ feature: SubscriptionFeature) -> Bool {
        return currentPlan.features.contains(feature)
    }
    
    var canSync: Bool {
        return hasFeature(.cloudSync)
    }
    
    var canCreateUnlimitedRecordings: Bool {
        return hasFeature(.unlimitedRecordings)
    }
    
    var canUseBackgroundSync: Bool {
        return hasFeature(.backgroundSync)
    }
    
    var canUseAutoBackup: Bool {
        return hasFeature(.autoBackup)
    }
    
    var canUsePriorityTranscription: Bool {
        return hasFeature(.priorityTranscription)
    }
    
    var canUseAdvancedSummaries: Bool {
        return hasFeature(.advancedSummaries)
    }
    
    var canUseCustomExports: Bool {
        return hasFeature(.customExports)
    }
    
    var canUseTeamSharing: Bool {
        return hasFeature(.teamSharing)
    }
    
    var canUseBulkOperations: Bool {
        return hasFeature(.bulkOperations)
    }
    
    // MARK: - Usage Tracking
    
    func canCreateNewRecording() -> Bool {
        guard let maxRecordings = usageLimits.maxRecordings else { return true }
        return monthlyRecordingCount < maxRecordings
    }
    
    func canRecordForMinutes(_ minutes: Int) -> Bool {
        guard let maxMinutes = usageLimits.maxRecordingMinutes else { return true }
        return monthlyRecordingMinutes + minutes <= maxMinutes
    }
    
    func canUseStorageGB(_ additionalGB: Double) -> Bool {
        guard let maxStorage = usageLimits.maxStorageGB else { return true }
        return currentStorageUsedGB + additionalGB <= maxStorage
    }
    
    func canExportThisMonth() -> Bool {
        guard let maxExports = usageLimits.maxExportsPerMonth else { return true }
        return monthlyExportCount < maxExports
    }
    
    func remainingRecordings() -> Int? {
        guard let maxRecordings = usageLimits.maxRecordings else { return nil }
        return max(0, maxRecordings - monthlyRecordingCount)
    }
    
    func remainingRecordingMinutes() -> Int? {
        guard let maxMinutes = usageLimits.maxRecordingMinutes else { return nil }
        return max(0, maxMinutes - monthlyRecordingMinutes)
    }
    
    func remainingStorageGB() -> Double? {
        guard let maxStorage = usageLimits.maxStorageGB else { return nil }
        return max(0, maxStorage - currentStorageUsedGB)
    }
    
    func remainingExports() -> Int? {
        guard let maxExports = usageLimits.maxExportsPerMonth else { return nil }
        return max(0, maxExports - monthlyExportCount)
    }
    
    // MARK: - Usage Reset
    
    func shouldResetMonthlyUsage() -> Bool {
        guard let lastReset = lastUsageResetDate else { return true }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Reset if it's been more than a month
        return !calendar.isDate(lastReset, equalTo: now, toGranularity: .month)
    }
    
    func resetMonthlyUsage() {
        monthlyRecordingCount = 0
        monthlyRecordingMinutes = 0
        monthlyExportCount = 0
        lastUsageResetDate = Date()
    }
    
    // MARK: - Subscription Status
    
    var subscriptionDisplayStatus: String {
        if isPaidUser {
            if let expiry = subscriptionExpiry {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return "Active until \(formatter.string(from: expiry))"
            }
            return "Active"
        }
        return "Free Plan"
    }
    
    var isSubscriptionExpiringSoon: Bool {
        guard let expiry = subscriptionExpiry else { return false }
        
        let calendar = Calendar.current
        let sevenDaysFromNow = calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        
        return expiry <= sevenDaysFromNow
    }
}