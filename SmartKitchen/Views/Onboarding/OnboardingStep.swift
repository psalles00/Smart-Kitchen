import Foundation

/// Ordered list of every screen in the first-launch onboarding flow.
/// The intro section now follows the redesigned 7-page presentation that
/// mirrors the app's pillars and main differentiators.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    // Phase 1 — Apresentação (welcome + 7 telas de diferenciais)
    case welcome = 0
    case overview                 // 1. Tudo num só lugar
    case recipeIdeas              // 2. Chega de travar — busca/sugestões
    case saveRecipes              // 3. Salve receitas em segundos
    case smartCount               // 4. Pulou um dia? sem drama (média inteligente)
    case multimodalLogging        // 5. Registre como quiser (foto/voz/texto)
    case pantryGrocerySync        // 6. Despensa ⇄ Mercado
    case nutritionCoach           // 7. Nutrition Coach (IA)

    // Phase 2 — Captura mínima
    case selectPantry
    case selectGrocery
    case selectRecipes

    case discoverySource

    // Phase 4 — Objetivos / Nutrition
    case goal
    case sex
    case birthday
    case body
    case activity
    case rate
    case preparing
    case goalProjection
    case appReview
    case paywall

    var id: Int { rawValue }

    var isLast: Bool { self == .paywall }

    /// Section label shown at the top progress bar.
    var section: OnboardingSection {
        switch self {
        case .welcome,
             .overview, .recipeIdeas, .saveRecipes, .smartCount,
             .multimodalLogging, .pantryGrocerySync, .nutritionCoach:
            return .intro
        case .selectPantry, .selectGrocery, .selectRecipes:
            return .capture
        case .goal, .sex, .birthday, .body, .activity, .rate, .discoverySource, .preparing, .goalProjection:
            return .goals
        case .appReview, .paywall:
            return .paywall
        }
    }
}

enum OnboardingSection: Int, CaseIterable {
    case intro
    case capture
    case goals
    case paywall
}
