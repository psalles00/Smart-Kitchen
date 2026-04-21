import Foundation

/// Pipeline protocol: each strategy implements `canHandle` + `run`.
/// Running on MainActor keeps the flow simple (SwiftData + UI live there).
@MainActor
protocol RecipeImportPipeline {
    /// Short human-readable label for logging / debugging.
    var name: String { get }
    /// Whether this pipeline can handle the given source.
    func canHandle(_ source: RecipeImportSource) -> Bool
    /// Run the pipeline. Reports progress via the `onStage` callback.
    func run(
        source: RecipeImportSource,
        onStage: @MainActor (RecipeImportStage) -> Void
    ) async throws -> RecipeDraft
}
