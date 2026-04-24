import SwiftUI

/// Placeholder de gate de assinatura para funcionalidades premium de Nutrição.
/// Hoje está inerte — toda a experiência continua gratuita. Quando/se formos
/// monetizar, basta trocar `isSubscribed` para respeitar `PurchaseManager`.
enum NutritionPaywallGate {
    /// Retorna `true` enquanto não houver paywall ativa. Mantém a API pronta
    /// para chamadores como `FoodCaptureHostView` ou `NutritionAIService` sem
    /// tocar em nenhuma UI de compras.
    static var isSubscribed: Bool { true }

    /// Apresenta o fluxo premium. Inerte por enquanto.
    static func presentIfNeeded() {
        // no-op até integrarmos com StoreKit / PurchaseManager.
    }
}
