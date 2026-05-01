import Foundation

/// Ordered list of every screen in the first-launch onboarding flow.
/// The numbering matches the plan in `/memories/session/plan.md`.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    // Phase 1+3 — Apresentação intercalada com tutoriais (intro → como usar)
    case welcome = 0
    // Receitas: intro + tutorial (compartilhar das redes)
    case recipes
    case tutorialShareAndPin
    // Despensa/Mercado: intro + dois tutoriais (ida e volta)
    case pantryShopping
    case tutorialPantryToGrocery
    case tutorialGroceryToPantry
    // Nutrition / IA — a própria tela já é a demo, sem tutorial extra
    case nutritionAndAI

    // Phase 2 — Captura mínima
    case selectPantry
    case selectGrocery
    case selectRecipes

    // Phase 4 — Objetivos / Nutrition
    case goal
    case sex
    case birthday
    case body
    case activity
    case rate
    case preparing

    // Phase 5 — Paywall
    case paywall

    var id: Int { rawValue }

    var isLast: Bool { self == .paywall }

    /// Section label shown at the top progress bar.
    var section: OnboardingSection {
        switch self {
        case .welcome, .recipes, .tutorialShareAndPin,
             .pantryShopping, .tutorialPantryToGrocery, .tutorialGroceryToPantry,
             .nutritionAndAI:
            return .intro
        case .selectPantry, .selectGrocery, .selectRecipes:
            return .capture
        case .goal, .sex, .birthday, .body, .activity, .rate, .preparing:
            return .goals
        case .paywall:
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
