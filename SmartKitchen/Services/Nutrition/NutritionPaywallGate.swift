import SwiftUI

/// Façade fina sobre `FeatureGate` para call sites legados na stack de
/// Nutrição. Em código novo prefira `FeatureGate.shared.canUse(.nutritionAI)`
/// e apresente `PaywallSheet(reason: .limitReached(.nutritionAI))` pela view.
@MainActor
enum NutritionPaywallGate {
    /// True se o usuário pode realizar mais uma análise nutricional via IA
    /// (premium ilimitado, free 2/dia).
    static var canUseNutritionAI: Bool {
        FeatureGate.shared.canUse(.nutritionAI)
    }

    /// True se o usuário tem assinatura premium ativa.
    static var isSubscribed: Bool {
        FeatureGate.shared.isPremium
    }

    /// Conta o consumo de uma análise nutricional. Chamar APÓS sucesso.
    static func consume() {
        FeatureGate.shared.consume(.nutritionAI)
    }

    /// Mantido para compatibilidade — call sites devem migrar para
    /// apresentar `PaywallSheet` diretamente da view.
    static func presentIfNeeded() {
        // no-op — apresentação do paywall é responsabilidade da view.
    }
}
