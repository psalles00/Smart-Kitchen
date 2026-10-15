import Foundation
import SwiftData
import SwiftUI
import CoreData
import Combine

/// Listing fetches keep cover bytes faulted until an actual image needs them.
/// This changes only fetch projection, never the model schema or stored data.
enum RecipeListQuery {
    static func descriptor(sortBy: [SortDescriptor<Recipe>]) -> FetchDescriptor<Recipe> {
        var descriptor = FetchDescriptor<Recipe>(sortBy: sortBy)
        descriptor.propertiesToFetch = [
            \.id, \.name, \.descriptionText, \.externalURLString, \.category, \.tags,
            \.prepTime, \.cookTime, \.servings, \.calories,
            \.proteinG, \.carbsG, \.fatG, \.fiberG, \.sugarG, \.sodiumMg,
            \.nutritionEstimated, \.nutritionUpdatedAt, \.difficulty, \.isFavorite,
            \.requiredUtensils, \.createdAt, \.updatedAt
        ]
        return descriptor
    }
}

/// Keep the last listing across foreground transitions. Refresh only after an
/// actual save/import, rather than re-running a Query from every body getter.
@MainActor @Observable
final class RecipeListCache {
    private(set) var recipes: [Recipe] = []
    private(set) var revision = 0
    private var contextID: ObjectIdentifier?
    private var inputsKey: Int?
    private let sortBy: [SortDescriptor<Recipe>]
    @ObservationIgnored private var pendingLocalRefresh = false
    @ObservationIgnored private var pendingCoordinators: [ObjectIdentifier: NSPersistentStoreCoordinator] = [:]
    @ObservationIgnored private var historyReaders: [ObjectIdentifier: RecipeRemoteHistory] = [:]
    @ObservationIgnored private var notificationDelay: Task<Void, Never>?
    @ObservationIgnored private var notificationWork: Task<Void, Never>?
    @ObservationIgnored private var listingContext: ModelContext?

    init(sortBy: [SortDescriptor<Recipe>]) { self.sortBy = sortBy }

    func loadIfNeeded(in context: ModelContext) {
        listingContext = context
        guard contextID != ObjectIdentifier(context) else { return }
        reload(in: context)
    }

    @discardableResult
    func reload(in context: ModelContext) -> Bool {
        do {
            let result = try context.fetch(RecipeListQuery.descriptor(sortBy: sortBy))
            let key = Self.listingInputsKey(result)
            guard contextID != ObjectIdentifier(context) || inputsKey != key else { return true }
            recipes = result
            contextID = ObjectIdentifier(context)
            inputsKey = key
            revision += 1
            return true
        } catch {
            // A failed read must never replace a previously valid listing.
            PerformanceLogger.event(.recipes, "recipe listing read failed", metadata: String(describing: error))
            return false
        }
    }

    func receive(_ notification: Notification, in context: ModelContext) {
        listingContext = context
        if notification.name == .NSPersistentStoreRemoteChange,
           let coordinator = notification.object as? NSPersistentStoreCoordinator {
            pendingCoordinators[ObjectIdentifier(coordinator)] = coordinator
        } else {
            // Missing history metadata must never hide a real import.
            pendingLocalRefresh = true
        }
        guard notificationWork == nil else { return }
        notificationDelay?.cancel()
        notificationDelay = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self else { return }
            self.notificationDelay = nil
            self.notificationWork = Task { @MainActor [weak self] in
                await self?.drainNotifications()
            }
        }
    }

    private func drainNotifications() async {
        defer { notificationWork = nil }
        while pendingLocalRefresh || !pendingCoordinators.isEmpty {
            var needsReload = pendingLocalRefresh
            let coordinators = pendingCoordinators
            pendingLocalRefresh = false
            pendingCoordinators.removeAll(keepingCapacity: true)
            var inspections: [(RecipeRemoteHistory, RecipeRemoteHistory.Inspection)] = []
            for (id, coordinator) in coordinators {
                let reader = historyReaders[id] ?? RecipeRemoteHistory(coordinator: coordinator)
                historyReaders[id] = reader
                let inspection = await reader.inspect()
                inspections.append((reader, inspection))
                needsReload = needsReload || inspection.requiresReload
            }
            guard let context = listingContext else { return }
            if !needsReload || reload(in: context) {
                // Advance only after a successful listing read. A failed read
                // retains the old checkpoint so the next notification retries.
                for (reader, inspection) in inspections { await reader.acknowledge(inspection) }
            }
            if pendingLocalRefresh || !pendingCoordinators.isEmpty {
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private static func listingInputsKey(_ recipes: [Recipe]) -> Int {
        var hasher = Hasher()
        hasher.combine(recipes.count)
        for recipe in recipes {
            hasher.combine(recipe.id)
            hasher.combine(recipe.name)
            hasher.combine(recipe.descriptionText)
            hasher.combine(recipe.externalURLString)
            hasher.combine(recipe.category)
            hasher.combine(recipe.tags)
            hasher.combine(recipe.createdAt)
            hasher.combine(recipe.updatedAt)
            hasher.combine(recipe.prepTime)
            hasher.combine(recipe.cookTime)
            hasher.combine(recipe.servings)
            hasher.combine(recipe.difficulty)
            hasher.combine(recipe.isFavorite)
            hasher.combine(recipe.requiredUtensils)
            hasher.combine(recipe.calories)
            hasher.combine(recipe.proteinG)
            hasher.combine(recipe.carbsG)
            hasher.combine(recipe.fatG)
            hasher.combine(recipe.fiberG)
            hasher.combine(recipe.sugarG)
            hasher.combine(recipe.sodiumMg)
            hasher.combine(recipe.nutritionEstimated)
            hasher.combine(recipe.nutritionUpdatedAt)
            for ingredient in recipe.ingredients ?? [] {
                hasher.combine(ingredient.id)
                hasher.combine(ingredient.name)
                hasher.combine(ingredient.quantity)
                hasher.combine(ingredient.unit)
                hasher.combine(ingredient.preparationState)
                hasher.combine(ingredient.sortOrder)
            }
        }
        return hasher.finalize()
    }
}

/// Save notifications cover the entire store, including settings and nutrition.
/// Inspect identifiers before debouncing so unrelated saves neither fetch all
/// recipes nor postpone a pending recipe refresh. Unknown/remote changes remain
/// conservative: they must still refresh imports from CloudKit or extensions.
enum RecipeListInvalidation {
    private static let entities: Set<String> = [
        "Recipe", "RecipeIngredient", "RecipeIngredientSection", "RecipeStep", "RecipePreparationMedia"
    ]

    // A function reference keeps this work on the notification's posting queue;
    // a closure declared inside View.body inherits MainActor under Swift 6.
    static func shouldRefresh(_ notification: Notification) -> Bool {
        let affected = affectsRecipes(notification)
        PerformanceLogger.event(.recipes, "recipe listing notification", metadata: "source=\(notification.name.rawValue) reload=\(affected)")
        return affected
    }

    static func affectsRecipes(_ notification: Notification) -> Bool {
        guard notification.name != .NSPersistentStoreRemoteChange,
              let info = notification.userInfo else { return true }
        if notification.name == ModelContext.didSave {
            let invalidated = ModelContext.NotificationKey.invalidatedAllIdentifiers
            if info[invalidated] != nil || info[invalidated.rawValue] != nil { return true }
            var recognized = false
            for key in [ModelContext.NotificationKey.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers] {
                guard let value = info[key] ?? info[key.rawValue] else { continue }
                let identifiers: [PersistentIdentifier]
                if let values = value as? [PersistentIdentifier] { identifiers = values }
                else if let values = value as? Set<PersistentIdentifier> { identifiers = Array(values) }
                else { return true }
                recognized = true
                if identifiers.contains(where: { isRecipeEntity($0.entityName) }) { return true }
            }
            return !recognized
        }
        if notification.name == .NSManagedObjectContextDidSave {
            if info[NSInvalidatedAllObjectsKey] != nil { return true }
            var recognized = false
            for key in [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSInvalidatedObjectsKey,
                        NSInsertedObjectIDsKey, NSUpdatedObjectIDsKey, NSDeletedObjectIDsKey] {
                guard let value = info[key] else { continue }
                let names: [String?]
                if let objects = value as? Set<NSManagedObject> { names = objects.map { $0.objectID.entity.name } }
                else if let identifiers = value as? Set<NSManagedObjectID> { names = identifiers.map { $0.entity.name } }
                else if let objects = value as? [NSManagedObject] { names = objects.map { $0.objectID.entity.name } }
                else if let identifiers = value as? [NSManagedObjectID] { names = identifiers.map { $0.entity.name } }
                else { return true }
                recognized = true
                if names.contains(where: { $0 == nil || isRecipeEntity($0!) }) { return true }
            }
            return !recognized
        }
        return true
    }

    static func isRecipeEntity(_ name: String) -> Bool {
        entities.contains(name.split(separator: ".").last.map(String.init) ?? name)
    }
}

/// Uses the coordinator delivered by Core Data's public remote notification.
/// Only a private-queue history context is created: no store, option, schema or
/// sync flag is changed, and no model objects cross into the UI context.
final class RecipeRemoteHistory: @unchecked Sendable {
    struct Inspection: @unchecked Sendable {
        let requiresReload: Bool
        let checkpoint: NSPersistentHistoryToken?
    }

    private let context: NSManagedObjectContext
    // Accessed only through context.perform, including acknowledgements.
    private var checkpoint: NSPersistentHistoryToken?

    init(coordinator: NSPersistentStoreCoordinator) {
        context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.undoManager = nil
    }

    func inspect() async -> Inspection {
        await context.perform {
            guard let coordinator = self.context.persistentStoreCoordinator,
                  let upperBound = coordinator.currentPersistentHistoryToken(fromStores: nil) else {
                return Inspection(requiresReload: true, checkpoint: nil)
            }
            do {
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: self.checkpoint)
                request.resultType = .transactionsAndChanges
                guard let result = try self.context.execute(request) as? NSPersistentHistoryResult,
                      let transactions = result.result as? [NSPersistentHistoryTransaction] else {
                    return Inspection(requiresReload: true, checkpoint: nil)
                }
                let changed = transactions.contains { transaction in
                    guard let changes = transaction.changes else { return true }
                    return changes.contains { change in
                        guard let name = change.changedObjectID.entity.name else { return true }
                        return RecipeListInvalidation.isRecipeEntity(name)
                    }
                }
                PerformanceLogger.event(.recipes, "recipe remote history", metadata: "transactions=\(transactions.count) reload=\(changed)")
                // Capture before fetching. A concurrent commit may be included
                // by the read, but must never be skipped by a newer checkpoint.
                return Inspection(requiresReload: changed, checkpoint: upperBound)
            } catch {
                self.checkpoint = nil // An expired bookmark is only in-memory state.
                PerformanceLogger.event(.recipes, "recipe remote history unavailable")
                return Inspection(requiresReload: true, checkpoint: nil)
            }
        }
    }

    func acknowledge(_ inspection: Inspection) async {
        guard let checkpoint = inspection.checkpoint else { return }
        await context.perform { self.checkpoint = checkpoint }
    }
}

struct RecipeListObservation: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    let cache: RecipeListCache

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: ModelContext.didSave)
                .merge(with: NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave),
                       NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange))
                .filter(RecipeListInvalidation.shouldRefresh)
                .receive(on: RunLoop.main)
        ) { notification in
            cache.receive(notification, in: modelContext)
        }
    }
}

// MARK: - Identified Utensil (for Form ForEach)

struct IdentifiedUtensil: Identifiable {
    let id = UUID()
    var name: String
    var category: String?
    var iconName: String?

    init(name: String = "", category: String? = nil, iconName: String? = nil) {
        self.name = name
        self.category = category
        self.iconName = iconName
    }
}

struct RecipeOptionDefinition: Hashable {
    let fullName: String
    let abbreviation: String?

    init(_ fullName: String, abbreviation: String? = nil) {
        self.fullName = fullName
        self.abbreviation = abbreviation?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var menuLabel: String {
        guard let abbreviation, !abbreviation.isEmpty else { return fullName }
        return "\(fullName) (\(abbreviation))"
    }

    var ingredientLabel: String {
        guard let abbreviation, !abbreviation.isEmpty else { return fullName }
        return abbreviation
    }

    func matches(_ rawValue: String) -> Bool {
        let normalizedValue = RecipeOptionCatalog.normalized(rawValue)
        guard !normalizedValue.isEmpty else { return false }

        if RecipeOptionCatalog.normalized(fullName) == normalizedValue {
            return true
        }

        if let abbreviation, RecipeOptionCatalog.normalized(abbreviation) == normalizedValue {
            return true
        }

        return false
    }
}

enum RecipeOptionCatalog {
    static let stateOptions: [RecipeOptionDefinition] = [
        RecipeOptionDefinition("Ralado"),
        RecipeOptionDefinition("Desfiado"),
        RecipeOptionDefinition("Grelhado"),
        RecipeOptionDefinition("Assado"),
        RecipeOptionDefinition("Frito"),
        RecipeOptionDefinition("Cozido"),
        RecipeOptionDefinition("Refogado"),
        RecipeOptionDefinition("Picado"),
        RecipeOptionDefinition("Fatiado"),
        RecipeOptionDefinition("Em cubos"),
        RecipeOptionDefinition("Moído"),
        RecipeOptionDefinition("Triturado"),
        RecipeOptionDefinition("Amassado"),
        RecipeOptionDefinition("Derretido"),
        RecipeOptionDefinition("Temperado"),
        RecipeOptionDefinition("Gelado"),
        RecipeOptionDefinition("Congelado"),
        RecipeOptionDefinition("Inteiro"),
        RecipeOptionDefinition("Sem casca"),
        RecipeOptionDefinition("Com casca")
    ]

    static let unitOptions: [RecipeOptionDefinition] = [
        RecipeOptionDefinition("Unidade", abbreviation: "un"),
        RecipeOptionDefinition("Colher de Sopa", abbreviation: "c.s."),
        RecipeOptionDefinition("Colher de Chá", abbreviation: "c.c."),
        RecipeOptionDefinition("Gramas", abbreviation: "g"),
        RecipeOptionDefinition("Quilogramas", abbreviation: "kg"),
        RecipeOptionDefinition("Xícara", abbreviation: "xic"),
        RecipeOptionDefinition("Copo"),
        RecipeOptionDefinition("Mililitros", abbreviation: "mL"),
        RecipeOptionDefinition("Litros", abbreviation: "L"),
        RecipeOptionDefinition("Pé"),
        RecipeOptionDefinition("Pitada"),
        RecipeOptionDefinition("Lata", abbreviation: "lat"),
        RecipeOptionDefinition("Pacote", abbreviation: "pct"),
        RecipeOptionDefinition("Fatia", abbreviation: "fat"),
        RecipeOptionDefinition("Ramo", abbreviation: "ram"),
        RecipeOptionDefinition("Dente", abbreviation: "dte"),
        RecipeOptionDefinition("Caixa", abbreviation: "cx"),
        RecipeOptionDefinition("Garrafa"),
        RecipeOptionDefinition("Tablete", abbreviation: "tbl")
    ]

    static func options(for kind: RecipeCustomOptionKind) -> [RecipeOptionDefinition] {
        switch kind {
        case .state:
            return stateOptions
        case .unit:
            return unitOptions
        }
    }

    static func resolve(_ rawValue: String, for kind: RecipeCustomOptionKind) -> RecipeOptionDefinition? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return options(for: kind).first { $0.matches(trimmed) }
    }

    static func menuLabel(for rawValue: String, kind: RecipeCustomOptionKind) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return resolve(trimmed, for: kind)?.menuLabel ?? trimmed
    }

    static func ingredientLabel(for rawValue: String, kind: RecipeCustomOptionKind) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return resolve(trimmed, for: kind)?.ingredientLabel ?? trimmed
    }

    static func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}

// MARK: - Recipe

@Model
final class Recipe {
    var id: UUID = UUID()
    var name: String = ""
    var descriptionText: String = ""
    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe)
    var ingredients: [RecipeIngredient]? = []
    @Relationship(deleteRule: .cascade)
    var ingredientSections: [RecipeIngredientSection]? = []
    @Relationship(deleteRule: .cascade, inverse: \RecipeStep.recipe)
    var steps: [RecipeStep]? = []
    var imageData: Data? = nil
    @Relationship(deleteRule: .cascade, inverse: \RecipePreparationMedia.recipe)
    var preparationMedia: [RecipePreparationMedia]? = []
    var externalURLString: String = ""
    var category: String = ""
    var tags: [String] = []

    /// Categories as an array (supports comma-separated multi-category storage).
    @Transient
    var categories: [String] {
        get {
            category.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        set {
            category = newValue.joined(separator: ", ")
        }
    }

    @Transient
    var localizedCategories: [String] {
        categories.map { CategoryMutationService.localizedDisplayName(for: $0, type: .recipe) }
    }

    @Transient
    var localizedCategorySummary: String {
        localizedCategories.joined(separator: ", ")
    }
    var prepTime: Int = 0       // minutes
    var cookTime: Int = 0       // minutes
    var servings: Int = 1
    var calories: Int? = nil
    // Nutrição por porção (todos opcionais — lightweight migration safe com CloudKit).
    var proteinG: Double? = nil
    var carbsG: Double? = nil
    var fatG: Double? = nil
    var fiberG: Double? = nil
    var sugarG: Double? = nil
    var sodiumMg: Double? = nil
    /// `true` quando os macros vieram de estimativa por IA, `false` se vieram do site/usuário.
    var nutritionEstimated: Bool? = nil
    var nutritionUpdatedAt: Date? = nil
    var difficulty: Difficulty = Difficulty.easy
    var isFavorite: Bool = false
    var requiredUtensils: [String]? = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        name: String,
        descriptionText: String = "",
        ingredients: [RecipeIngredient] = [],
        steps: [RecipeStep] = [],
        imageData: Data? = nil,
        preparationMedia: [RecipePreparationMedia] = [],
        externalURLString: String = "",
        category: String = "",
        tags: [String] = [],
        prepTime: Int = 0,
        cookTime: Int = 0,
        servings: Int = 1,
        calories: Int? = nil,
        difficulty: Difficulty = .easy,
        isFavorite: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.descriptionText = descriptionText
        self.ingredients = ingredients
        self.steps = steps
        self.imageData = imageData
        self.preparationMedia = preparationMedia
        self.externalURLString = externalURLString
        self.category = category
        self.tags = tags
        self.prepTime = prepTime
        self.cookTime = cookTime
        self.servings = servings
        self.calories = calories
        self.difficulty = difficulty
        self.isFavorite = isFavorite
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Total preparation + cooking time.
    var totalTime: Int { prepTime + cookTime }

    /// Plain-text summary for AI context.
    var aiReadableDescription: String {
        var parts = [String]()
        parts.append("Receita: \(name)")
        if !descriptionText.isEmpty { parts.append("Descrição: \(descriptionText)") }
        if !externalURLString.isEmpty { parts.append("Link: \(externalURLString)") }
        parts.append("Categoria: \(category)")
        parts.append("Dificuldade: \(difficulty.rawValue)")
        parts.append("Tempo: preparo \(prepTime)min, cozimento \(cookTime)min")
        parts.append("Porções: \(servings)")
        if let cal = calories { parts.append("Calorias: \(cal) kcal") }
        if !tags.isEmpty { parts.append("Tags: \(tags.joined(separator: ", "))") }

        func formatIngredient(_ ing: RecipeIngredient) -> String {
            let labeledName = ing.preparationState.isEmpty ? ing.name : "\(ing.name) \(ing.preparationState)"
            if let qty = ing.quantity, !ing.unit.isEmpty {
                return "- \(labeledName): \(qty) \(ing.unit)"
            } else if let qty = ing.quantity {
                return "- \(labeledName): \(qty)"
            }
            return "- \(labeledName)"
        }

        let allIngredients = (ingredients ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let sections = (ingredientSections ?? []).sorted { $0.sortOrder < $1.sortOrder }

        if sections.isEmpty {
            let ingredientList = allIngredients.map(formatIngredient)
            if !ingredientList.isEmpty {
                parts.append("Ingredientes:\n\(ingredientList.joined(separator: "\n"))")
            }
        } else {
            var lines: [String] = []
            let unsectioned = allIngredients.filter { $0.sectionID == nil }
            if !unsectioned.isEmpty {
                lines.append(contentsOf: unsectioned.map(formatIngredient))
            }
            for section in sections {
                var header = "[\(section.title)]"
                if !section.subtitle.isEmpty { header += " — \(section.subtitle)" }
                lines.append(header)
                let sectionItems = allIngredients.filter { $0.sectionID == section.id }
                lines.append(contentsOf: sectionItems.map(formatIngredient))
            }
            if !lines.isEmpty {
                parts.append("Ingredientes:\n\(lines.joined(separator: "\n"))")
            }
        }

        let stepList = (steps ?? [])
            .sorted { $0.order < $1.order }
            .map { "  \($0.order). \($0.instruction)" }
        if !stepList.isEmpty {
            parts.append("Passos:\n\(stepList.joined(separator: "\n"))")
        }

        if let media = preparationMedia, !media.isEmpty {
            parts.append("Mídias de preparo: \(media.count)")
        }

        return parts.joined(separator: "\n")
    }

    func compatibility(against pantryNames: [String]) -> RecipeCompatibility? {
        let normalizedIngredients = (ingredients ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.name)
            .map(Self.normalizedIngredient)

        guard !normalizedIngredients.isEmpty else { return nil }

        let matchedIngredients = normalizedIngredients.reduce(into: 0) { total, ingredient in
            if pantryNames.contains(where: { pantry in
                pantry == ingredient || pantry.contains(ingredient) || ingredient.contains(pantry)
            }) {
                total += 1
            }
        }

        return RecipeCompatibility(matchedIngredients: matchedIngredients, totalIngredients: normalizedIngredients.count)
    }

    private static func normalizedIngredient(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}

enum RecipePreparationMediaType: String, Codable, CaseIterable {
    case photo
    case video

    var label: String {
        switch self {
        case .photo: String(localized: "Foto")
        case .video: String(localized: "Vídeo")
        }
    }
}

@Model
final class RecipePreparationMedia {
    var id: UUID = UUID()
    var mediaTypeRaw: String = RecipePreparationMediaType.photo.rawValue
    var data: Data = Data()
    var fileExtension: String = ""
    var sortOrder: Int = 0
    /// Marks media auto-saved from the original import source (downloaded video,
    /// scanned image, hero image). Used to avoid duplicates on re-import.
    var sourceOriginal: Bool = false
    var recipe: Recipe? = nil

    init(
        mediaType: RecipePreparationMediaType,
        data: Data,
        fileExtension: String = "",
        sortOrder: Int = 0,
        sourceOriginal: Bool = false
    ) {
        self.id = UUID()
        self.mediaTypeRaw = mediaType.rawValue
        self.data = data
        self.fileExtension = fileExtension
        self.sortOrder = sortOrder
        self.sourceOriginal = sourceOriginal
    }

    var mediaType: RecipePreparationMediaType {
        get { RecipePreparationMediaType(rawValue: mediaTypeRaw) ?? .photo }
        set { mediaTypeRaw = newValue.rawValue }
    }
}

struct RecipeCompatibility: Equatable {
    let matchedIngredients: Int
    let totalIngredients: Int

    var ratio: Double { Double(matchedIngredients) / Double(totalIngredients) }
    var compactText: String { "\(matchedIngredients)/\(totalIngredients)" }
    var longText: String { "\(matchedIngredients) de \(totalIngredients) ingredientes" }
}

// MARK: - Difficulty

enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case easy   = "Fácil"
    case medium = "Médio"
    case hard   = "Difícil"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .easy:   String(localized: "Fácil")
        case .medium: String(localized: "Médio")
        case .hard:   String(localized: "Difícil")
        }
    }

    var icon: String {
        switch self {
        case .easy:   "leaf"
        case .medium: "flame"
        case .hard:   "bolt.fill"
        }
    }
}

// MARK: - RecipeIngredient

@Model
final class RecipeIngredient {
    var id: UUID = UUID()
    var name: String = ""
    var quantity: Double? = nil
    var unit: String = ""
    var preparationState: String = ""
    var iconName: String? = nil
    var sortOrder: Int = 0
    /// Optional soft reference to a `RecipeIngredientSection.id` that groups this ingredient.
    /// `nil` means the ingredient lives in the implicit top (unsectioned) group.
    var sectionID: UUID? = nil
    var recipe: Recipe? = nil

    init(
        name: String,
        quantity: Double? = nil,
        unit: String = "",
        preparationState: String = "",
        iconName: String? = nil,
        sortOrder: Int = 0,
        sectionID: UUID? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.preparationState = preparationState
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.sectionID = sectionID
    }

    /// Formatted display string (e.g. "200 g" or "2 xícaras").
    var formattedQuantity: String {
        guard let qty = quantity else { return "" }
        let num = qty.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", qty)
            : String(format: "%.1f", qty)
        let resolvedUnit = RecipeOptionCatalog.ingredientLabel(for: unit, kind: .unit)
        return resolvedUnit.isEmpty ? num : "\(num) \(resolvedUnit)"
    }

    var formattedState: String {
        RecipeOptionCatalog.ingredientLabel(for: preparationState, kind: .state)
    }

    var formattedQuantityAndState: String {
        let quantityText = formattedQuantity
        let stateText = formattedState

        if quantityText.isEmpty { return stateText }
        if stateText.isEmpty { return quantityText }
        return "\(quantityText) \(stateText)"
    }
}

// MARK: - RecipeIngredientSection

/// Optional grouping for ingredients (e.g. "Para a massa", "Para o creme").
/// Ingredients reference sections via `RecipeIngredient.sectionID`. Deleting
/// a section does NOT delete its ingredients — they fall back to the implicit
/// unsectioned group.
@Model
final class RecipeIngredientSection {
    var id: UUID = UUID()
    var title: String = ""
    var subtitle: String = ""
    var sortOrder: Int = 0
    var recipe: Recipe? = nil

    init(title: String = "", subtitle: String = "", sortOrder: Int = 0, id: UUID = UUID()) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.sortOrder = sortOrder
    }
}

// MARK: - RecipeStep

@Model
final class RecipeStep {
    var id: UUID = UUID()
    var order: Int = 0
    var instruction: String = ""
    var durationMinutes: Int? = nil
    var recipe: Recipe? = nil

    init(order: Int, instruction: String, durationMinutes: Int? = nil) {
        self.id = UUID()
        self.order = order
        self.instruction = instruction
        self.durationMinutes = durationMinutes
    }
}
