import Foundation
import StoreKit
import Combine

@MainActor
protocol SubscriptionServiceProtocol: ObservableObject {
    var availableProducts: [Product] { get }
    var purchasedProducts: [Product] { get }
    var subscriptionStatus: SubscriptionStatus { get }
    var currentTier: SubscriptionTier { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }
    
    func loadProducts() async
    func purchase(_ product: Product) async -> Bool
    func restorePurchases() async -> Bool
    
    func getProduct(for plan: SubscriptionPlan) -> Product?
    func isProductPurchased(_ product: Product) -> Bool
    func hasActiveSubscription() -> Bool
    func getFormattedPrice(for product: Product) -> String
    func getSubscriptionPeriod(for product: Product) -> String
    
    func incrementRecordingCount()
    func incrementRecordingMinutes(_ minutes: Int)
    func incrementStorageUsage(_ gigabytes: Double)
    func incrementExportCount()
}