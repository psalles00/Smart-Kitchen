import Foundation
import Observation

/// In-memory model that aggregates every choice the user makes through the
/// onboarding flow. Nothing is persisted to SwiftData until the very last
/// step (`OnboardingStep.preparing`) commits everything atomically. This keeps
/// the database clean if the user kills the app halfway through.
@Observable
final class OnboardingState {
    /// Current step index inside `OnboardingStep.allCases`.
    var stepIndex: Int = 0

    // MARK: - Phase 2 selections (≥3 each)
    /// Identifiers of pantry items chosen on the pantry catalog screen.
    var selectedPantryItemIDs: Set<String> = []
    /// Identifiers of grocery items chosen on the grocery catalog screen.
    var selectedGroceryItemIDs: Set<String> = []
    /// Identifiers of recipe templates chosen on the recipe interests screen.
    var selectedRecipeTemplateIDs: Set<String> = []

    // MARK: - Phase 3 tutorial gates
    /// Set to true after the user actually toggles the demo checkbox in the
    /// pantry → grocery tutorial.
    var didCompletePantryToGroceryTutorial: Bool = false
    /// Set to true after the user actually toggles the demo checkbox in the
    /// grocery → pantry tutorial.
    var didCompleteGroceryToPantryTutorial: Bool = false

    // MARK: - Phase 4 nutrition
    /// Mirrors `NutritionProfile` fields. Only persisted on the preparing step.
    var nutritionGoalRaw: String? = nil       // WeightGoal raw value
    var nutritionSexRaw: String? = nil        // NutritionSex raw value
    var nutritionBirthday: Date? = nil
    var nutritionHeightCm: Double = 170
    var nutritionWeightKg: Double = 70
    var nutritionActivityRaw: String? = nil   // ActivityLevel raw value
    var nutritionWeeklyChangeKg: Double = 0.5
    /// Goal-rate input mode used on the rate step. The internal source of
    /// truth is always `nutritionWeeklyChangeKg` — when the user picks a
    /// target weight + months, we convert.
    var nutritionRateMode: RateInputMode = .targetWeight
    /// Target weight (kg) the user wants to reach. Only used when
    /// `nutritionRateMode == .targetWeight`. Default = current weight ± 5kg
    /// computed lazily by the view.
    var nutritionTargetWeightKg: Double = 65
    /// Number of months to reach the target weight.
    var nutritionTargetMonths: Int = 3

    // MARK: - Phase 5 paywall
    /// Tracks the plan the user previewed in the paywall (annual/monthly).
    var selectedPlanID: String? = nil

    // MARK: - Computed gates
    var canAdvancePantrySelection: Bool { selectedPantryItemIDs.count >= 3 }
    var canAdvanceGrocerySelection: Bool { selectedGroceryItemIDs.count >= 3 }
    var canAdvanceRecipeSelection: Bool { selectedRecipeTemplateIDs.count >= 3 }
}

/// Goal-rate input mode for `RateStepView`.
enum RateInputMode: String, CaseIterable, Identifiable {
    case targetWeight  // "Quero chegar a X kg em Y meses"
    case perWeek       // "X kg por semana"

    var id: String { rawValue }
}
