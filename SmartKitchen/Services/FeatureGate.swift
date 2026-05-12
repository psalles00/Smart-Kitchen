import Foundation
import Observation

/// Soft + hard feature limits for free-tier users. Counters live in
/// `UserDefaults` (not SwiftData) so they're never sync'd via CloudKit and
/// can't accidentally corrupt the user database.
///
/// - **Soft gates** (counters): track usage in the current calendar day.
///   When the limit is hit, the caller should present `PaywallSheet`.
/// - **Hard gates**: properties that simply return `true`/`false` based on
///   the active subscription. They do NOT disable underlying iCloud / SwiftData
///   sync — those remain always-on. They only gate explicit user actions
///   (e.g. "compartilhar família", "exportar backup", LIGAR sync iCloud
///   pela primeira vez). Se sync já está ON, downgrade premium-expirado
///   nunca desliga; apenas o toggle ON inicial é gated.
///
/// IMPORTANT — NEVER use this gate to decide whether to *show* user data.
/// Locked-out users must still be able to read their full dataset. We only
/// limit the *creation* of new feature usage (a fresh AI request, a new
/// import, a manual backup export, etc.).
@MainActor
@Observable
final class FeatureGate {

    static let shared = FeatureGate()

    /// Soft (per-day) gates. Premium users are unlimited.
    enum Feature: String, CaseIterable {
        /// Conversational AI surfaces (Assistant chat, Recipe Ideas, etc.).
        case ai = "ai_requests"
        /// Recipe imports via URL, share extension, AI tool.
        case imports = "recipe_imports"
        /// Nutrition AI (food capture, label scan, parser).
        case nutritionAI = "nutrition_ai_requests"

        /// Daily limit for free-tier users.
        var freeLimit: Int {
            switch self {
            case .ai:           return 2
            case .imports:      return 3
            case .nutritionAI:  return 2
            }
        }

        var displayName: String {
            switch self {
            case .ai:          return String(localized: "IA")
            case .imports:     return String(localized: "Importações")
            case .nutritionAI: return String(localized: "IA Nutricional")
            }
        }
    }

    /// Hard (boolean) gates — features entirely unavailable on free tier.
    enum HardFeature: String, CaseIterable {
        case iCloudSync = "icloud_sync"
        case familyShare = "family_share"
        case externalBackup = "external_backup"

        var displayName: String {
            switch self {
            case .iCloudSync:      return String(localized: "Sincronização iCloud")
            case .familyShare:     return String(localized: "Compartilhamento Familiar")
            case .externalBackup:  return String(localized: "Backup")
            }
        }
    }

    /// Live entitlement source. Should be set once at app launch.
    var subscriptionManager: SubscriptionManager?

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Soft gates (per-day)

    /// Current usage count for today.
    func usage(of feature: Feature) -> Int {
        rolloverIfNeeded()
        return defaults.integer(forKey: counterKey(for: feature))
    }

    /// Returns true if the user can perform another action of this type.
    func canUse(_ feature: Feature) -> Bool {
        if isPremium { return true }
        return usage(of: feature) < feature.freeLimit
    }

    /// Increments the counter. Caller is expected to have checked `canUse`.
    /// On premium, this is a no-op (counters aren't tracked).
    func consume(_ feature: Feature) {
        guard !isPremium else { return }
        rolloverIfNeeded()
        let current = defaults.integer(forKey: counterKey(for: feature))
        defaults.set(current + 1, forKey: counterKey(for: feature))
    }

    /// Whether the counter pill should be visible (≥50% of limit). Com
    /// limites diários pequenos (2-3), aparece logo após o primeiro uso.
    func shouldShowCounter(_ feature: Feature) -> Bool {
        guard !isPremium else { return false }
        let used = usage(of: feature)
        return Double(used) / Double(feature.freeLimit) >= 0.5
    }

    /// Remaining uses today.
    func remaining(_ feature: Feature) -> Int {
        max(0, feature.freeLimit - usage(of: feature))
    }

    /// "X / Y" label for the counter pill.
    func counterLabel(_ feature: Feature) -> String {
        "\(usage(of: feature)) / \(feature.freeLimit)"
    }

    /// Localized "Hoje: X / Y" label.
    func counterLabelToday(_ feature: Feature) -> String {
        String(format: String(localized: "Hoje: %@"), counterLabel(feature))
    }

    /// Localized description of when the counter resets.
    var resetDescription: String {
        String(localized: "Renova à meia-noite")
    }

    // MARK: - Hard gates

    /// Tied to active StoreKit entitlement.
    ///
    /// DEBUG / Simulator override: when running in the iOS Simulator, the
    /// StoreKit "Sign in with Apple Account" prompt cannot be completed
    /// (pressing OK is a no-op), so `AppStore.sync()` never returns a valid
    /// transaction. To unblock manual testing of premium-gated features in
    /// the simulator, we treat the user as subscribed by default. Real
    /// devices and Release builds always go through StoreKit.
    var isPremium: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return subscriptionManager?.isSubscribed ?? false
        #endif
    }

    /// Generic hard-feature accessor.
    func canAccess(_ feature: HardFeature) -> Bool { isPremium }

    /// User can toggle iCloud sync ON in Settings UI. (Free tier sees a
    /// premium badge mas NUNCA pode desligar sync existente — sync é
    /// sempre preservado; este gate aplica-se apenas ao toggle ON inicial.)
    var canToggleICloudSync: Bool { isPremium }

    /// User can initiate CloudKit Share for collaborative pantry/list.
    var canShareWithFamily: Bool { isPremium }

    /// User can access premium backup actions in Settings.
    var canExportExternalBackup: Bool { isPremium }

    // MARK: - Daily rollover

    /// Last day identifier we observed (e.g. "2026-05-06").
    private var todayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: .now)
    }

    private static let dayDefaultsKey = "featureGate.lastDay"
    /// Legacy monthly key — kept so we can clean it up on first launch after
    /// the daily-rollover migration.
    private static let legacyMonthDefaultsKey = "featureGate.lastMonth"

    /// Resets all counters when the calendar day changes.
    private func rolloverIfNeeded() {
        // One-time migration cleanup: drop the legacy monthly marker e zera
        // contadores antigos para não carregar 5/mês para o novo 3/dia.
        if defaults.string(forKey: Self.legacyMonthDefaultsKey) != nil {
            defaults.removeObject(forKey: Self.legacyMonthDefaultsKey)
            for feature in Feature.allCases {
                defaults.removeObject(forKey: counterKey(for: feature))
            }
        }

        let stored = defaults.string(forKey: Self.dayDefaultsKey)
        let current = todayKey
        guard stored != current else { return }
        for feature in Feature.allCases {
            defaults.removeObject(forKey: counterKey(for: feature))
        }
        defaults.set(current, forKey: Self.dayDefaultsKey)
    }

    private func counterKey(for feature: Feature) -> String {
        "featureGate.\(feature.rawValue).count"
    }
}
