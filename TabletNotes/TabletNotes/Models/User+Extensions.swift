import Foundation

// MARK: - User Extensions (Non-SwiftData)
extension User {
    var subscriptionTierEnum: SubscriptionTier {
        return SubscriptionTier(rawValue: subscriptionTier) ?? .free
    }
    
    var subscriptionStatusEnum: SubscriptionStatus {
        return SubscriptionStatus(rawValue: subscriptionStatus) ?? .free
    }
    
    var isPaidUser: Bool {
        print("[User] isPaidUser check - tier: \(subscriptionTier), tierEnum: \(subscriptionTierEnum), status: \(subscriptionStatus), statusEnum: \(subscriptionStatusEnum)")

        guard subscriptionTierEnum != .free else {
            print("[User] isPaidUser = false (tier is free)")
            return false
        }
        guard subscriptionStatusEnum == .active else {
            print("[User] isPaidUser = false (status is not active: \(subscriptionStatusEnum))")
            return false
        }

        // Check if subscription is still valid
        if let expiry = subscriptionExpiry {
            let isValid = Date() < expiry
            print("[User] isPaidUser = \(isValid) (expiry check: \(expiry))")
            return isValid
        }

        // If no expiry date, assume it's valid (for legacy users)
        print("[User] isPaidUser = true (no expiry, status is active)")
        return subscriptionStatusEnum == .active
    }
    
    var currentPlan: SubscriptionPlan {
        if isPaidUser {
            // First try to match by both tier and product ID
            if let productId = subscriptionProductId {
                if let exactMatch = SubscriptionPlan.allPlans.first(where: { 
                    $0.tier == subscriptionTierEnum && $0.productId == productId 
                }) {
                    return exactMatch
                }
            }
            
            // Fallback: match by tier only (for users with missing/invalid product IDs)
            // Prefer the popular/annual plan for each tier
            if let tierMatch = SubscriptionPlan.allPlans.first(where: { 
                $0.tier == subscriptionTierEnum && $0.isPopular 
            }) {
                return tierMatch
            }
            
            // Last resort: any plan with matching tier
            if let anyTierMatch = SubscriptionPlan.allPlans.first(where: { 
                $0.tier == subscriptionTierEnum 
            }) {
                return anyTierMatch
            }
        }
        return SubscriptionPlan.free
    }
    
    var usageLimits: UsageLimits {
        let limits = currentPlan.limits
        print("[User] Usage limits for \(email): tier=\(subscriptionTier), maxDuration=\(limits.maxRecordingDurationMinutes ?? -1) minutes")
        return limits
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
    
    // MARK: - Data Consistency
    
    /// Fixes subscription data inconsistencies by assigning appropriate product IDs
    /// Call this when a user has a valid subscription tier but missing product ID
    func fixSubscriptionDataInconsistency() {
        // MIGRATION: Convert legacy "pro" tier to "premium"
        if subscriptionTier == "pro" {
            print("[User] Migrating legacy 'pro' tier to 'premium' for user: \(email)")
            subscriptionTier = "premium"

            // Update product ID if it was a pro product ID
            if let productId = subscriptionProductId {
                if productId.contains("pro.monthly") {
                    subscriptionProductId = SubscriptionPlan.premiumMonthly.productId
                    print("[User] Migrated pro monthly to premium monthly product ID")
                } else if productId.contains("pro.annual") {
                    subscriptionProductId = SubscriptionPlan.premiumAnnual.productId
                    print("[User] Migrated pro annual to premium annual product ID")
                }
            }
        }

        // Only fix if user has a valid paid tier but missing product ID
        guard isPaidUser && subscriptionProductId == nil else { return }

        print("[User] Fixing subscription data inconsistency for user: \(email)")
        print("[User] Current tier: \(subscriptionTier), missing product ID")

        // Assign the popular (annual) product ID for the user's tier
        switch subscriptionTierEnum {
        case .premium:
            subscriptionProductId = SubscriptionPlan.premiumAnnual.productId
            print("[User] Assigned Premium Annual product ID: \(SubscriptionPlan.premiumAnnual.productId)")

        case .free:
            // Free users shouldn't have inconsistent data, but just in case
            subscriptionProductId = nil
            subscriptionTier = "free"
            subscriptionStatus = "free"
        }
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
    
    func canRecordForDuration(_ minutes: Int) -> Bool {
        guard let maxDuration = usageLimits.maxRecordingDurationMinutes else { return true }
        return minutes <= maxDuration
    }
    
    func maxRecordingDuration() -> Int? {
        return usageLimits.maxRecordingDurationMinutes
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