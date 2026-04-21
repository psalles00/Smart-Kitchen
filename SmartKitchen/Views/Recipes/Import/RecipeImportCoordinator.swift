import Foundation
import SwiftUI
import SwiftData

/// View-model that owns the import session lifecycle.
@MainActor
@Observable
final class RecipeImportCoordinator {

    enum Phase: Equatable {
        case pickingSource
        case processing(stage: RecipeImportStage)
        case preview(draft: RecipeDraft)
        case savedRecipeID(UUID)
        case failed(message: String)
    }

    var phase: Phase = .pickingSource
    var isPresented: Bool = true

    /// Pre-filled source (when the caller already has content — e.g. from share extension).
    var prefilledSource: RecipeImportSource?

    private let orchestrator: RecipeImportOrchestrator
    private var currentTask: Task<Void, Never>?

    init(orchestrator: RecipeImportOrchestrator = .init()) {
        self.orchestrator = orchestrator
    }

    // MARK: - Actions

    func start(_ source: RecipeImportSource) {
        currentTask?.cancel()
        phase = .processing(stage: .analyzing)
        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let draft = try await self.orchestrator.importRecipe(from: source) { [weak self] stage in
                    guard let self else { return }
                    self.phase = .processing(stage: stage)
                }
                if Task.isCancelled { return }
                self.phase = .preview(draft: draft)
                HapticManager.impact(style: .medium)
            } catch is CancellationError {
                // swallow
            } catch {
                self.phase = .failed(message: error.localizedDescription)
                HapticManager.impact(style: .heavy)
            }
        }
    }

    func cancel() {
        currentTask?.cancel()
        phase = .pickingSource
    }

    func retry() {
        phase = .pickingSource
    }

    func dismiss() {
        currentTask?.cancel()
        isPresented = false
    }

    // MARK: - Save

    /// Persists the edited draft into the user's recipe library.
    @discardableResult
    func save(draft: RecipeDraft, in context: ModelContext) -> Recipe {
        let recipe = Recipe(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            descriptionText: draft.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            imageData: draft.imageData,
            externalURLString: draft.externalURLString.trimmingCharacters(in: .whitespacesAndNewlines),
            category: draft.category,
            prepTime: draft.prepTime,
            cookTime: draft.cookTime,
            servings: draft.servings,
            calories: draft.calories,
            difficulty: draft.difficulty
        )
        context.insert(recipe)
        recipe.requiredUtensils = draft.requiredUtensils.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        for (index, ing) in draft.ingredients.enumerated() {
            let trimmedName = ing.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }
            let ingredient = RecipeIngredient(
                name: trimmedName,
                quantity: ing.quantity,
                unit: ing.unit,
                preparationState: ing.preparationState,
                iconName: ing.iconName ?? ItemDatabase.shared.exactMatch(for: trimmedName)?.nomeDoArquivo,
                sortOrder: index
            )
            ingredient.recipe = recipe
            context.insert(ingredient)
        }

        for step in draft.steps {
            let trimmed = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let s = RecipeStep(order: step.order, instruction: trimmed, durationMinutes: step.durationMinutes)
            s.recipe = recipe
            context.insert(s)
        }

        try? context.save()
        phase = .savedRecipeID(recipe.id)
        HapticManager.impact(style: .medium)
        return recipe
    }
}
