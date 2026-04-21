import Foundation

/// Top-level coordinator that picks the right pipeline for a given source
/// and runs it through normalization.
@MainActor
final class RecipeImportOrchestrator {

    private let pipelines: [RecipeImportPipeline]
    private let normalizer: IngredientNormalizer

    init(
        pipelines: [RecipeImportPipeline]? = nil,
        normalizer: IngredientNormalizer = .init()
    ) {
        self.pipelines = pipelines ?? RecipeImportOrchestrator.defaultPipelines()
        self.normalizer = normalizer
    }

    static func defaultPipelines() -> [RecipeImportPipeline] {
        [
            SocialURLPipeline(),
            WebURLPipeline(),
            ImageOCRPipeline(),
            TextPipeline()
        ]
    }

    /// Import the given source. `onStage` fires every time the pipeline changes
    /// stage — use it to drive the processing UI animations.
    func importRecipe(
        from source: RecipeImportSource,
        onStage: @MainActor @escaping (RecipeImportStage) -> Void
    ) async throws -> RecipeDraft {
        RecipeImportLogger.info("orchestrator import started \(RecipeImportLogger.sourceSummary(source))")
        guard let pipeline = pipelines.first(where: { $0.canHandle(source) }) else {
            RecipeImportLogger.error("no pipeline found for source")
            throw RecipeImportError.unsupportedSource("Nenhum pipeline disponível.")
        }
        RecipeImportLogger.info("selected pipeline=\(pipeline.name)")
        onStage(.analyzing)
        RecipeImportLogger.debug("stage=\(RecipeImportStage.analyzing.title)")
        let draft = try await pipeline.run(source: source, onStage: onStage)
        RecipeImportLogger.info("pipeline output \(RecipeImportLogger.draftSummary(draft))")
        onStage(.organizingIngredients)
        RecipeImportLogger.debug("stage=\(RecipeImportStage.organizingIngredients.title)")
        let normalized = normalizer.normalize(draft)
        RecipeImportLogger.info("normalized output \(RecipeImportLogger.draftSummary(normalized))")
        onStage(.finalizing)
        RecipeImportLogger.debug("stage=\(RecipeImportStage.finalizing.title)")
        return normalized
    }
}
