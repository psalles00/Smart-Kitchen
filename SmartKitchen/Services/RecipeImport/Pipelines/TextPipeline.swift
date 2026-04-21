import Foundation

/// Pipeline for raw pasted text.
@MainActor
struct TextPipeline: RecipeImportPipeline {

    let name = "text"

    func canHandle(_ source: RecipeImportSource) -> Bool {
        if case .text = source { return true }
        return false
    }

    func run(
        source: RecipeImportSource,
        onStage: @MainActor (RecipeImportStage) -> Void
    ) async throws -> RecipeDraft {
        guard case let .text(raw) = source else {
            throw RecipeImportError.unsupportedSource("Esperado texto.")
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RecipeImportError.emptyContent }

        onStage(.analyzing)
        onStage(.organizingIngredients)

        let structurer = RecipeStructurer()
        var draft = try await structurer.structure(
            text: trimmed,
            hints: RecipeStructurer.Hints(sourceLabel: "Texto colado")
        )

        onStage(.finalizing)
        if draft.sourceLabel.isEmpty { draft.sourceLabel = "Texto colado" }
        return draft
    }
}
