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

    /// Last source passed to `start(_:)`. Used by `runDeepAttempt()` to retry
    /// failed imports with the heavier improver pipeline (video download +
    /// transcription + AI restructuring).
    private(set) var lastSource: RecipeImportSource?

    /// True once the deep attempt has been used for the current session.
    /// Prevents the user from triggering the deep attempt multiple times and
    /// drives the UI to fall back to the generic "Tentar outra" action.
    private(set) var deepAttemptUsed: Bool = false

    /// True while the deep attempt task is running. Used to disable the
    /// button and avoid duplicate triggers.
    private(set) var isDeepAttempting: Bool = false

    private let orchestrator: RecipeImportOrchestrator
    private var currentTask: Task<Void, Never>?
    private var currentSessionID: String = "no-session"

    init(orchestrator: RecipeImportOrchestrator = .init()) {
        self.orchestrator = orchestrator
        RecipeImportLogger.info("coordinator initialized")
    }

    /// Whether the last source supports a deeper retry using the improver.
    /// Only URL-based and videoFile sources can currently benefit from
    /// downloading/transcribing media for a second attempt.
    var supportsDeepAttempt: Bool {
        switch lastSource {
        case .url, .videoFile:
            return true
        case .text, .image, .none:
            return false
        }
    }

    // MARK: - Actions

    func start(_ source: RecipeImportSource) {
        let sessionID = UUID().uuidString
        currentSessionID = sessionID
        RecipeImportLogger.info("start import \(RecipeImportLogger.sourceSummary(source))", sessionID: sessionID)
        currentTask?.cancel()
        lastSource = source
        deepAttemptUsed = false
        isDeepAttempting = false
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
        isDeepAttempting = false
        phase = .pickingSource
    }

    func retry() {
        RecipeImportLogger.info("retry requested", sessionID: currentSessionID)
        lastSource = nil
        deepAttemptUsed = false
        isDeepAttempting = false
        phase = .pickingSource
    }

    /// Runs the deep import attempt using `RecipeImportImprover` on top of a
    /// minimal draft built from `lastSource`. Re-enters `.processing` while
    /// running and transitions to `.preview` on success or `.failed` on error.
    func runDeepAttempt() {
        guard !isDeepAttempting, !deepAttemptUsed else {
            RecipeImportLogger.info("deep attempt ignored (isDeepAttempting=\(isDeepAttempting) used=\(deepAttemptUsed))", sessionID: currentSessionID)
            return
        }
        guard let source = lastSource else {
            RecipeImportLogger.error("deep attempt requested but lastSource is nil", sessionID: currentSessionID)
            return
        }

        var seedDraft = RecipeDraft()
        switch source {
        case .url(let url):
            seedDraft.externalURLString = url.absoluteString
            seedDraft.sourceLabel = "Importação refinada"
        case .videoFile(let url):
            seedDraft.videoURL = url
            seedDraft.sourceLabel = "Vídeo compartilhado"
        case .text, .image:
            RecipeImportLogger.error("deep attempt not supported for source kind", sessionID: currentSessionID)
            return
        }

        let sessionID = UUID().uuidString
        currentSessionID = sessionID
        RecipeImportLogger.info("deep attempt start \(RecipeImportLogger.sourceSummary(source))", sessionID: sessionID)

        isDeepAttempting = true
        deepAttemptUsed = true
        currentTask?.cancel()
        phase = .processing(stage: .readingVideo)

        currentTask = Task { [weak self] in
            guard let self else { return }
            await RecipeImportLogContext.$sessionID.withValue(sessionID) {
                defer {
                    self.isDeepAttempting = false
                }
                do {
                    let improver = RecipeImportImprover()
                    let improved = try await improver.improve(draft: seedDraft) { [weak self] stage in
                        guard let self else { return }
                        RecipeImportLogger.debug("deep stage callback=\(stage.title)", sessionID: sessionID)
                        switch stage {
                        case .locatingVideo, .downloadingVideo, .extractingAudio, .transcribingAudio:
                            self.phase = .processing(stage: .readingVideo)
                        case .restructuringDraft:
                            self.phase = .processing(stage: .organizingIngredients)
                        case .finalizing:
                            self.phase = .processing(stage: .finalizing)
                        }
                    }
                    if Task.isCancelled {
                        RecipeImportLogger.info("deep attempt cancelled before preview", sessionID: sessionID)
                        return
                    }
                    self.phase = .preview(draft: improved)
                    RecipeImportLogger.info("deep attempt preview ready \(RecipeImportLogger.draftSummary(improved))", sessionID: sessionID)
                    HapticManager.impact(style: .medium)
                } catch is CancellationError {
                    RecipeImportLogger.info("deep attempt cancelled by CancellationError", sessionID: sessionID)
                } catch {
                    self.phase = .failed(message: error.localizedDescription)
                    RecipeImportLogger.error("deep attempt failed error=\(error.localizedDescription)", sessionID: sessionID)
                    HapticManager.impact(style: .heavy)
                }
            }
        }
    }

    func dismiss() {
        RecipeImportLogger.info("dismiss requested", sessionID: currentSessionID)
        currentTask?.cancel()
        isDeepAttempting = false
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

        // Persist ingredient sections (if any) and remap draft section ids to
        // freshly-created SwiftData section ids.
        var sectionIDMap: [UUID: UUID] = [:]
        let sortedSectionDrafts = draft.ingredientSections.sorted { $0.sortOrder < $1.sortOrder }
        for (idx, sectionDraft) in sortedSectionDrafts.enumerated() {
            let title = sectionDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = sectionDraft.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty && subtitle.isEmpty { continue }
            let newID = UUID()
            let section = RecipeIngredientSection(
                title: title,
                subtitle: subtitle,
                sortOrder: idx,
                id: newID
            )
            section.recipe = recipe
            context.insert(section)
            sectionIDMap[sectionDraft.id] = newID
        }

        for (index, ing) in draft.ingredients.enumerated() {
            let trimmedName = ing.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }
            let mappedSectionID: UUID? = ing.sectionID.flatMap { sectionIDMap[$0] }
            let ingredient = RecipeIngredient(
                name: trimmedName,
                quantity: ing.quantity,
                unit: ing.unit,
                preparationState: ing.preparationState,
                iconName: ing.iconName ?? ItemDatabase.shared.exactMatch(for: trimmedName)?.nomeDoArquivo,
                sortOrder: index,
                sectionID: mappedSectionID
            )
            ingredient.recipe = recipe
            context.insert(ingredient)
            RecipeImportLogger.debug("save ingredient index=\(index) name=\(trimmedName) section=\(mappedSectionID?.uuidString ?? "-")", sessionID: currentSessionID)
        }

        for step in draft.steps {
            let trimmed = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let s = RecipeStep(order: step.order, instruction: trimmed, durationMinutes: step.durationMinutes)
            s.recipe = recipe
            context.insert(s)
            RecipeImportLogger.debug("save step order=\(step.order) chars=\(trimmed.count)", sessionID: currentSessionID)
        }

        let mediaToPersist = draft.preparationMediaPreparedForSave

        for (index, media) in mediaToPersist.enumerated() {
            guard !media.data.isEmpty else { continue }
            let attachment = RecipePreparationMedia(
                mediaType: media.type,
                data: media.data,
                fileExtension: media.fileExtension,
                sortOrder: index,
                sourceOriginal: media.sourceOriginal
            )
            attachment.recipe = recipe
            context.insert(attachment)
            RecipeImportLogger.debug("save preparation media index=\(index) type=\(media.type.rawValue) bytes=\(media.data.count) original=\(media.sourceOriginal)", sessionID: currentSessionID)
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
