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
    var subscriptionExpiry: Date?
    
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
        subscriptionTier: String = "free",
        subscriptionExpiry: Date? = nil
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.profileImageURL = profileImageURL
        self.createdAt = createdAt
        self.isEmailVerified = isEmailVerified
        self.subscriptionTier = subscriptionTier
        self.subscriptionExpiry = subscriptionExpiry
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