import SwiftUI

/// Presents the same paywall used in onboarding, but as a modal sheet for
/// in-app upgrade prompts (limit reached, hard-gated action, etc.).
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showPaywall) {
///     PaywallSheet(reason: .limitReached(.ai))
/// }
/// ```
struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss

    enum Reason: Identifiable {
        case limitReached(FeatureGate.Feature)
        case hardGate(String)
        case manual

        var id: String {
            switch self {
            case .limitReached(let f): return "limit-\(f.rawValue)"
            case .hardGate(let s):     return "hard-\(s)"
            case .manual:              return "manual"
            }
        }

        var title: String {
            switch self {
            case .limitReached(let f):
                return String(format: String(localized: "Você atingiu o limite diário de %@."), f.displayName)
            case .hardGate(let label):
                return label
            case .manual:
                return String(localized: "Desbloqueie tudo no Savoria")
            }
        }
    }

    let reason: Reason

    /// Reuses an `OnboardingState` purely so it can host `PaywallStepView`.
    /// Nothing on this state is persisted from a sheet presentation.
    @State private var dummyState = OnboardingState()

    var body: some View {
        ZStack {
            PaywallStepView(state: dummyState, onFinish: { _ in
                dismiss()
            })
            .overlay(alignment: .top) {
                if case .limitReached = reason {
                    Text(reason.title)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .padding(.top, 8)
                }
            }
        }
    }
}

/// Compact chip used near AI/import call sites to show the user is close to
/// their monthly limit.
struct FeatureCounterChip: View {
    let feature: FeatureGate.Feature
    @State private var gate = FeatureGate.shared

    var body: some View {
        if gate.shouldShowCounter(feature) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 11, weight: .bold))
                Text(gate.counterLabel(feature))
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
            .foregroundStyle(Color.orange)
            .transition(.scale.combined(with: .opacity))
        }
    }
}
