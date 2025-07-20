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