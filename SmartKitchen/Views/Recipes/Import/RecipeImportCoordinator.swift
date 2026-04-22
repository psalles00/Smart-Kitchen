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

    var phase: Phase = .pickingSource {
        didSet {
            RecipeImportLogger.info("phase=\(phaseSummary(phase))", sessionID: currentSessionID)
        }
    }
    var isPresented: Bool = true

    /// Pre-filled source (when the caller already has content — e.g. from share extension).
    var prefilledSource: RecipeImportSource?

    private let orchestrator: RecipeImportOrchestrator
    private var currentTask: Task<Void, Never>?
    private var currentSessionID: String = "no-session"

    init(orchestrator: RecipeImportOrchestrator = .init()) {
        self.orchestrator = orchestrator
        RecipeImportLogger.info("coordinator initialized")
    }

    // MARK: - Actions

    func start(_ source: RecipeImportSource) {
        let sessionID = UUID().uuidString
        currentSessionID = sessionID
        RecipeImportLogger.info("start import \(RecipeImportLogger.sourceSummary(source))", sessionID: sessionID)
        currentTask?.cancel()
        phase = .processing(stage: .analyzing)
        currentTask = Task { [weak self] in
            guard let self else { return }
            await RecipeImportLogContext.$sessionID.withValue(sessionID) {
                do {
                    let draft = try await self.orchestrator.importRecipe(from: source) { [weak self] stage in
                        guard let self else { return }
                        RecipeImportLogger.debug("stage callback=\(stage.title)", sessionID: sessionID)
                        self.phase = .processing(stage: stage)
                    }
                    if Task.isCancelled {
                        RecipeImportLogger.info("task cancelled before preview", sessionID: sessionID)
                        return
                    }
                    self.phase = .preview(draft: draft)
                    RecipeImportLogger.info("preview ready \(RecipeImportLogger.draftSummary(draft))", sessionID: sessionID)
                    HapticManager.impact(style: .medium)
                } catch is CancellationError {
                    RecipeImportLogger.info("import cancelled by CancellationError", sessionID: sessionID)
                } catch {
                    self.phase = .failed(message: error.localizedDescription)
                    RecipeImportLogger.error("import failed error=\(error.localizedDescription)", sessionID: sessionID)
                    HapticManager.impact(style: .heavy)
                }
            }
        }
    }

    func cancel() {
        RecipeImportLogger.info("cancel requested", sessionID: currentSessionID)
        currentTask?.cancel()
        phase = .pickingSource
    }

    func retry() {
        RecipeImportLogger.info("retry requested", sessionID: currentSessionID)
        phase = .pickingSource
    }

    func dismiss() {
        RecipeImportLogger.info("dismiss requested", sessionID: currentSessionID)
        currentTask?.cancel()
        isPresented = false
    }

    // MARK: - Save

    /// Persists the edited draft into the user's recipe library.
    @discardableResult
    func save(draft: RecipeDraft, in context: ModelContext) -> Recipe {
        RecipeImportLogger.info("save start \(RecipeImportLogger.draftSummary(draft))", sessionID: currentSessionID)
        let recipe = Recipe(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            descriptionText: draft.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            imageData: draft.imageData,
            externalURLString: draft.externalURLString.trimmingCharacters(in: .whitespacesAndNewlines),
            category: CategoryMutationService.normalizedRecipeCategoryString(from: draft.category, context: context),
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
            RecipeImportLogger.debug("save ingredient index=\(index) name=\(trimmedName)", sessionID: currentSessionID)
        }

        for step in draft.steps {
            let trimmed = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let s = RecipeStep(order: step.order, instruction: trimmed, durationMinutes: step.durationMinutes)
            s.recipe = recipe
            context.insert(s)
            RecipeImportLogger.debug("save step order=\(step.order) chars=\(trimmed.count)", sessionID: currentSessionID)
        }

        phase = .savedRecipeID(recipe.id)
        RecipeImportLogger.info("save completed recipeID=\(recipe.id.uuidString)", sessionID: currentSessionID)
        HapticManager.impact(style: .medium)
        return recipe
    }

    private func phaseSummary(_ phase: Phase) -> String {
        switch phase {
        case .pickingSource:
            return "pickingSource"
        case .processing(let stage):
            return "processing(\(stage.title))"
        case .preview(let draft):
            return "preview(ingredients=\(draft.ingredients.count),steps=\(draft.steps.count))"
        case .savedRecipeID(let id):
            return "savedRecipeID(\(id.uuidString))"
        case .failed(let message):
            return "failed(\(RecipeImportLogger.preview(message, limit: 120)))"
        }
    }
}
