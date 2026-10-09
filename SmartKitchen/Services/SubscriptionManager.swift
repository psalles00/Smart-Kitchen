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
    // Brazil fallback for screen previews or while StoreKit is unavailable.
    // Loaded Product.displayPrice always remains the source for actual sales.
    static let annualFallbackPrice = "R$ 99,90"
    static let monthlyFallbackPrice = "R$ 49,90"

    /// Loaded products keyed by product identifier.
    private(set) var products: [String: Product] = [:]
    private(set) var loadState: LoadState = .idle
    private(set) var purchaseState: PurchaseState = .idle

    /// True if the user currently has a valid entitlement to either plan.
    private(set) var storeIsSubscribed: Bool = false
    var isSubscribed: Bool {
        #if DEBUG && os(iOS)
        if debugMode != .appStore { return debugMode == .premium }
        #endif
        return storeIsSubscribed
    }
    #if DEBUG && os(iOS)
    enum DebugMode: String, CaseIterable, Identifiable {
        case appStore, basic, premium
        var id: String { rawValue }
        var title: String {
            switch self {
            case .appStore: String(localized: "App Store")
            case .basic: String(localized: "Básico")
            case .premium: String(localized: "Premium")
            }
        }
    }
    private(set) var debugMode: DebugMode
    private let debugDefaults: UserDefaults
    private static let debugModeKey = "Savoria.debug.subscriptionMode"

    func setDebugMode(_ mode: DebugMode) {
        debugMode = mode
        debugDefaults.set(mode.rawValue, forKey: Self.debugModeKey)
        NotificationCenter.default.post(name: .subscriptionStateChanged, object: nil)
    }
    #endif
    /// Identifier of the active product, if any.
    private(set) var activeProductID: String? = nil
    /// Expiration date of the active subscription, if any.
    private(set) var expirationDate: Date? = nil
    /// True while a `restore()` call is in progress.
    private(set) var isRestoring: Bool = false
    /// Last restore feedback (humanised), nil until a restore happens.
    private(set) var lastRestoreMessage: String? = nil

    nonisolated(unsafe) private var updatesTask: Task<Void, Never>? = nil

    init(defaults: UserDefaults = .standard, observesTransactions: Bool = true) {
        #if DEBUG && os(iOS)
        debugDefaults = defaults
        debugMode = DebugMode(rawValue: defaults.string(forKey: Self.debugModeKey) ?? "") ?? .appStore
        #endif
        guard observesTransactions else { return }
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
        var expiry: Date? = nil
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productType == .autoRenewable,
               [Self.annualProductID, Self.monthlyProductID].contains(tx.productID),
               tx.revocationDate == nil,
               (tx.expirationDate ?? .distantFuture) > .now {
                subscribed = true
                activeID = tx.productID
                expiry = tx.expirationDate
                break
            }
        }
        let changed = (self.storeIsSubscribed != subscribed) || (self.activeProductID != activeID)
        self.storeIsSubscribed = subscribed
        self.activeProductID = activeID
        self.expirationDate = expiry
        if changed {
            NotificationCenter.default.post(name: .subscriptionStateChanged, object: nil)
        }
    }

    // MARK: - Purchase / Restore

    /// Initiates a purchase. Returns `true` on a successful, verified buy.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        #if DEBUG && os(iOS)
        guard debugMode == .appStore else {
            purchaseState = .failed(String(localized: "Volte ao modo App Store para realizar uma compra real."))
            return false
        }
        #endif
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
        isRestoring = true
        let wasSubscribed = storeIsSubscribed
        do {
            try await AppStore.sync()
        } catch {
            isRestoring = false
            lastRestoreMessage = String(localized: "Não foi possível restaurar agora. Tente novamente.")
            return
        }
        await refreshEntitlements()
        isRestoring = false
        if storeIsSubscribed && !wasSubscribed {
            lastRestoreMessage = String(localized: "Assinatura restaurada com sucesso.")
        } else if storeIsSubscribed {
            lastRestoreMessage = String(localized: "Sua assinatura já estava ativa.")
        } else {
            lastRestoreMessage = String(localized: "Nenhuma compra anterior encontrada.")
        }
    }

    // MARK: - Private

    private func handle(transaction: Transaction) async {
        await refreshEntitlements()
    }
}

extension Notification.Name {
    /// Posted whenever the user's subscription state transitions
    /// (subscribed ↔ not subscribed, plan switch).
    static let subscriptionStateChanged = Notification.Name("savoria.subscriptionStateChanged")
}
