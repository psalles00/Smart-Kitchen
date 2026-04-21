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
        RecipeImportLogger.info("text pipeline started")
        guard case let .text(raw) = source else {
            RecipeImportLogger.error("text pipeline received non-text source")
            throw RecipeImportError.unsupportedSource("Esperado texto.")
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        RecipeImportLogger.debug("text payload chars=\(raw.count) trimmedChars=\(trimmed.count)")
        guard !trimmed.isEmpty else { throw RecipeImportError.emptyContent }

        onStage(.analyzing)
        RecipeImportLogger.debug("stage=\(RecipeImportStage.analyzing.title)")
        onStage(.organizingIngredients)
        RecipeImportLogger.debug("stage=\(RecipeImportStage.organizingIngredients.title)")

        let structurer = RecipeStructurer()
        var draft = try await structurer.structure(
            text: trimmed,
            hints: RecipeStructurer.Hints(sourceLabel: "Texto colado")
        )
        RecipeImportLogger.info("text pipeline structured \(RecipeImportLogger.draftSummary(draft))")

        onStage(.finalizing)
        RecipeImportLogger.debug("stage=\(RecipeImportStage.finalizing.title)")
        if draft.sourceLabel.isEmpty { draft.sourceLabel = "Texto colado" }
        RecipeImportLogger.info("text pipeline completed sourceLabel=\(draft.sourceLabel)")
        return draft
    }
}
