import Foundation
import AVFoundation

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
            LocalVideoPipeline(),
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

@MainActor
private struct LocalVideoPipeline: RecipeImportPipeline {
    let name = "local-video"

    func canHandle(_ source: RecipeImportSource) -> Bool {
        if case .videoFile = source { return true }
        return false
    }

    func run(
        source: RecipeImportSource,
        onStage: @MainActor (RecipeImportStage) -> Void
    ) async throws -> RecipeDraft {
        guard case let .videoFile(fileURL) = source else {
            throw RecipeImportError.unsupportedSource("Esperado vídeo local.")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw RecipeImportError.unsupportedSource("O vídeo compartilhado não está mais disponível.")
        }

        try await validateVideoDuration(for: fileURL)

        let improver = RecipeImportImprover()
        let filenameStem = fileURL.deletingPathExtension().lastPathComponent

        var draft = RecipeDraft()
        draft.name = prettyTitle(from: filenameStem)
        draft.nameConfidence = .low
        draft.sourceLabel = "Vídeo compartilhado"
        draft.videoURL = fileURL

        RecipeImportLogger.info("local video pipeline started file=\(fileURL.lastPathComponent)")

        let improved = try await withoutActuallyEscaping(onStage) { escapingOnStage in
            try await improver.improve(draft: draft) { stage in
                switch stage {
                case .locatingVideo, .downloadingVideo, .extractingAudio, .transcribingAudio:
                    escapingOnStage(.readingVideo)
                case .restructuringDraft:
                    escapingOnStage(.organizingIngredients)
                case .finalizing:
                    escapingOnStage(.finalizing)
                }
            }
        }

        var finalized = improved
        if finalized.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalized.name = prettyTitle(from: filenameStem)
            finalized.nameConfidence = .low
        }
        if finalized.sourceLabel.isEmpty {
            finalized.sourceLabel = "Vídeo compartilhado"
        }

        RecipeImportLogger.info("local video pipeline completed \(RecipeImportLogger.draftSummary(finalized))")
        return finalized
    }

    private func prettyTitle(from rawFilename: String) -> String {
        let separators = CharacterSet(charactersIn: "-_")
        let words = rawFilename
            .components(separatedBy: separators)
            .flatMap { $0.split(whereSeparator: { $0.isWhitespace }) }
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return "Receita do vídeo" }
        return words.joined(separator: " ")
    }

    private func validateVideoDuration(for fileURL: URL) async throws {
        let asset = AVURLAsset(url: fileURL)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)

        guard seconds.isFinite else { return }
        if seconds > RecipeImportVideoPolicy.maxSharedVideoDurationSeconds {
            throw RecipeImportError.unsupportedSource(RecipeImportVideoPolicy.maxSharedVideoDurationMessage)
        }
    }
}
