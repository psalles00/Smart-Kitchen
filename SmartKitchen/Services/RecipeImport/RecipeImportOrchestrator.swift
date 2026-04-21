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
        guard let pipeline = pipelines.first(where: { $0.canHandle(source) }) else {
            throw RecipeImportError.unsupportedSource("Nenhum pipeline disponível.")
        }
        onStage(.analyzing)
        let draft = try await pipeline.run(source: source, onStage: onStage)
        onStage(.organizingIngredients)
        let normalized = normalizer.normalize(draft)
        onStage(.finalizing)
        return normalized
    }
}
