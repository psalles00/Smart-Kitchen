import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class BackupManager {
    static let shared = BackupManager()

    private static let maxBackups = 7
    private static let lastBackupDateKey = "BackupManager.lastBackupDate"
    private static let lastExternalBackupDateKey = "BackupManager.lastExternalBackupDate"
    private static let autoRestoredBackupNameKey = "BackupManager.autoRestoredBackupName"

    private(set) var backups: [BackupEntry] = []
    private(set) var isWorking = false

    private let backupsDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        loadBackupList()
    }

    // MARK: - Public

    /// Perform a daily backup if one hasn't been done today.
    func performDailyBackupIfNeeded(context: ModelContext) {
        let calendar = Calendar.current
        if let last = UserDefaults.standard.object(forKey: Self.lastBackupDateKey) as? Date,
           calendar.isDateInToday(last) {
            // internal already done today; still try external below
        } else {
            Task { @MainActor in
                await createBackup(context: context)
            }
        }

        // Auto external backup (only if user enabled and configured a folder)
        let settings = (try? context.fetch(FetchDescriptor<AppSettings>()).first) ?? nil
        guard let settings, settings.autoDailyBackupEnabled, let bookmark = settings.autoBackupBookmarkData else { return }
        if let lastExt = UserDefaults.standard.object(forKey: Self.lastExternalBackupDateKey) as? Date,
           calendar.isDateInToday(lastExt) {
            return
        }
        Task { @MainActor in
            await performExternalBackup(context: context, bookmark: bookmark, includeMedia: settings.syncRecipeMediaToCloud)
        }
    }

    /// Create a full backup now.
    @discardableResult
    func createBackup(context: ModelContext) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }

        do {
            let snapshot = try AppBackupSnapshot(context: context)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let fileName = "backup-\(formatter.string(from: .now)).json"
            let fileURL = backupsDirectory.appendingPathComponent(fileName)

            try data.write(to: fileURL, options: .atomic)

            UserDefaults.standard.set(Date.now, forKey: Self.lastBackupDateKey)

            pruneOldBackups()
            loadBackupList()
            return true
        } catch {
            #if DEBUG
            print("[BackupManager] Failed to create backup: \(error)")
            #endif
            return false
        }
    }

    /// Restore from a specific backup entry.
    func restore(from entry: BackupEntry, context: ModelContext) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }

        do {
            let data = try Data(contentsOf: entry.url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(AppBackupSnapshot.self, from: data)
            try snapshot.restore(into: context)
            return true
        } catch {
            #if DEBUG
            print("[BackupManager] Failed to restore backup: \(error)")
            #endif
            return false
        }
    }

    /// One-time emergency recovery path used after catastrophic store issues.
    ///
    /// Restores the latest internal backup only when the current store has no
    /// visible list/recipe data and the backup clearly contains user content.
    /// Once a specific backup file has been auto-restored, it will not be
    /// auto-restored again on future launches.
    @discardableResult
    func restoreLatestBackupIfCurrentStoreNeedsRecovery(context: ModelContext) -> Bool {
        loadBackupList()
        guard let latest = backups.first else { return false }
        guard UserDefaults.standard.string(forKey: Self.autoRestoredBackupNameKey) != latest.url.lastPathComponent else {
            return false
        }

        do {
            let snapshot = try decodeSnapshot(at: latest.url)
            guard shouldAutoRestore(snapshot: snapshot, into: context) else { return false }

            try snapshot.restore(into: context)
            UserDefaults.standard.set(latest.url.lastPathComponent, forKey: Self.autoRestoredBackupNameKey)
            NSLog("[BackupManager] Auto-restored backup %@", latest.url.lastPathComponent)
            return true
        } catch {
            NSLog("[BackupManager] Auto-restore failed: %@", String(describing: error))
            return false
        }
    }

    /// Delete a specific backup.
    func delete(_ entry: BackupEntry) {
        try? FileManager.default.removeItem(at: entry.url)
        loadBackupList()
    }

    /// Delete all internal backups and reset recovery markers.
    func deleteAllBackups() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []

        for url in files {
            try? fm.removeItem(at: url)
        }

        UserDefaults.standard.removeObject(forKey: Self.lastBackupDateKey)
        UserDefaults.standard.removeObject(forKey: Self.autoRestoredBackupNameKey)
        loadBackupList()
    }

    /// Export a backup entry as zip Data for file exporter.
    func exportData(from entry: BackupEntry) throws -> Data {
        let jsonData = try Data(contentsOf: entry.url)
        return try SimpleZipArchive.archive(fileName: "smart-kitchen-backup.json", data: jsonData)
    }

    /// Export current data as zip Data.
    func exportCurrentData(context: ModelContext) throws -> Data {
        let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first
        let includeMedia = settings?.syncRecipeMediaToCloud ?? true
        return try BackupSnapshotV2.makeArchive(context: context, includeMedia: includeMedia)
    }

    /// Import a zip backup from external file. Accepts both v1 (single
    /// `smart-kitchen-backup.json`) and v2 (multi-file with `manifest.json`).
    func importBackup(from zipData: Data, context: ModelContext) throws {
        let jsonData: Data
        if BackupSnapshotV2.isV2Archive(zipData) {
            jsonData = try BackupSnapshotV2.extractCanonicalJSON(from: zipData)
        } else {
            jsonData = try SimpleZipArchive.extractFile(named: "smart-kitchen-backup.json", from: zipData)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(AppBackupSnapshot.self, from: jsonData)
        try snapshot.restore(into: context)
    }

    // MARK: - External (auto) backups

    /// Save a v2 backup file into the user-chosen folder using a security-scoped
    /// bookmark. Returns true on success.
    @discardableResult
    func performExternalBackup(context: ModelContext, bookmark: Data, includeMedia: Bool) async -> Bool {
        do {
            var isStale = false
            #if os(macOS)
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            #else
            let url = try URL(resolvingBookmarkData: bookmark, relativeTo: nil, bookmarkDataIsStale: &isStale)
            #endif
            guard !isStale else {
                NSLog("[BackupManager] External backup bookmark is stale; user must reselect folder")
                return false
            }

            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }

            let zipData = try BackupSnapshotV2.makeArchive(context: context, includeMedia: includeMedia)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let fileName = "SmartKitchen-Backup-\(formatter.string(from: .now)).zip"
            let target = url.appendingPathComponent(fileName)

            // Replace same-day file if exists
            try? FileManager.default.removeItem(at: target)
            try zipData.write(to: target, options: .atomic)

            UserDefaults.standard.set(Date.now, forKey: Self.lastExternalBackupDateKey)
            pruneOldExternalBackups(in: url)
            return true
        } catch {
            NSLog("[BackupManager] External backup failed: %@", String(describing: error))
            return false
        }
    }

    private func pruneOldExternalBackups(in folder: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else { return }
        let backups = files
            .filter { $0.lastPathComponent.hasPrefix("SmartKitchen-Backup-") && $0.pathExtension == "zip" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return l > r
            }
        if backups.count > Self.maxBackups {
            for url in backups[Self.maxBackups...] {
                try? fm.removeItem(at: url)
            }
        }
    }

    /// Reload the list from disk.
    func loadBackupList() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: .skipsHiddenFiles) else {
            backups = []
            return
        }

        backups = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> BackupEntry? in
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                let date = values?.creationDate ?? (try? fm.attributesOfItem(atPath: url.path)[.creationDate] as? Date) ?? .distantPast
                let size = values?.fileSize ?? 0
                return BackupEntry(url: url, date: date, sizeBytes: size)
            }
            .sorted { $0.date > $1.date }
    }

    private func decodeSnapshot(at url: URL) throws -> AppBackupSnapshot {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppBackupSnapshot.self, from: data)
    }

    private func shouldAutoRestore(snapshot: AppBackupSnapshot, into context: ModelContext) -> Bool {
        let currentVisibleCount =
            count(FetchDescriptor<UnifiedItem>(), in: context) +
            count(FetchDescriptor<Recipe>(), in: context) +
            count(FetchDescriptor<PantryItem>(), in: context) +
            count(FetchDescriptor<GroceryItem>(), in: context) +
            count(FetchDescriptor<UtensilItem>(), in: context)

        guard currentVisibleCount == 0 else { return false }

        let backupVisibleCount = snapshot.unifiedItems.count + snapshot.recipes.count
        guard backupVisibleCount > 0 else { return false }

        return true
    }

    private func count<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, in context: ModelContext) -> Int {
        (try? context.fetch(descriptor).count) ?? 0
    }

    // MARK: - Private

    private func pruneOldBackups() {
        let fm = FileManager.default
        guard var files = try? fm.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else { return }

        files = files.filter { $0.pathExtension == "json" }
        files.sort { url1, url2 in
            let d1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let d2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return d1 > d2
        }

        if files.count > Self.maxBackups {
            for url in files[Self.maxBackups...] {
                try? fm.removeItem(at: url)
            }
        }
    }
}

// MARK: - BackupEntry

struct BackupEntry: Identifiable {
    let id = UUID()
    let url: URL
    let date: Date
    let sizeBytes: Int

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }

    var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Hoje"
        } else if calendar.isDateInYesterday(date) {
            return "Ontem"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, d MMM"
            formatter.locale = AppLocalization.current().formattingLocale
            return formatter.string(from: date).localizedCapitalized
        }
    }
}

// MARK: - Shared Backup Snapshot (moved from SettingsView to be reusable)

struct AppBackupSnapshot: Codable {
    let exportedAt: Date
    let appSettings: [AppSettingsRecord]
    let categories: [CategoryRecord]
    let deletedDefaultCategories: [DeletedDefaultCategoryRecord]
    let unifiedItems: [UnifiedItemRecord]
    let recipes: [RecipeRecord]
    let recipeIngredientSections: [RecipeIngredientSectionRecord]
    let recipeIngredients: [RecipeIngredientRecord]
    let recipeSteps: [RecipeStepRecord]
    let recipePreparationMedia: [RecipePreparationMediaRecord]
    let chatMessages: [ChatMessageRecord]

    // Legacy keys for backward-compat decoding
    private enum CodingKeys: String, CodingKey {
        case exportedAt, appSettings, categories, deletedDefaultCategories
        case unifiedItems
        case pantryItems, groceryItems, utensilItems // legacy
        case recipes, recipeIngredientSections, recipeIngredients, recipeSteps, recipePreparationMedia, chatMessages
    }

    init(context: ModelContext) throws {
        exportedAt = .now
        appSettings = try context.fetch(FetchDescriptor<AppSettings>()).map(AppSettingsRecord.init)
        categories = try context.fetch(FetchDescriptor<Category>()).map(CategoryRecord.init)
        deletedDefaultCategories = try context.fetch(FetchDescriptor<DeletedDefaultCategory>()).map(DeletedDefaultCategoryRecord.init)
        unifiedItems = try context.fetch(FetchDescriptor<UnifiedItem>()).map(UnifiedItemRecord.init)

        let recipeList = try context.fetch(FetchDescriptor<Recipe>())
        recipes = recipeList.map(RecipeRecord.init)
        recipeIngredientSections = recipeList
            .flatMap { $0.ingredientSections ?? [] }
            .map(RecipeIngredientSectionRecord.init)
        recipeIngredients = recipeList
            .flatMap { $0.ingredients ?? [] }
            .map(RecipeIngredientRecord.init)
        recipeSteps = recipeList
            .flatMap { $0.steps ?? [] }
            .map(RecipeStepRecord.init)
        recipePreparationMedia = recipeList
            .flatMap { $0.preparationMedia ?? [] }
            .map(RecipePreparationMediaRecord.init)

        chatMessages = try context.fetch(FetchDescriptor<ChatMessage>()).map(ChatMessageRecord.init)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(appSettings, forKey: .appSettings)
        try container.encode(categories, forKey: .categories)
        try container.encode(deletedDefaultCategories, forKey: .deletedDefaultCategories)
        try container.encode(unifiedItems, forKey: .unifiedItems)
        try container.encode(recipes, forKey: .recipes)
        try container.encode(recipeIngredientSections, forKey: .recipeIngredientSections)
        try container.encode(recipeIngredients, forKey: .recipeIngredients)
        try container.encode(recipeSteps, forKey: .recipeSteps)
        try container.encode(recipePreparationMedia, forKey: .recipePreparationMedia)
        try container.encode(chatMessages, forKey: .chatMessages)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        appSettings = try container.decode([AppSettingsRecord].self, forKey: .appSettings)
        categories = try container.decode([CategoryRecord].self, forKey: .categories)
        deletedDefaultCategories = try container.decodeIfPresent([DeletedDefaultCategoryRecord].self, forKey: .deletedDefaultCategories) ?? []

        // Try new unified format first, fall back to legacy
        if let unified = try? container.decode([UnifiedItemRecord].self, forKey: .unifiedItems) {
            unifiedItems = unified
        } else {
            // Legacy: convert from old 3-array format
            var converted: [UnifiedItemRecord] = []
            let pantry = try container.decodeIfPresent([LegacyPantryItemRecord].self, forKey: .pantryItems) ?? []
            let grocery = try container.decodeIfPresent([LegacyGroceryItemRecord].self, forKey: .groceryItems) ?? []
            let utensils = try container.decodeIfPresent([LegacyUtensilItemRecord].self, forKey: .utensilItems) ?? []

            for p in pantry {
                converted.append(UnifiedItemRecord(
                    id: p.id, name: p.name, descriptionText: p.descriptionText, imageData: p.imageData,
                    category: p.category, quantity: p.quantity, unit: p.unit, iconName: p.iconName,
                    isPantry: true, isGrocery: false, isUtensil: false,
                    pantrySortOrder: p.sortOrder, grocerySortOrder: 0, utensilSortOrder: 0,
                    isLinkedToGrocery: p.isLinkedToGrocery, expirationDate: p.expirationDate,
                    defaultExpiryDays: p.defaultExpiryDays,
                    isChecked: false, isFixed: false, linkedPantryItemId: nil, addedAt: p.addedAt
                ))
            }
            for g in grocery {
                converted.append(UnifiedItemRecord(
                    id: g.id, name: g.name, descriptionText: g.descriptionText, imageData: g.imageData,
                    category: g.category, quantity: g.quantity, unit: g.unit, iconName: g.iconName,
                    isPantry: false, isGrocery: true, isUtensil: false,
                    pantrySortOrder: 0, grocerySortOrder: g.sortOrder, utensilSortOrder: 0,
                    isLinkedToGrocery: false, expirationDate: nil,
                    defaultExpiryDays: g.defaultExpiryDays,
                    isChecked: g.isChecked, isFixed: g.isFixed, linkedPantryItemId: g.linkedPantryItemId,
                    addedAt: g.addedAt
                ))
            }
            for u in utensils {
                converted.append(UnifiedItemRecord(
                    id: u.id, name: u.name, descriptionText: u.descriptionText, imageData: u.imageData,
                    category: u.category, quantity: nil, unit: nil, iconName: u.iconName,
                    isPantry: false, isGrocery: false, isUtensil: true,
                    pantrySortOrder: 0, grocerySortOrder: 0, utensilSortOrder: u.sortOrder,
                    isLinkedToGrocery: false, expirationDate: nil, defaultExpiryDays: nil,
                    isChecked: false, isFixed: false, linkedPantryItemId: nil, addedAt: u.addedAt
                ))
            }
            unifiedItems = converted
        }

        recipes = try container.decode([RecipeRecord].self, forKey: .recipes)
        recipeIngredientSections = try container.decodeIfPresent([RecipeIngredientSectionRecord].self, forKey: .recipeIngredientSections) ?? []
        recipeIngredients = try container.decode([RecipeIngredientRecord].self, forKey: .recipeIngredients)
        recipeSteps = try container.decode([RecipeStepRecord].self, forKey: .recipeSteps)
        recipePreparationMedia = try container.decodeIfPresent([RecipePreparationMediaRecord].self, forKey: .recipePreparationMedia) ?? []
        chatMessages = try container.decode([ChatMessageRecord].self, forKey: .chatMessages)
    }

    func restore(into context: ModelContext) throws {
        for recipe in try context.fetch(FetchDescriptor<Recipe>()) {
            context.delete(recipe)
        }
        try context.delete(model: UnifiedItem.self)
        try context.delete(model: PantryItem.self)
        try context.delete(model: GroceryItem.self)
        try context.delete(model: UtensilItem.self)
        try context.delete(model: Category.self)
        try context.delete(model: DeletedDefaultCategory.self)
        try context.delete(model: ChatMessage.self)
        try context.delete(model: AppSettings.self)

        for record in appSettings {
            let settings = AppSettings()
            settings.id = record.id
            settings.pantryDetailLevel = record.pantryDetailLevel
            settings.accentColorRaw = record.accentColorRaw
            settings.appearanceMode = record.appearanceMode
            settings.recipeViewMode = record.recipeViewMode
            settings.expiringItemsLeadDays = record.expiringItemsLeadDays
            settings.recipeCompatibilityThresholdPercentValue = record.recipeCompatibilityThresholdPercent
            settings.openAIAPIKey = record.openAIAPIKey
            settings.hasCompletedOnboarding = record.hasCompletedOnboarding
            settings.showUtensils = record.showUtensils
            context.insert(settings)
        }

        for record in categories {
            let category = Category(
                name: record.name,
                type: record.type,
                iconName: record.iconName,
                sortOrder: record.sortOrder
            )
            category.id = record.id
            context.insert(category)
        }

        for record in deletedDefaultCategories {
            let deletedDefault = DeletedDefaultCategory(name: record.name, type: record.type)
            deletedDefault.id = record.id
            context.insert(deletedDefault)
        }

        for record in unifiedItems {
            let item = UnifiedItem(
                name: record.name,
                descriptionText: record.descriptionText,
                imageData: record.imageData,
                category: record.category,
                quantity: record.quantity,
                unit: record.unit,
                iconName: record.iconName,
                isPantry: record.isPantry,
                isGrocery: record.isGrocery,
                isUtensil: record.isUtensil,
                pantrySortOrder: record.pantrySortOrder,
                grocerySortOrder: record.grocerySortOrder,
                utensilSortOrder: record.utensilSortOrder,
                isLinkedToGrocery: record.isLinkedToGrocery,
                expirationDate: record.expirationDate,
                defaultExpiryDays: record.defaultExpiryDays,
                isChecked: record.isChecked,
                isFixed: record.isFixed,
                linkedPantryItemId: record.linkedPantryItemId
            )
            item.id = record.id
            item.addedAt = record.addedAt
            context.insert(item)
        }

        var recipesByID: [UUID: Recipe] = [:]
        for record in recipes {
            let recipe = Recipe(
                name: record.name,
                descriptionText: record.descriptionText,
                imageData: record.imageData,
                externalURLString: record.externalURLString,
                category: record.category,
                tags: record.tags,
                prepTime: record.prepTime,
                cookTime: record.cookTime,
                servings: record.servings,
                calories: record.calories,
                difficulty: record.difficulty,
                isFavorite: record.isFavorite
            )
            recipe.id = record.id
            recipe.createdAt = record.createdAt
            recipe.updatedAt = record.updatedAt
            context.insert(recipe)
            recipesByID[record.id] = recipe
        }

        for record in recipeIngredientSections {
            guard let recipe = recipesByID[record.recipeID] else { continue }
            let section = RecipeIngredientSection(
                title: record.title,
                subtitle: record.subtitle,
                sortOrder: record.sortOrder,
                id: record.id
            )
            section.recipe = recipe
            context.insert(section)
        }

        for record in recipeIngredients {
            guard let recipe = recipesByID[record.recipeID] else { continue }
            let ingredient = RecipeIngredient(
                name: record.name,
                quantity: record.quantity,
                unit: record.unit,
                preparationState: record.preparationState,
                iconName: record.iconName,
                sortOrder: record.sortOrder,
                sectionID: record.sectionID
            )
            ingredient.id = record.id
            ingredient.recipe = recipe
            context.insert(ingredient)
        }

        for record in recipeSteps {
            guard let recipe = recipesByID[record.recipeID] else { continue }
            let step = RecipeStep(order: record.order, instruction: record.instruction, durationMinutes: record.durationMinutes)
            step.id = record.id
            step.recipe = recipe
            context.insert(step)
        }

        for record in recipePreparationMedia {
            guard let recipe = recipesByID[record.recipeID] else { continue }
            let media = RecipePreparationMedia(
                mediaType: record.mediaType,
                data: record.data,
                fileExtension: record.fileExtension,
                sortOrder: record.sortOrder
            )
            media.id = record.id
            media.recipe = recipe
            context.insert(media)
        }

        for record in chatMessages {
            let message = ChatMessage(
                role: record.role,
                content: record.content,
                attachedRecipeIds: record.attachedRecipeIds,
                quickActions: record.quickActions
            )
            message.id = record.id
            message.timestamp = record.timestamp
            context.insert(message)
        }

        try context.save()
    }
}

// MARK: - Codable Records

struct AppSettingsRecord: Codable {
    let id: UUID
    let pantryDetailLevel: PantryDetailLevel
    let accentColorRaw: String
    let appearanceMode: AppearanceMode
    let recipeViewMode: RecipeViewMode
    let expiringItemsLeadDays: Int
    let recipeCompatibilityThresholdPercent: Int
    let openAIAPIKey: String
    let hasCompletedOnboarding: Bool
    let showUtensils: Bool

    init(_ settings: AppSettings) {
        id = settings.id
        pantryDetailLevel = settings.pantryDetailLevel
        accentColorRaw = settings.accentColorRaw
        appearanceMode = settings.appearanceMode
        recipeViewMode = settings.recipeViewMode
        expiringItemsLeadDays = settings.expiringItemsLeadDays
        recipeCompatibilityThresholdPercent = settings.recipeCompatibilityThresholdPercent
        openAIAPIKey = settings.openAIAPIKey
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        showUtensils = settings.showUtensils
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        pantryDetailLevel = try container.decode(PantryDetailLevel.self, forKey: .pantryDetailLevel)
        accentColorRaw = try container.decode(String.self, forKey: .accentColorRaw)
        appearanceMode = try container.decode(AppearanceMode.self, forKey: .appearanceMode)
        recipeViewMode = try container.decode(RecipeViewMode.self, forKey: .recipeViewMode)
        expiringItemsLeadDays = try container.decodeIfPresent(Int.self, forKey: .expiringItemsLeadDays) ?? 30
        recipeCompatibilityThresholdPercent = try container.decodeIfPresent(Int.self, forKey: .recipeCompatibilityThresholdPercent) ?? 80
        openAIAPIKey = try container.decode(String.self, forKey: .openAIAPIKey)
        hasCompletedOnboarding = try container.decode(Bool.self, forKey: .hasCompletedOnboarding)
        showUtensils = try container.decodeIfPresent(Bool.self, forKey: .showUtensils) ?? false
    }
}

struct CategoryRecord: Codable {
    let id: UUID
    let name: String
    let type: CategoryType
    let iconName: String?
    let sortOrder: Int

    init(_ category: Category) {
        id = category.id
        name = category.name
        type = category.type
        iconName = category.iconName
        sortOrder = category.sortOrder
    }
}

struct DeletedDefaultCategoryRecord: Codable {
    let id: UUID
    let name: String
    let type: CategoryType

    init(_ category: DeletedDefaultCategory) {
        id = category.id
        name = category.name
        type = category.type
    }
}

struct UnifiedItemRecord: Codable {
    let id: UUID
    let name: String
    let descriptionText: String
    let imageData: Data?
    let category: String
    let quantity: Double?
    let unit: String?
    let iconName: String?
    let isPantry: Bool
    let isGrocery: Bool
    let isUtensil: Bool
    let pantrySortOrder: Int
    let grocerySortOrder: Int
    let utensilSortOrder: Int
    let isLinkedToGrocery: Bool
    let expirationDate: Date?
    let defaultExpiryDays: Int?
    let isChecked: Bool
    let isFixed: Bool
    let linkedPantryItemId: UUID?
    let addedAt: Date

    init(_ item: UnifiedItem) {
        id = item.id
        name = item.name
        descriptionText = item.descriptionText
        imageData = item.imageData
        category = item.category
        quantity = item.quantity
        unit = item.unit
        iconName = item.iconName
        isPantry = item.isPantry
        isGrocery = item.isGrocery
        isUtensil = item.isUtensil
        pantrySortOrder = item.pantrySortOrder
        grocerySortOrder = item.grocerySortOrder
        utensilSortOrder = item.utensilSortOrder
        isLinkedToGrocery = item.isLinkedToGrocery
        expirationDate = item.expirationDate
        defaultExpiryDays = item.defaultExpiryDays
        isChecked = item.isChecked
        isFixed = item.isFixed
        linkedPantryItemId = item.linkedPantryItemId
        addedAt = item.addedAt
    }

    init(
        id: UUID, name: String, descriptionText: String, imageData: Data?,
        category: String, quantity: Double?, unit: String?, iconName: String?,
        isPantry: Bool, isGrocery: Bool, isUtensil: Bool,
        pantrySortOrder: Int, grocerySortOrder: Int, utensilSortOrder: Int,
        isLinkedToGrocery: Bool, expirationDate: Date?, defaultExpiryDays: Int?,
        isChecked: Bool, isFixed: Bool, linkedPantryItemId: UUID?, addedAt: Date
    ) {
        self.id = id; self.name = name; self.descriptionText = descriptionText
        self.imageData = imageData; self.category = category; self.quantity = quantity
        self.unit = unit; self.iconName = iconName
        self.isPantry = isPantry; self.isGrocery = isGrocery; self.isUtensil = isUtensil
        self.pantrySortOrder = pantrySortOrder; self.grocerySortOrder = grocerySortOrder
        self.utensilSortOrder = utensilSortOrder
        self.isLinkedToGrocery = isLinkedToGrocery; self.expirationDate = expirationDate
        self.defaultExpiryDays = defaultExpiryDays
        self.isChecked = isChecked; self.isFixed = isFixed
        self.linkedPantryItemId = linkedPantryItemId; self.addedAt = addedAt
    }
}

// MARK: - Legacy Records (for backward-compat backup decoding only)

struct LegacyPantryItemRecord: Codable {
    let id: UUID
    let name: String
    let descriptionText: String
    let imageData: Data?
    let category: String
    let quantity: Double?
    let unit: String?
    let iconName: String?
    let isLinkedToGrocery: Bool
    let expirationDate: Date?
    let defaultExpiryDays: Int?
    let sortOrder: Int
    let addedAt: Date

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        descriptionText = try container.decodeIfPresent(String.self, forKey: .descriptionText) ?? ""
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        category = try container.decode(String.self, forKey: .category)
        quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        isLinkedToGrocery = try container.decode(Bool.self, forKey: .isLinkedToGrocery)
        expirationDate = try container.decodeIfPresent(Date.self, forKey: .expirationDate)
        defaultExpiryDays = try container.decodeIfPresent(Int.self, forKey: .defaultExpiryDays)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        addedAt = try container.decode(Date.self, forKey: .addedAt)
    }
}

struct LegacyGroceryItemRecord: Codable {
    let id: UUID
    let name: String
    let descriptionText: String
    let imageData: Data?
    let category: String
    let quantity: Double?
    let unit: String?
    let iconName: String?
    let isChecked: Bool
    let isFixed: Bool
    let linkedPantryItemId: UUID?
    let defaultExpiryDays: Int?
    let sortOrder: Int
    let addedAt: Date

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        descriptionText = try container.decodeIfPresent(String.self, forKey: .descriptionText) ?? ""
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        category = try container.decode(String.self, forKey: .category)
        quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        isChecked = try container.decodeIfPresent(Bool.self, forKey: .isChecked) ?? false
        isFixed = try container.decodeIfPresent(Bool.self, forKey: .isFixed) ?? false
        linkedPantryItemId = try container.decodeIfPresent(UUID.self, forKey: .linkedPantryItemId)
        defaultExpiryDays = try container.decodeIfPresent(Int.self, forKey: .defaultExpiryDays)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        addedAt = try container.decode(Date.self, forKey: .addedAt)
    }
}

struct LegacyUtensilItemRecord: Codable {
    let id: UUID
    let name: String
    let descriptionText: String
    let imageData: Data?
    let category: String
    let iconName: String?
    let sortOrder: Int
    let addedAt: Date
}

struct RecipeRecord: Codable {
    let id: UUID
    let name: String
    let descriptionText: String
    let imageData: Data?
    let category: String
    let tags: [String]
    let prepTime: Int
    let cookTime: Int
    let servings: Int
    let calories: Int?
    let difficulty: Difficulty
    let isFavorite: Bool
    let externalURLString: String
    let createdAt: Date
    let updatedAt: Date

    init(_ recipe: Recipe) {
        id = recipe.id
        name = recipe.name
        descriptionText = recipe.descriptionText
        imageData = recipe.imageData
        category = recipe.category
        tags = recipe.tags
        prepTime = recipe.prepTime
        cookTime = recipe.cookTime
        servings = recipe.servings
        calories = recipe.calories
        difficulty = recipe.difficulty
        isFavorite = recipe.isFavorite
        externalURLString = recipe.externalURLString
        createdAt = recipe.createdAt
        updatedAt = recipe.updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        descriptionText = try container.decode(String.self, forKey: .descriptionText)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        category = try container.decode(String.self, forKey: .category)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        prepTime = try container.decodeIfPresent(Int.self, forKey: .prepTime) ?? 0
        cookTime = try container.decodeIfPresent(Int.self, forKey: .cookTime) ?? 0
        servings = try container.decodeIfPresent(Int.self, forKey: .servings) ?? 1
        calories = try container.decodeIfPresent(Int.self, forKey: .calories)
        difficulty = try container.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .easy
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        externalURLString = try container.decodeIfPresent(String.self, forKey: .externalURLString) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct RecipePreparationMediaRecord: Codable {
    let id: UUID
    let recipeID: UUID
    let mediaType: RecipePreparationMediaType
    let data: Data
    let fileExtension: String
    let sortOrder: Int

    init(_ media: RecipePreparationMedia) {
        id = media.id
        recipeID = media.recipe?.id ?? UUID()
        mediaType = media.mediaType
        data = media.data
        fileExtension = media.fileExtension
        sortOrder = media.sortOrder
    }
}

struct RecipeIngredientSectionRecord: Codable {
    let id: UUID
    let recipeID: UUID
    let title: String
    let subtitle: String
    let sortOrder: Int

    init(_ section: RecipeIngredientSection) {
        id = section.id
        recipeID = section.recipe?.id ?? UUID()
        title = section.title
        subtitle = section.subtitle
        sortOrder = section.sortOrder
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        recipeID = try container.decode(UUID.self, forKey: .recipeID)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
}

struct RecipeIngredientRecord: Codable {
    let id: UUID
    let recipeID: UUID
    let name: String
    let quantity: Double?
    let unit: String
    let preparationState: String
    let iconName: String?
    let sortOrder: Int
    let sectionID: UUID?

    init(_ ingredient: RecipeIngredient) {
        id = ingredient.id
        recipeID = ingredient.recipe?.id ?? UUID()
        name = ingredient.name
        quantity = ingredient.quantity
        unit = ingredient.unit
        preparationState = ingredient.preparationState
        iconName = ingredient.iconName
        sortOrder = ingredient.sortOrder
        sectionID = ingredient.sectionID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        recipeID = try container.decode(UUID.self, forKey: .recipeID)
        name = try container.decode(String.self, forKey: .name)
        quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        preparationState = try container.decodeIfPresent(String.self, forKey: .preparationState) ?? ""
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        sectionID = try container.decodeIfPresent(UUID.self, forKey: .sectionID)
    }
}

struct RecipeStepRecord: Codable {
    let id: UUID
    let recipeID: UUID
    let order: Int
    let instruction: String
    let durationMinutes: Int?

    init(_ step: RecipeStep) {
        id = step.id
        recipeID = step.recipe?.id ?? UUID()
        order = step.order
        instruction = step.instruction
        durationMinutes = step.durationMinutes
    }
}

struct ChatMessageRecord: Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    let attachedRecipeIds: [UUID]
    let quickActions: [QuickAction]

    init(_ message: ChatMessage) {
        id = message.id
        role = message.role
        content = message.content
        timestamp = message.timestamp
        attachedRecipeIds = message.attachedRecipeIds
        quickActions = message.quickActions
    }
}

// MARK: - Simple Zip Archive (reused from original)

enum SimpleZipArchive {
    static func archive(fileName: String, data: Data) throws -> Data {
        guard let nameData = fileName.data(using: .utf8) else {
            throw BackupTransferError.invalidFileName
        }
        guard nameData.count <= Int(UInt16.max), data.count <= Int(UInt32.max) else {
            throw BackupTransferError.payloadTooLarge
        }

        let crc = CRC32.checksum(of: data)
        var archive = Data()

        archive.appendUInt32(0x04034B50)
        archive.appendUInt16(20)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt32(crc)
        archive.appendUInt32(UInt32(data.count))
        archive.appendUInt32(UInt32(data.count))
        archive.appendUInt16(UInt16(nameData.count))
        archive.appendUInt16(0)
        archive.append(nameData)
        archive.append(data)

        let centralDirectoryOffset = UInt32(archive.count)

        archive.appendUInt32(0x02014B50)
        archive.appendUInt16(20)
        archive.appendUInt16(20)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt32(crc)
        archive.appendUInt32(UInt32(data.count))
        archive.appendUInt32(UInt32(data.count))
        archive.appendUInt16(UInt16(nameData.count))
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt32(0)
        archive.appendUInt32(0)
        archive.append(nameData)

        let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset

        archive.appendUInt32(0x06054B50)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(1)
        archive.appendUInt16(1)
        archive.appendUInt32(centralDirectorySize)
        archive.appendUInt32(centralDirectoryOffset)
        archive.appendUInt16(0)

        return archive
    }

    static func extractFile(named fileName: String, from archive: Data) throws -> Data {
        var offset = 0

        while offset + 30 <= archive.count {
            let signature = try archive.readUInt32(at: offset)

            if signature == 0x04034B50 {
                let compressionMethod = try archive.readUInt16(at: offset + 8)
                guard compressionMethod == 0 else {
                    throw BackupTransferError.unsupportedZipCompression
                }

                let payloadSize = Int(try archive.readUInt32(at: offset + 18))
                let nameLength = Int(try archive.readUInt16(at: offset + 26))
                let extraLength = Int(try archive.readUInt16(at: offset + 28))
                let nameStart = offset + 30
                let nameEnd = nameStart + nameLength
                let dataStart = nameEnd + extraLength
                let dataEnd = dataStart + payloadSize

                guard dataEnd <= archive.count else {
                    throw BackupTransferError.invalidArchive
                }

                let entryNameData = archive.subdata(in: nameStart..<nameEnd)
                let entryName = String(data: entryNameData, encoding: .utf8)

                if entryName == fileName {
                    return archive.subdata(in: dataStart..<dataEnd)
                }

                offset = dataEnd
            } else if signature == 0x02014B50 || signature == 0x06054B50 {
                break
            } else {
                throw BackupTransferError.invalidArchive
            }
        }

        throw BackupTransferError.missingBackupPayload
    }
}

enum BackupTransferError: LocalizedError {
    case invalidFileName
    case payloadTooLarge
    case invalidArchive
    case unsupportedZipCompression
    case missingBackupPayload

    var errorDescription: String? {
        switch self {
        case .invalidFileName:
            String(localized: "Nome do arquivo de backup inválido.")
        case .payloadTooLarge:
            String(localized: "O backup é grande demais para ser compactado neste formato.")
        case .invalidArchive:
            String(localized: "O arquivo .zip selecionado é inválido.")
        case .unsupportedZipCompression:
            String(localized: "O arquivo .zip usa um tipo de compactação não suportado por este app.")
        case .missingBackupPayload:
            String(localized: "O arquivo .zip não contém um backup válido do Savoria.")
        }
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = 0xEDB88320 ^ (crc >> 1)
            } else {
                crc >>= 1
            }
        }
        return crc
    }

    static func checksum(of data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { buffer in
            append(buffer.bindMemory(to: UInt8.self))
        }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { buffer in
            append(buffer.bindMemory(to: UInt8.self))
        }
    }

    func readUInt16(at offset: Int) throws -> UInt16 {
        guard offset + 2 <= count else {
            throw BackupTransferError.invalidArchive
        }
        return subdata(in: offset..<(offset + 2)).withUnsafeBytes {
            UInt16(littleEndian: $0.load(as: UInt16.self))
        }
    }

    func readUInt32(at offset: Int) throws -> UInt32 {
        guard offset + 4 <= count else {
            throw BackupTransferError.invalidArchive
        }
        return subdata(in: offset..<(offset + 4)).withUnsafeBytes {
            UInt32(littleEndian: $0.load(as: UInt32.self))
        }
    }
}
