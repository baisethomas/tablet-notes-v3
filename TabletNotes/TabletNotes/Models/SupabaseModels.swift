import Foundation

// MARK: - Supabase Profile Model
struct SupabaseProfile: Codable {
    let id: UUID
    let email: String
    let name: String
    let profileImageUrl: String?
    let createdAt: Date
    let isEmailVerified: Bool
    let subscriptionTier: String
    let subscriptionStatus: String
    let subscriptionExpiry: Date?
    let subscriptionProductId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case profileImageUrl = "profile_image_url"
        case createdAt = "created_at"
        case isEmailVerified = "is_email_verified"
        case subscriptionTier = "subscription_tier"
        case subscriptionStatus = "subscription_status"
        case subscriptionExpiry = "subscription_expiry"
        case subscriptionProductId = "subscription_product_id"
    }

    // Convert to SwiftData User model
    func toUser() -> User {
        return User(
            id: id,
            email: email,
            name: name,
            profileImageURL: profileImageUrl,
            createdAt: createdAt,
            isEmailVerified: isEmailVerified,
            subscriptionTier: subscriptionTier,
            subscriptionStatus: subscriptionStatus,
            subscriptionExpiry: subscriptionExpiry,
            subscriptionProductId: subscriptionProductId
        )
    }
}

// MARK: - Supabase User Notification Settings Model
struct SupabaseUserNotificationSettings: Codable {
    let id: UUID
    let userId: UUID
    let transcriptionComplete: Bool
    let summaryComplete: Bool
    let syncErrors: Bool
    let weeklyDigest: Bool
    let productUpdates: Bool
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case transcriptionComplete = "transcription_complete"
        case summaryComplete = "summary_complete"
        case syncErrors = "sync_errors"
        case weeklyDigest = "weekly_digest"
        case productUpdates = "product_updates"
        case createdAt = "created_at"
    }
    
    // Convert to SwiftData UserNotificationSettings model
    func toUserNotificationSettings() -> UserNotificationSettings {
        return UserNotificationSettings(
            id: id,
            transcriptionComplete: transcriptionComplete,
            summaryComplete: summaryComplete,
            syncErrors: syncErrors,
            weeklyDigest: weeklyDigest,
            productUpdates: productUpdates
        )
    }
}

// MARK: - Supabase Insert/Update Models
struct SupabaseProfileInsert: Codable {
    let id: String
    let email: String
    let name: String
    let profileImageUrl: String?
    let createdAt: String
    let isEmailVerified: Bool
    let subscriptionTier: String
    let subscriptionExpiry: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case profileImageUrl = "profile_image_url"
        case createdAt = "created_at"
        case isEmailVerified = "is_email_verified"
        case subscriptionTier = "subscription_tier"
        case subscriptionExpiry = "subscription_expiry"
    }
}

// MARK: - Helper Extensions for User Model
extension User {
    // Convert to Supabase-compatible insert model
    func toSupabaseInsert() -> SupabaseProfileInsert {
        let formatter = ISO8601DateFormatter()
        
        return SupabaseProfileInsert(
            id: id.uuidString,
            email: email,
            name: name,
            profileImageUrl: profileImageURL,
            createdAt: formatter.string(from: createdAt),
            isEmailVerified: isEmailVerified,
            subscriptionTier: subscriptionTier,
            subscriptionExpiry: subscriptionExpiry.map { formatter.string(from: $0) }
        )
    }
}

// MARK: - Helper Extensions for UserNotificationSettings Model
extension UserNotificationSettings {
    // Convert to Supabase-compatible dictionary for insert/update
    func toSupabaseDict(userId: UUID) -> [String: Any] {
        return [
            "id": id.uuidString,
            "user_id": userId.uuidString,
            "transcription_complete": transcriptionComplete,
            "summary_complete": summaryComplete,
            "sync_errors": syncErrors,
            "weekly_digest": weeklyDigest,
            "product_updates": productUpdates
        ]
    }
}