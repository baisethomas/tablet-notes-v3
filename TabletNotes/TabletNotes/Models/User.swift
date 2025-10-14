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
    var subscriptionTier: String // "free", "premium"
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
        subscriptionTier: String = "premium",
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
    case sessionExpired
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
        case .sessionExpired:
            return "Your session has expired. Please sign in again"
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
        case .sessionExpired:
            return "Please sign in again to continue"
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