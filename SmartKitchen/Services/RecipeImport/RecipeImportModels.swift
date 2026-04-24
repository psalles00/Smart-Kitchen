import Foundation
import OSLog

// MARK: - Source

/// A single input to the recipe import pipeline.
enum RecipeImportSource: Equatable {
    case url(URL)
    case text(String)
    case image(Data)
    case videoFile(URL)
}

enum RecipeImportVideoPolicy {
    static let maxSharedVideoDurationMinutes = 20
    static let maxSharedVideoDurationSeconds = Double(maxSharedVideoDurationMinutes * 60)
    static let maxSharedVideoDurationMessage = "Vídeos enviados devem ter no máximo 20 minutos."
}

// MARK: - Confidence

/// How much we trust an extracted field. Drives the yellow/red badges in preview.
enum FieldConfidence: Equatable {
    case high
    case medium
    case low
}

// MARK: - Draft

/// In-memory draft recipe produced by a pipeline. Mirrors `Recipe` but is
/// `struct`-based so it can be edited in the preview UI before being saved.
struct RecipeDraft: Equatable {
    var name: String = ""
    var nameConfidence: FieldConfidence = .high
    var descriptionText: String = ""
    var descriptionConfidence: FieldConfidence = .high
    var category: String = "Outros"
    var categoryConfidence: FieldConfidence = .low
    var difficulty: Difficulty = .easy
    var prepTime: Int = 0
    var prepTimeConfidence: FieldConfidence = .low
    var cookTime: Int = 0
    var cookTimeConfidence: FieldConfidence = .low
    var servings: Int = 1
    var servingsConfidence: FieldConfidence = .low
    var calories: Int? = nil
    var externalURLString: String = ""
    var imageData: Data? = nil
    var imageURL: URL? = nil
    /// Optional direct video URL from the import source (mainly social pages).
    var videoURL: URL? = nil
    var requiredUtensils: [String] = []
    var ingredients: [IngredientDraft] = []
    var ingredientSections: [SectionDraft] = []
    var steps: [StepDraft] = []
    /// Original source media that should always accompany the saved recipe
    /// (downloaded social video, scanned image, hero image). Written into
    /// `Recipe.preparationMedia` on save with `sourceOriginal = true`.
    var preparationMedia: [ImportDraftPreparationMedia] = []
    /// Human-readable origin hint (e.g. "AllRecipes.com", "Texto colado", "Imagem").
    var sourceLabel: String = ""
    /// Overall confidence aggregated for the whole draft.
    var overallConfidence: FieldConfidence {
        if ingredients.isEmpty || steps.isEmpty { return .low }
        let fields: [FieldConfidence] = [nameConfidence, descriptionConfidence]
        if fields.contains(.low) { return .low }
        if fields.contains(.medium) { return .medium }
        return .high
    }
}

struct IngredientDraft: Equatable, Identifiable {
    let id: UUID
    var name: String
    var quantity: Double?
    var unit: String
    var preparationState: String
    var iconName: String?
    var confidence: FieldConfidence
    /// Optional pointer to `SectionDraft.id` grouping this ingredient. `nil`
    /// means the ingredient belongs to the implicit top (unsectioned) group.
    var sectionID: UUID?

    init(
        id: UUID = UUID(),
        name: String = "",
        quantity: Double? = nil,
        unit: String = "",
        preparationState: String = "",
        iconName: String? = nil,
        confidence: FieldConfidence = .medium,
        sectionID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.preparationState = preparationState
        self.iconName = iconName
        self.confidence = confidence
        self.sectionID = sectionID
    }
}

struct SectionDraft: Equatable, Identifiable {
    let id: UUID
    var title: String
    var subtitle: String
    var sortOrder: Int

    init(id: UUID = UUID(), title: String = "", subtitle: String = "", sortOrder: Int = 0) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.sortOrder = sortOrder
    }
}

struct ImportDraftPreparationMedia: Equatable, Identifiable {
    let id: UUID
    var type: RecipePreparationMediaType
    var data: Data
    var fileExtension: String
    /// Marks media auto-saved from the original import source. Used to
    /// avoid adding duplicates on re-import.
    var sourceOriginal: Bool

    init(
        id: UUID = UUID(),
        type: RecipePreparationMediaType,
        data: Data,
        fileExtension: String = "",
        sourceOriginal: Bool = false
    ) {
        self.id = id
        self.type = type
        self.data = data
        self.fileExtension = fileExtension
        self.sourceOriginal = sourceOriginal
    }
}

struct StepDraft: Equatable, Identifiable {
    let id: UUID
    var order: Int
    var instruction: String
    var durationMinutes: Int?
    var confidence: FieldConfidence

    init(
        id: UUID = UUID(),
        order: Int = 1,
        instruction: String = "",
        durationMinutes: Int? = nil,
        confidence: FieldConfidence = .medium
    ) {
        self.id = id
        self.order = order
        self.instruction = instruction
        self.durationMinutes = durationMinutes
        self.confidence = confidence
    }
}

// MARK: - Stage (for processing UI)

/// Steps shown during the import animation. Wording matches the PRD.
enum RecipeImportStage: Equatable {
    case analyzing
    case fetching
    case extractingText
    case readingVideo
    case organizingIngredients
    case finalizing

    var title: String {
        switch self {
        case .analyzing:            return "Analisando conteúdo"
        case .fetching:             return "Buscando a receita"
        case .extractingText:       return "Extraindo receita"
        case .readingVideo:         return "Lendo vídeo"
        case .organizingIngredients: return "Organizando ingredientes"
        case .finalizing:           return "Finalizando receita"
        }
    }

    var systemImage: String {
        switch self {
        case .analyzing:            return "sparkles"
        case .fetching:             return "network"
        case .extractingText:       return "text.viewfinder"
        case .readingVideo:         return "video.circle"
        case .organizingIngredients: return "list.bullet.rectangle"
        case .finalizing:           return "checkmark.seal"
        }
    }

    /// Progress used for indeterminate animation (0...1).
    var progress: Double {
        switch self {
        case .analyzing:            return 0.10
        case .fetching:             return 0.28
        case .extractingText:       return 0.48
        case .readingVideo:         return 0.60
        case .organizingIngredients: return 0.78
        case .finalizing:           return 0.95
        }
    }
}

enum RecipeImportImprovementStage: CaseIterable, Equatable, Hashable {
    case locatingVideo
    case downloadingVideo
    case extractingAudio
    case transcribingAudio
    case restructuringDraft
    case finalizing

    var title: String {
        switch self {
        case .locatingVideo:     return "Localizando o vídeo"
        case .downloadingVideo:  return "Baixando o vídeo"
        case .extractingAudio:   return "Extraindo o áudio"
        case .transcribingAudio: return "Transcrevendo o vídeo"
        case .restructuringDraft: return "Reorganizando a receita"
        case .finalizing:        return "Finalizando o refino"
        }
    }

    var systemImage: String {
        switch self {
        case .locatingVideo:     return "link"
        case .downloadingVideo:  return "arrow.down.circle"
        case .extractingAudio:   return "waveform"
        case .transcribingAudio: return "text.quote"
        case .restructuringDraft: return "list.bullet.rectangle"
        case .finalizing:        return "checkmark.circle"
        }
    }

    /// Progress reflects completed stages only. The active stage is shown
    /// separately in the UI, and completion is set to 1.0 by the caller.
    var progress: Double {
        let stages = Self.allCases
        guard let index = stages.firstIndex(of: self), !stages.isEmpty else { return 0 }
        return Double(index) / Double(stages.count)
    }
}

struct RecipeDraftMediaSaveSummary: Equatable {
    let totalCount: Int
    let photoCount: Int
    let videoCount: Int
    let includesSourceOriginalMedia: Bool
    let usesCoverFallback: Bool

    var title: String {
        if totalCount == 0 {
            return "Nenhuma mídia adicional será salva"
        }
        if usesCoverFallback && videoCount == 0 && photoCount == 1 {
            return "A capa será salva com a receita"
        }
        return "A revisão vai salvar mídia"
    }

    var detail: String {
        if totalCount == 0 {
            return "Este rascunho não tem fotos ou vídeos extras para persistir."
        }

        var sentences: [String] = []
        if !breakdown.isEmpty {
            sentences.append("Serão salvos \(breakdown).")
        }
        if includesSourceOriginalMedia {
            sentences.append("Inclui mídia original da importação.")
        } else if usesCoverFallback {
            sentences.append("A capa será preservada como mídia de apoio.")
        }
        return sentences.joined(separator: " ")
    }

    var systemImage: String {
        if totalCount == 0 {
            return "photo"
        }
        if videoCount > 0 {
            return "play.rectangle.fill"
        }
        if photoCount > 1 {
            return "photo.on.rectangle.angled"
        }
        return "photo.fill"
    }

    private var breakdown: String {
        var parts: [String] = []
        if videoCount > 0 {
            parts.append(countLabel(videoCount, singular: "vídeo", plural: "vídeos"))
        }
        if photoCount > 0 {
            parts.append(countLabel(photoCount, singular: "foto", plural: "fotos"))
        }
        return parts.joined(separator: ", ")
    }

    private func countLabel(_ count: Int, singular: String, plural: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(plural)"
    }
}

extension RecipeDraft {
    var preparationMediaPreparedForSave: [ImportDraftPreparationMedia] {
        var mediaToPersist = preparationMedia.filter { !$0.data.isEmpty }
        let hasVideoMedia = mediaToPersist.contains { $0.type == .video }

        if hasVideoMedia, let cover = imageData, !cover.isEmpty {
            mediaToPersist.removeAll {
                $0.sourceOriginal && $0.type == .photo && $0.data == cover
            }
        }

        if mediaToPersist.isEmpty, let imageData, !imageData.isEmpty {
            return [
                ImportDraftPreparationMedia(
                    type: .photo,
                    data: imageData,
                    fileExtension: "jpg",
                    sourceOriginal: true
                )
            ]
        }

        return mediaToPersist
    }

    var mediaSaveSummary: RecipeDraftMediaSaveSummary {
        let preparedMedia = preparationMediaPreparedForSave
        let originalMediaCount = preparationMedia.filter { !$0.data.isEmpty }.count
        let photoCount = preparedMedia.filter { $0.type == .photo }.count
        let videoCount = preparedMedia.filter { $0.type == .video }.count

        return RecipeDraftMediaSaveSummary(
            totalCount: preparedMedia.count,
            photoCount: photoCount,
            videoCount: videoCount,
            includesSourceOriginalMedia: preparedMedia.contains { $0.sourceOriginal },
            usesCoverFallback: originalMediaCount == 0 && imageData != nil && preparedMedia.count == 1 && photoCount == 1
        )
    }
}

// MARK: - Errors

enum RecipeImportError: LocalizedError {
    case invalidURL
    case invalidImage
    case emptyContent
    case fetchFailed(String)
    case unsupportedSource(String)
    case insufficientContent(suggestion: String)
    case aiFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL inválida."
        case .invalidImage:
            return "Imagem inválida ou ilegível."
        case .emptyContent:
            return "Conteúdo vazio. Cole um link, texto ou envie uma imagem ou vídeo."
        case .fetchFailed(let msg):
            return "Não foi possível buscar o conteúdo: \(msg)"
        case .unsupportedSource(let msg):
            return "Fonte não suportada: \(msg)"
        case .insufficientContent(let suggestion):
            return "Não encontramos informação suficiente. \(suggestion)"
        case .aiFailed(let msg):
            return "Falha ao estruturar a receita: \(msg)"
        case .cancelled:
            return "Importação cancelada."
        }
    }
}

// MARK: - Logging

enum RecipeImportLogContext {
    @TaskLocal static var sessionID: String = "no-session"
}

enum RecipeImportLogger {
    private static let logger = Logger(subsystem: "com.pedrosalles.smartkitchen.sync", category: "RecipeImport")

    static func debug(_ message: String, sessionID: String? = nil) {
        let sid = sessionID ?? RecipeImportLogContext.sessionID
        logger.debug("[\(sid, privacy: .public)] \(message, privacy: .public)")
        #if DEBUG
        print("[RecipeImport][debug][\(sid)] \(message)")
        #endif
    }

    static func info(_ message: String, sessionID: String? = nil) {
        let sid = sessionID ?? RecipeImportLogContext.sessionID
        logger.info("[\(sid, privacy: .public)] \(message, privacy: .public)")
        #if DEBUG
        print("[RecipeImport][info][\(sid)] \(message)")
        #endif
    }

    static func error(_ message: String, sessionID: String? = nil) {
        let sid = sessionID ?? RecipeImportLogContext.sessionID
        logger.error("[\(sid, privacy: .public)] \(message, privacy: .public)")
        #if DEBUG
        print("[RecipeImport][error][\(sid)] \(message)")
        #endif
    }

    static func sourceSummary(_ source: RecipeImportSource) -> String {
        switch source {
        case .url(let url):
            return "source=url host=\(url.host ?? "-") value=\(url.absoluteString)"
        case .text(let text):
            return "source=text chars=\(text.count) preview=\(preview(text))"
        case .image(let data):
            return "source=image bytes=\(data.count)"
        case .videoFile(let url):
            return "source=video file=\(url.lastPathComponent)"
        }
    }

    static func draftSummary(_ draft: RecipeDraft) -> String {
        "draft name=\(preview(draft.name, limit: 64)) ingredients=\(draft.ingredients.count) steps=\(draft.steps.count) utensils=\(draft.requiredUtensils.count) hasVideoURL=\(draft.videoURL != nil) sourceLabel=\(preview(draft.sourceLabel, limit: 48))"
    }

    static func preview(_ text: String, limit: Int = 120) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > limit else { return compact }
        let idx = compact.index(compact.startIndex, offsetBy: limit)
        return String(compact[..<idx]) + "..."
    }
}
