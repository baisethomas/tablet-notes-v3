import Foundation
import Testing
@testable import TabletNotes

// TAB-111: App Review rejected v1.0 twice (Guideline 2.1(b), "cannot locate the
// In-App Purchases"). The reviewer signed in with Apple, which starts the 14-day
// trial; during the trial `isPaidUser`/`canSync` are true, so the Cloud Sync
// row's orange "Upgrade" caption — the app's only paywall entry — disappeared.
// These tests pin the always-visible subscription row's presentation: every
// entitlement state must produce a row with a call to action, and the trial
// state the reviewer lands in must lead to a Subscribe affordance.
struct SubscriptionEntryPointTests {

    @Test func freePlanOffersUpgrade() {
        let entry = SubscriptionTrialState.free.entryPoint
        #expect(entry.subtitle == "Free plan")
        #expect(entry.callToAction == "Upgrade")
    }

    @Test func activeTrialShowsDaysLeftAndOffersSubscribe() {
        let entry = SubscriptionTrialState.trialActive(daysLeft: 13).entryPoint
        #expect(entry.subtitle == "Free trial · 13 days left")
        #expect(entry.callToAction == "Subscribe")
    }

    @Test func expiringTrialOffersSubscribe() {
        let plural = SubscriptionTrialState.trialExpiringSoon(daysLeft: 2).entryPoint
        #expect(plural.subtitle == "Free trial · 2 days left")
        #expect(plural.callToAction == "Subscribe")

        let singular = SubscriptionTrialState.trialExpiringSoon(daysLeft: 1).entryPoint
        #expect(singular.subtitle == "Free trial · 1 day left")
    }

    @Test func expiredTrialOffersUpgrade() {
        let entry = SubscriptionTrialState.trialExpired.entryPoint
        #expect(entry.subtitle == "Trial expired")
        #expect(entry.callToAction == "Upgrade")
    }

    @Test func paidPlanOffersManage() {
        let entry = SubscriptionTrialState.paidActive.entryPoint
        #expect(entry.subtitle == "Premium active")
        #expect(entry.callToAction == "Manage")
    }

    /// The exact profile App Review lands on: a fresh Sign in with Apple account
    /// that the signup trigger put on a 14-day trial (premium/active/expiry
    /// +14d, no product id). Before TAB-111 this user saw no paywall entry at
    /// all. The row must exist and must invite a purchase.
    @Test func freshTrialAccountIsOfferedSubscribe() {
        let reviewer = User(
            email: "john.apple@privaterelay.appleid.com",
            name: "John Apple",
            isEmailVerified: true,
            subscriptionTier: "premium",
            subscriptionStatus: "active",
            subscriptionExpiry: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
            subscriptionProductId: nil
        )

        guard case .trialActive(let daysLeft) = reviewer.trialState else {
            Issue.record("expected an active trial, got \(reviewer.trialState)")
            return
        }
        #expect((13...14).contains(daysLeft))
        #expect(reviewer.trialState.entryPoint.callToAction == "Subscribe")
        // The trial legitimately unlocks sync; the fix must not touch that.
        #expect(reviewer.canSync)
    }

    /// The demo account (testuser@tabletnotes.io) after its trial was reset to
    /// the free tier: still gets a row, with Upgrade.
    @Test func freeTierAccountIsOfferedUpgrade() {
        let demo = User(
            email: "testuser@tabletnotes.io",
            name: "Test user",
            isEmailVerified: true,
            subscriptionTier: "free",
            subscriptionStatus: "active",
            subscriptionExpiry: nil,
            subscriptionProductId: nil
        )
        #expect(demo.trialState == .free)
        #expect(demo.trialState.entryPoint.callToAction == "Upgrade")
        #expect(!demo.canSync)
    }
}
