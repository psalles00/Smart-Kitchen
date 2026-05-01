import Foundation
import Observation

/// Soft + hard feature limits for free-tier users. Counters live in
/// `UserDefaults` (not SwiftData) so they're never sync'd via CloudKit and
/// can't accidentally corrupt the user database.
///
/// - **Soft gates** (counters): track usage in the current calendar month.
///   When the limit is hit, the caller should present `PaywallSheet`.
/// - **Hard gates**: properties that simply return `true`/`false` based on
///   the active subscription. They do NOT disable underlying iCloud / SwiftData
///   sync — those remain always-on. They only gate explicit user actions
///   (e.g. "compartilhar família", "exportar backup").
///
/// IMPORTANT — NEVER use this gate to decide whether to *show* user data.
/// Locked-out users must still be able to read their full dataset. We only
/// limit the *creation* of new feature usage (a fresh AI request, a new
/// import, a manual backup export, etc.).
@MainActor
@Observable
final class FeatureGate {

    static let shared = FeatureGate()

    enum Feature: String, CaseIterable {
        case ai = "ai_requests"
        case imports = "recipe_imports"
        case nutritionAI = "nutrition_ai_requests"

        /// Monthly limit for free-tier users.
        var freeLimit: Int {
            switch self {
            case .ai:           return 10
            case .imports:      return 5
            case .nutritionAI:  return 10
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

    /// Live entitlement source. Should be set once at app launch.
    var subscriptionManager: SubscriptionManager?

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Soft gates

    /// Current usage count for the running calendar month.
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

    /// Whether the counter chip should be visible (≥70% of limit) so the
    /// user starts to see the limit approaching.
    func shouldShowCounter(_ feature: Feature) -> Bool {
        guard !isPremium else { return false }
        let used = usage(of: feature)
        return Double(used) / Double(feature.freeLimit) >= 0.7
    }

    /// "X / Y" label for the counter chip.
    func counterLabel(_ feature: Feature) -> String {
        "\(usage(of: feature)) / \(feature.freeLimit)"
    }

    // MARK: - Hard gates (UI-only)

    /// Tied to active StoreKit entitlement.
    var isPremium: Bool {
        subscriptionManager?.isSubscribed ?? false
    }

    /// User can toggle iCloud sync on/off in Settings UI. (Free tier sees a
    /// premium badge but can NEVER disable sync — sync is always on under the
    /// hood, this is purely a marketing surface.)
    var canToggleICloudSync: Bool { isPremium }

    /// User can initiate CloudKit Share for collaborative pantry/list.
    var canShareWithFamily: Bool { isPremium }

    /// User can export an external backup (zip via BackupManager).
    var canExportExternalBackup: Bool { isPremium }

    // MARK: - Monthly rollover

    /// Last month identifier we observed (e.g. "2026-05").
    private var lastMonthKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: .now)
    }

    private static let monthDefaultsKey = "featureGate.lastMonth"

    /// Resets all counters when the calendar month changes.
    private func rolloverIfNeeded() {
        let stored = defaults.string(forKey: Self.monthDefaultsKey)
        let current = lastMonthKey
        guard stored != current else { return }
        for feature in Feature.allCases {
            defaults.removeObject(forKey: counterKey(for: feature))
        }
        defaults.set(current, forKey: Self.monthDefaultsKey)
    }

    private func counterKey(for feature: Feature) -> String {
        "featureGate.\(feature.rawValue).count"
    }
}
