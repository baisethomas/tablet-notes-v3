import Foundation
import StoreKit
import Combine

@MainActor
class SubscriptionService: ObservableObject, SubscriptionServiceProtocol {
    
    // MARK: - Published Properties
    
    @Published private(set) var availableProducts: [Product] = []
    @Published private(set) var purchasedProducts: [Product] = []
    @Published private(set) var subscriptionStatus: SubscriptionStatus = .free
    @Published private(set) var currentTier: SubscriptionTier = .free
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let authManager: AuthenticationManager
    private let supabaseService: SupabaseServiceProtocol
    private var updateListenerTask: Task<Void, Error>?
    private var cancellables = Set<AnyCancellable>()
    
    // Product IDs for StoreKit (must match App Store Connect)
    private let productIds: Set<String> = [
        "com.tabletnotes.premium.monthly",
        "com.tabletnotes.premium.annual"
    ]
    
    // MARK: - Initialization
    
    init(authManager: AuthenticationManager, supabaseService: SupabaseServiceProtocol) {
        self.authManager = authManager
        self.supabaseService = supabaseService
        
        setupObservers()
        startListeningForTransactions()
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Listen for auth state changes
        authManager.$authStatePublished
            .sink { [weak self] authState in
                Task { @MainActor in
                    await self?.handleAuthStateChange(authState)
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleAuthStateChange(_ authState: AuthState) async {
        switch authState {
        case .authenticated(let user):
            await loadUserSubscriptionStatus(user)
            await loadProducts()
        case .unauthenticated:
            reset()
        default:
            break
        }
    }
    
    private func reset() {
        availableProducts = []
        purchasedProducts = []
        subscriptionStatus = .free
        currentTier = .free
        errorMessage = nil
    }
    
    // MARK: - Product Loading
    
    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let products = try await Product.products(for: productIds)
            
            // Sort products by price (ascending)
            availableProducts = products.sorted { product1, product2 in
                product1.price < product2.price
            }
            
            await loadPurchasedProducts()
            
        } catch {
            errorMessage = "Failed to load subscription options: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func loadPurchasedProducts() async {
        var purchased: [Product] = []
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try await checkVerified(result)
                
                if let product = availableProducts.first(where: { $0.id == transaction.productID }) {
                    purchased.append(product)
                }
            } catch {
                print("Failed to verify transaction: \(error)")
            }
        }
        
        purchasedProducts = purchased
        await updateSubscriptionStatus()
    }
    
    // MARK: - Purchase Flow
    
    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try await checkVerified(verification)
                
                // Update user subscription in database
                await updateUserSubscription(for: transaction, product: product)
                
                // Finish the transaction
                await transaction.finish()
                
                // Reload purchased products
                await loadPurchasedProducts()
                
                isLoading = false
                return true
                
            case .userCancelled:
                errorMessage = "Purchase cancelled"
                isLoading = false
                return false
                
            case .pending:
                errorMessage = "Purchase is pending approval"
                isLoading = false
                return false
                
            @unknown default:
                errorMessage = "Unknown purchase result"
                isLoading = false
                return false
            }
            
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }
    
    // MARK: - Restore Purchases
    
    func restorePurchases() async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            try await AppStore.sync()
            await loadPurchasedProducts()
            
            if purchasedProducts.isEmpty {
                errorMessage = "No previous purchases found"
                isLoading = false
                return false
            } else {
                isLoading = false
                return true
            }
            
        } catch {
            errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }
    
    // MARK: - Transaction Monitoring
    
    private func startListeningForTransactions() {
        updateListenerTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                do {
                    let transaction = try await self?.checkVerified(result)
                    
                    await MainActor.run { [weak self] in
                        Task {
                            await self?.handleTransaction(transaction)
                        }
                    }
                } catch {
                    print("Transaction verification failed: \(error)")
                }
            }
        }
    }
    
    private func handleTransaction(_ transaction: Transaction?) async {
        guard let transaction = transaction else { return }
        
        // Find the product for this transaction
        if let product = availableProducts.first(where: { $0.id == transaction.productID }) {
            await updateUserSubscription(for: transaction, product: product)
        }
        
        await loadPurchasedProducts()
        await transaction.finish()
    }
    
    // MARK: - Subscription Status Management
    
    private func loadUserSubscriptionStatus(_ user: User) async {
        currentTier = user.subscriptionTierEnum
        subscriptionStatus = user.subscriptionStatusEnum
    }
    
    private func updateSubscriptionStatus() async {
        guard let user = authManager.currentUser else { return }
        
        // Check if any purchased products are still active
        var activeSubscription: Product?
        var latestExpiry: Date?
        
        for product in purchasedProducts {
            if let subscription = product.subscription {
                for await result in Transaction.currentEntitlements {
                    do {
                        let transaction = try await checkVerified(result)
                        
                        if transaction.productID == product.id {
                            // Check if subscription is still valid
                            if let expirationDate = transaction.expirationDate,
                               expirationDate > Date() {
                                activeSubscription = product
                                
                                if latestExpiry == nil || expirationDate > latestExpiry! {
                                    latestExpiry = expirationDate
                                }
                            }
                        }
                    } catch {
                        print("Failed to verify entitlement: \(error)")
                    }
                }
            }
        }
        
        // Update status based on active subscriptions
        if let activeProduct = activeSubscription {
            if let plan = SubscriptionPlan.allPlans.first(where: { $0.productId == activeProduct.id }) {
                currentTier = plan.tier
                subscriptionStatus = .active
            }
        } else {
            currentTier = .free
            subscriptionStatus = .free
        }
    }
    
    private func updateUserSubscription(for transaction: Transaction, product: Product) async {
        guard let user = authManager.currentUser else { return }
        
        // Find the subscription plan
        guard let plan = SubscriptionPlan.allPlans.first(where: { $0.productId == product.id }) else {
            return
        }
        
        // Update user subscription details
        user.subscriptionTier = plan.tier.rawValue
        user.subscriptionStatus = SubscriptionStatus.active.rawValue
        user.subscriptionProductId = product.id
        user.subscriptionPurchaseDate = transaction.purchaseDate
        user.subscriptionExpiry = transaction.expirationDate
        user.subscriptionRenewalDate = transaction.expirationDate
        
        // Reset monthly usage if upgrading from free
        if user.shouldResetMonthlyUsage() {
            user.resetMonthlyUsage()
        }
        
        // Update in database
        do {
            try await supabaseService.updateUserProfile(user)
        } catch {
            print("Failed to update user subscription in database: \(error)")
        }
        
        // Update local state
        currentTier = plan.tier
        subscriptionStatus = .active
    }
    
    // MARK: - Helper Methods
    
    private func checkVerified<T>(_ result: VerificationResult<T>) async throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.unverifiedTransaction
        case .verified(let safe):
            return safe
        }
    }
    
    // MARK: - Public Utility Methods
    
    func getProduct(for plan: SubscriptionPlan) -> Product? {
        return availableProducts.first { $0.id == plan.productId }
    }
    
    func isProductPurchased(_ product: Product) -> Bool {
        return purchasedProducts.contains { $0.id == product.id }
    }
    
    func hasActiveSubscription() -> Bool {
        return subscriptionStatus == .active && currentTier != .free
    }
    
    func getFormattedPrice(for product: Product) -> String {
        return product.displayPrice
    }
    
    func getSubscriptionPeriod(for product: Product) -> String {
        guard let subscription = product.subscription else { return "" }
        
        let period = subscription.subscriptionPeriod
        let unit = period.unit
        let value = period.value
        
        switch unit {
        case .day:
            return value == 1 ? "Daily" : "\(value) days"
        case .week:
            return value == 1 ? "Weekly" : "\(value) weeks"
        case .month:
            return value == 1 ? "Monthly" : "\(value) months"
        case .year:
            return value == 1 ? "Annual" : "\(value) years"
        @unknown default:
            return "Unknown"
        }
    }
    
    // MARK: - Usage Tracking
    
    func incrementRecordingCount() {
        guard let user = authManager.currentUser else { return }
        
        if user.shouldResetMonthlyUsage() {
            user.resetMonthlyUsage()
        }
        
        user.monthlyRecordingCount += 1
        
        // Update in database
        Task {
            try? await supabaseService.updateUserProfile(user)
        }
    }
    
    func incrementRecordingMinutes(_ minutes: Int) {
        guard let user = authManager.currentUser else { return }
        
        if user.shouldResetMonthlyUsage() {
            user.resetMonthlyUsage()
        }
        
        user.monthlyRecordingMinutes += minutes
        
        // Update in database
        Task {
            try? await supabaseService.updateUserProfile(user)
        }
    }
    
    func incrementStorageUsage(_ gigabytes: Double) {
        guard let user = authManager.currentUser else { return }
        
        user.currentStorageUsedGB += gigabytes
        
        // Update in database
        Task {
            try? await supabaseService.updateUserProfile(user)
        }
    }
    
    func incrementExportCount() {
        guard let user = authManager.currentUser else { return }
        
        if user.shouldResetMonthlyUsage() {
            user.resetMonthlyUsage()
        }
        
        user.monthlyExportCount += 1
        
        // Update in database
        Task {
            try? await supabaseService.updateUserProfile(user)
        }
    }
}

// MARK: - Subscription Errors

enum SubscriptionError: LocalizedError {
    case unverifiedTransaction
    case productNotFound
    case purchaseFailed
    case restoreFailed
    
    var errorDescription: String? {
        switch self {
        case .unverifiedTransaction:
            return "Transaction could not be verified"
        case .productNotFound:
            return "Subscription product not found"
        case .purchaseFailed:
            return "Purchase failed"
        case .restoreFailed:
            return "Failed to restore purchases"
        }
    }
}