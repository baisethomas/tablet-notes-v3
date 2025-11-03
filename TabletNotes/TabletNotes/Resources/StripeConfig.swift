import Foundation

// MARK: - Stripe Configuration
// This file contains configuration for Stripe payment processing
// Used for backend subscription management and webhook handling

struct StripeConfig {
    // MARK: - Stripe API Keys

    // Stripe Publishable Key (safe to use in client-side code)
    // Test mode key - replace with live key for production
    static let publishableKey = "pk_test_51SPH8bLtURujYcqQFxTD3qzHLGTHDz57MejikyGRveOFQ2XAAZc8zrWjoYNEUDMi98M7mtPqZXpa8jQ7mHcdiEXF00uFwVqsyv"

    // IMPORTANT: Never put the secret key in client-side code!
    // The secret key should only be used in your backend/Netlify functions
    // Store secret key in Netlify environment variables: STRIPE_SECRET_KEY

    // MARK: - Product IDs

    // Stripe Product IDs (from Stripe Dashboard)
    static let premiumMonthlyProductId = "prod_TLzieewv6f0Qmi"
    static let premiumAnnualProductId = "prod_TLzkM04Ab0R8yG"

    // MARK: - Environment

    enum Environment {
        case test
        case live
    }

    static var currentEnvironment: Environment {
        return publishableKey.hasPrefix("pk_test_") ? .test : .live
    }

    // MARK: - Configuration Validation

    /// Validates that the Stripe configuration has been properly set up
    static func validateConfig() -> Bool {
        // Check if publishable key is configured
        guard !publishableKey.isEmpty,
              publishableKey.hasPrefix("pk_") else {
            print("❌ Stripe publishable key is not configured or invalid")
            return false
        }

        // Check if product IDs are configured
        guard !premiumMonthlyProductId.isEmpty,
              !premiumAnnualProductId.isEmpty,
              premiumMonthlyProductId.hasPrefix("prod_"),
              premiumAnnualProductId.hasPrefix("prod_") else {
            print("❌ Stripe product IDs are not configured or invalid")
            return false
        }

        let envStr = currentEnvironment == .test ? "TEST" : "LIVE"
        print("✅ Stripe configuration is valid (\(envStr) mode)")
        return true
    }

    /// Returns true if the configuration has been properly set up
    static var isConfigured: Bool {
        return validateConfig()
    }

    /// Returns true if running in test mode
    static var isTestMode: Bool {
        return currentEnvironment == .test
    }
}

// MARK: - Configuration Status
/*
 ⚠️ STRIPE CONFIG - ARCHIVED FOR FUTURE WEB USE

 This configuration is NOT currently used in the iOS app.
 The app uses Apple In-App Purchases (StoreKit) for subscriptions.

 Stripe Product IDs (for reference):
 - Premium Monthly: prod_TLzieewv6f0Qmi ($9.99/month)
 - Premium Annual: prod_TLzkM04Ab0R8yG ($79.99/year)

 Apple IAP Product IDs (currently used):
 - com.tabletnotes.premium.monthly ($9.99/month)
 - com.tabletnotes.premium.annual ($79.99/year)

 Future Use Cases:
 - Web-based subscription management portal
 - Alternative payment method for users outside iOS
 - Backend subscription validation via Stripe webhooks

 ⚠️ IMPORTANT:
 - iOS apps MUST use Apple IAP per App Store guidelines
 - Stripe can be used for web-based subscriptions only
 - Never use Stripe for in-app purchases on iOS
 */
