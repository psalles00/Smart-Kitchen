import Foundation

/// Ordered list of every screen in the first-launch onboarding flow.
/// The numbering matches the plan in `/memories/session/plan.md`.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    // Phase 1 — Apresentação
    case welcome = 0
    case recipes
    case pantryShopping
    case nutritionAndAI

    // Phase 2 — Captura mínima
    case selectPantry
    case selectGrocery
    case selectRecipes

    // Phase 3 — Tutorial interativo
    case tutorialPantryToGrocery
    case tutorialGroceryToPantry
    case tutorialShareAndPin

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

    /// Section label shown at the top progress bar (one of 5 sections).
    var section: OnboardingSection {
        switch self {
        case .welcome, .recipes, .pantryShopping, .nutritionAndAI:
            return .intro
        case .selectPantry, .selectGrocery, .selectRecipes:
            return .capture
        case .tutorialPantryToGrocery, .tutorialGroceryToPantry, .tutorialShareAndPin:
            return .tutorial
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
    case tutorial
    case goals
    case paywall
}
