import Foundation
#if canImport(Vision)
import Vision
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Pipeline for an image source. Runs on-device OCR via Vision and then
/// feeds the extracted text into the RecipeStructurer for LLM parsing.
@MainActor
struct ImageOCRPipeline: RecipeImportPipeline {

    let name = "image-ocr"

    func canHandle(_ source: RecipeImportSource) -> Bool {
        if case .image = source { return true }
        return false
    }

    func run(
        source: RecipeImportSource,
        onStage: @MainActor (RecipeImportStage) -> Void
    ) async throws -> RecipeDraft {
        guard case let .image(data) = source else {
            throw RecipeImportError.unsupportedSource("Esperado imagem.")
        }
        guard !data.isEmpty else { throw RecipeImportError.emptyContent }

        onStage(.analyzing)
        onStage(.extractingText)

        let text = try await recognizeText(in: data)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else {
            throw RecipeImportError.insufficientContent(
                suggestion: "Não consegui ler texto suficiente da imagem. Tente uma foto mais nítida ou envie apenas o trecho da receita."
            )
        }

        onStage(.organizingIngredients)
        let structurer = RecipeStructurer()
        var draft = try await structurer.structure(
            text: trimmed,
            hints: RecipeStructurer.Hints(sourceLabel: "Imagem")
        )

        // Preserve original image as cover when no remote image was produced.
        if draft.imageData == nil && draft.imageURL == nil {
            draft.imageData = data
        }

        onStage(.finalizing)
        if draft.sourceLabel.isEmpty { draft.sourceLabel = "Imagem" }
        return draft
    }

    // MARK: - OCR

    private func recognizeText(in data: Data) async throws -> String {
        #if canImport(Vision) && canImport(UIKit)
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            throw RecipeImportError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["pt-BR", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        #else
        throw RecipeImportError.unsupportedSource("OCR não disponível nesta plataforma.")
        #endif
    }
}
