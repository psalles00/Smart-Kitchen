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
        RecipeImportLogger.info("image OCR pipeline started")
        guard case let .image(data) = source else {
            RecipeImportLogger.error("image OCR pipeline received non-image source")
            throw RecipeImportError.unsupportedSource("Esperado imagem.")
        }
        RecipeImportLogger.debug("image bytes=\(data.count)")
        guard !data.isEmpty else { throw RecipeImportError.emptyContent }

        onStage(.analyzing)
        RecipeImportLogger.debug("stage=\(RecipeImportStage.analyzing.title)")
        onStage(.extractingText)
        RecipeImportLogger.debug("stage=\(RecipeImportStage.extractingText.title)")

        let text = try await recognizeText(in: data)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        RecipeImportLogger.info("ocr extracted chars=\(trimmed.count) lines=\(trimmed.split(separator: "\n").count)")
        guard trimmed.count >= 20 else {
            RecipeImportLogger.error("ocr insufficient text chars=\(trimmed.count)")
            throw RecipeImportError.insufficientContent(
                suggestion: "Não consegui ler texto suficiente da imagem. Tente uma foto mais nítida ou envie apenas o trecho da receita."
            )
        }

        onStage(.organizingIngredients)
        RecipeImportLogger.debug("stage=\(RecipeImportStage.organizingIngredients.title)")
        let structurer = RecipeStructurer()
        var draft = try await structurer.structure(
            text: trimmed,
            hints: RecipeStructurer.Hints(sourceLabel: "Imagem")
        )
        RecipeImportLogger.info("ocr structured \(RecipeImportLogger.draftSummary(draft))")

        // Preserve original image as cover when no remote image was produced.
        if draft.imageData == nil && draft.imageURL == nil {
            draft.imageData = data
        }

        // Always attach the scanned image as original source media so the user
        // can find the raw material under "Adicionar Fotos ou Vídeos".
        if !draft.preparationMedia.contains(where: { $0.sourceOriginal && $0.type == .photo && $0.data == data }) {
            draft.preparationMedia.append(
                ImportDraftPreparationMedia(
                    type: .photo,
                    data: data,
                    fileExtension: "jpg",
                    sourceOriginal: true
                )
            )
        }

        onStage(.finalizing)
        RecipeImportLogger.debug("stage=\(RecipeImportStage.finalizing.title)")
        if draft.sourceLabel.isEmpty { draft.sourceLabel = "Imagem" }
        RecipeImportLogger.info("image OCR pipeline completed sourceLabel=\(draft.sourceLabel)")
        return draft
    }

    // MARK: - OCR

    /// `nonisolated` para que os closures literais usados em
    /// `VNRecognizeTextRequest(completionHandler:)` e na chamada do `handler.perform`
    /// não herdem `@MainActor` da struct externa. O Vision invoca o completion
    /// handler em uma thread interna; closures `@MainActor` ali disparam
    /// `_swift_task_checkIsolatedSwift` → EXC_BREAKPOINT.
    private nonisolated func recognizeText(in data: Data) async throws -> String {
        #if canImport(Vision) && canImport(UIKit)
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            RecipeImportLogger.error("ocr invalid image payload")
            throw RecipeImportError.invalidImage
        }

        return try await Self.performOCR(on: cgImage)
        #else
        RecipeImportLogger.error("ocr unsupported platform")
        throw RecipeImportError.unsupportedSource("OCR não disponível nesta plataforma.")
        #endif
    }

    #if canImport(Vision) && canImport(UIKit)
    private nonisolated static func performOCR(on cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    RecipeImportLogger.error("ocr Vision request error=\(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                RecipeImportLogger.debug("ocr Vision observations=\(observations.count) lines=\(lines.count)")
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = AppLocalization.current().visionRecognitionLanguages

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    RecipeImportLogger.error("ocr handler perform error=\(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    #endif
}
