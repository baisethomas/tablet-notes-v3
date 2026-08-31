import Foundation
import Testing
@testable import TabletNotes

/// Regression tests for TAB-108's client half: the device must never write
/// entitlement columns to `profiles`. Entitlements are server-derived from
/// the verified StoreKit transaction (verify-purchase.js, TAB-47); a client
/// that writes `subscription_*` is at best redundant and at worst the
/// premium-forging path. These tests pin the upsert payload's shape so the
/// server-side column revoke (TAB-108's migration) cannot break the auth
/// flow — and so no future field addition quietly reintroduces the write.
struct ProfileEntitlementWriteTests {

    private func payloadKeys() throws -> Set<String> {
        let user = User(
            id: UUID(),
            email: "entitlement@test.com",
            name: "Entitlement Test"
        )
        let data = try JSONEncoder().encode(user.toSupabaseInsert())
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return Set((object ?? [:]).keys)
    }

    @Test("the profile upsert carries no entitlement columns")
    func upsertOmitsSubscriptionColumns() throws {
        let keys = try payloadKeys()
        let entitlementColumns: Set<String> = [
            "subscription_tier",
            "subscription_status",
            "subscription_expiry",
            "subscription_product_id",
            "subscription_purchase_date",
            "subscription_renewal_date",
            "subscription_original_transaction_id"
        ]
        #expect(keys.isDisjoint(with: entitlementColumns),
                "client profile upsert must not write entitlement columns: \(keys.intersection(entitlementColumns))")
    }

    @Test("the profile upsert still carries the identity fields")
    func upsertKeepsIdentityFields() throws {
        let keys = try payloadKeys()
        #expect(keys.isSuperset(of: ["id", "email", "name"]))
    }
}
