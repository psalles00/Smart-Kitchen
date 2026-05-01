import Foundation
import StoreKit
import Observation

/// Lightweight StoreKit 2 wrapper used by the onboarding paywall and by the
/// in-app subscription card. Holds the loaded `Product`s, the user's current
/// entitlement state, and exposes `purchase()` / `restore()` helpers.
///
/// IMPORTANT — DATA SAFETY:
/// This manager NEVER touches the SwiftData store, the iCloud capability,
/// or the model container. It only reads/writes the boolean
/// `AppSettings.isPremium` flag (added separately) — entitlement is never
/// the source of truth for whether the user can SEE their data; it only
/// gates new feature usage.
@MainActor
@Observable
final class SubscriptionManager {

    enum LoadState { case idle, loading, loaded, failed(String) }
    enum PurchaseState { case idle, purchasing, success, cancelled, failed(String) }

    /// Stable product identifiers. These must match what's in App Store
    /// Connect and the local `Configuration.storekit` file.
    static let annualProductID  = "com.pedrosalles.smartkitchen.sync.premium.annual"
    static let monthlyProductID = "com.pedrosalles.smartkitchen.sync.premium.monthly"

    /// Loaded products keyed by product identifier.
    private(set) var products: [String: Product] = [:]
    private(set) var loadState: LoadState = .idle
    private(set) var purchaseState: PurchaseState = .idle

    /// True if the user currently has a valid entitlement to either plan.
    private(set) var isSubscribed: Bool = false
    /// Identifier of the active product, if any.
    private(set) var activeProductID: String? = nil

    nonisolated(unsafe) private var updatesTask: Task<Void, Never>? = nil

    init() {
        // Listen for transactions that arrive outside of an explicit purchase
        // call (renewals, family-sharing changes, etc.).
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let tx) = update {
                    await self?.handle(transaction: tx)
                    await tx.finish()
                }
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Loading

    var annualProduct: Product? { products[Self.annualProductID] }
    var monthlyProduct: Product? { products[Self.monthlyProductID] }

    /// Loads the products from the store. Safe to call multiple times.
    func loadProducts() async {
        if case .loading = loadState { return }
        loadState = .loading
        do {
            let loaded = try await Product.products(for: [
                Self.annualProductID,
                Self.monthlyProductID
            ])
            var dict: [String: Product] = [:]
            for product in loaded { dict[product.id] = product }
            self.products = dict
            self.loadState = .loaded
            await refreshEntitlements()
        } catch {
            self.loadState = .failed(error.localizedDescription)
        }
    }

    /// Re-checks `Transaction.currentEntitlements` to update `isSubscribed`.
    func refreshEntitlements() async {
        var subscribed = false
        var activeID: String? = nil
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productType == .autoRenewable,
               tx.revocationDate == nil,
               (tx.expirationDate ?? .distantFuture) > .now {
                subscribed = true
                activeID = tx.productID
                break
            }
        }
        self.isSubscribed = subscribed
        self.activeProductID = activeID
    }

    // MARK: - Purchase / Restore

    /// Initiates a purchase. Returns `true` on a successful, verified buy.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await handle(transaction: tx)
                    await tx.finish()
                    purchaseState = .success
                    return true
                } else {
                    purchaseState = .failed("Transação não verificada")
                    return false
                }
            case .userCancelled:
                purchaseState = .cancelled
                return false
            case .pending:
                purchaseState = .idle
                return false
            @unknown default:
                purchaseState = .idle
                return false
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
            return false
        }
    }

    /// Restores prior purchases by syncing transactions and re-evaluating
    /// entitlements. Calling `AppStore.sync()` requires user authentication.
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            // Surfaced silently — `refreshEntitlements` still runs.
        }
        await refreshEntitlements()
    }

    // MARK: - Private

    private func handle(transaction: Transaction) async {
        await refreshEntitlements()
    }
}
