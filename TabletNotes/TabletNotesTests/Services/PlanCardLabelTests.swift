import Foundation
import Testing
@testable import TabletNotes

// TAB-112: the paywall's plan card read "Current Plan: Premium — Active until
// <date>" for a user on the 14-day trial, directly above the Subscribe
// buttons. The trial is tier premium / status active, so every "is paid"
// derived label lied. These tests pin the card's title and status per state.
struct PlanCardLabelTests {

    private func user(tier: String, status: String, expiry: Date?, productId: String?) -> User {
        User(
            email: "card@example.com",
            name: "Card",
            isEmailVerified: true,
            subscriptionTier: tier,
            subscriptionStatus: status,
            subscriptionExpiry: expiry,
            subscriptionProductId: productId
        )
    }

    private var inTwoWeeks: Date { Calendar.current.date(byAdding: .day, value: 14, to: Date())! }
    private var yesterday: Date { Calendar.current.date(byAdding: .day, value: -1, to: Date())! }

    private func medium(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    @Test func trialUserIsLabelledFreeTrialNotPremium() {
        let trial = user(tier: "premium", status: "active", expiry: inTwoWeeks, productId: nil)
        #expect(trial.currentPlanDisplayName == "Free Trial")
        #expect(trial.subscriptionDisplayStatus == "Trial ends \(medium(inTwoWeeks))")
        #expect(!trial.showsPaidPlanCheckmark)
        // Entitlements are untouched: the trial still unlocks sync.
        #expect(trial.canSync)
    }

    @Test func paidUserKeepsPremiumActiveUntil() {
        let paid = user(tier: "premium", status: "active", expiry: inTwoWeeks,
                        productId: "com.tabletnotes.premium.annual")
        #expect(paid.currentPlanDisplayName == "Premium")
        #expect(paid.subscriptionDisplayStatus == "Active until \(medium(inTwoWeeks))")
        #expect(paid.showsPaidPlanCheckmark)
    }

    @Test func freeUserUnchanged() {
        let free = user(tier: "free", status: "active", expiry: nil, productId: nil)
        #expect(free.currentPlanDisplayName == "Free")
        #expect(free.subscriptionDisplayStatus == "Free Plan")
        #expect(!free.showsPaidPlanCheckmark)
    }

    @Test func expiredTrialReadsTrialEnded() {
        let expired = user(tier: "premium", status: "active", expiry: yesterday, productId: nil)
        #expect(expired.currentPlanDisplayName == "Free")
        #expect(expired.subscriptionDisplayStatus == "Trial ended")
        #expect(!expired.showsPaidPlanCheckmark)
        #expect(!expired.canSync)
    }
}
