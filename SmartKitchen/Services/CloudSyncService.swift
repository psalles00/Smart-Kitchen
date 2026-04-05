import Foundation
import SwiftData
import CoreData
import Observation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Observable
final class CloudSyncService: @unchecked Sendable {
    static let shared = CloudSyncService()

    // MARK: - Container management

    private static let syncEnabledKey = "iCloudSyncEnabled"
    private static let lastSyncDateKey = "iCloudLastSyncDate"
    private static let storeSplitKey = "SmartKitchen.hasCompletedStoreSplit"
    private var remoteChangeObserver: Any?
    private var deduplicationWorkItem: DispatchWorkItem?

    private(set) var container: ModelContainer
    private(set) var containerID = UUID()
    static let appSchema = Schema([
        Recipe.self,
        RecipeIngredient.self,
        RecipeStep.self,
        RecipePreparationMedia.self,
        PantryItem.self,
        GroceryItem.self,
        UtensilItem.self,
        Category.self,
        ChatMessage.self,
        AppSettings.self,
    ])

    static let cloudKitContainerID = "iCloud.com.pedrosalles.smartkitchen.sync"

    // MARK: - Store URLs

    private static var storeDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SmartKitchen", isDirectory: true)
    }

    static var privateStoreURL: URL { storeDirectory.appendingPathComponent("Private.store") }
    static var sharedStoreURL: URL { storeDirectory.appendingPathComponent("Shared.store") }

    // MARK: - Sync state

    var iCloudAvailable = false
    var isSyncing = false
    var syncEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.syncEnabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Self.syncEnabledKey) }
    }
    var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastSyncDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastSyncDateKey) }
    }
    var syncError: String?

    // MARK: - Init

    private init() {
        let syncPref = UserDefaults.standard.object(forKey: Self.syncEnabledKey) as? Bool ?? false

        #if DEBUG
        let skip = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || NSClassFromString("XCTestCase") != nil
        #else
        let skip = false
        #endif

        let cloudKitAllowed = Self.canUseCloudKitInCurrentEnvironment()
        let useCloud = syncPref && !skip && cloudKitAllowed

        // Ensure store directory exists
        try? FileManager.default.createDirectory(at: Self.storeDirectory, withIntermediateDirectories: true)

        // Migrate from legacy single store to multi-store layout (one-time)
        Self.performStoreSplitMigrationIfNeeded()

        do {
            container = try Self.makeContainer(usingCloudKit: useCloud)
        } catch {
            NSLog("CloudKit container failed, falling back to local: %@", String(describing: error))
            container = try! Self.makeContainer(usingCloudKit: false)
            UserDefaults.standard.set(false, forKey: Self.syncEnabledKey)
            syncError = "Não foi possível inicializar a sincronização com iCloud neste dispositivo."
        }

        if syncPref && !cloudKitAllowed {
            UserDefaults.standard.set(false, forKey: Self.syncEnabledKey)
            syncError = "Sincronização iCloud indisponível nesta build."
        }

        checkiCloudAvailability()

        if useCloud {
            registerForRemoteNotifications()
            setupRemoteChangeObservation()
        }
    }

    func checkiCloudAvailability() {
        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
    }

    func syncNow() {
        guard !isSyncing, syncEnabled else { return }
        isSyncing = true
        syncError = nil
        checkiCloudAvailability()

        // Trigger a save on the default context to push pending changes
        let context = ModelContext(container)
        do {
            if context.hasChanges {
                try context.save()
            }
            lastSyncDate = Date()
        } catch {
            syncError = "Erro ao sincronizar: \(error.localizedDescription)"
        }
        isSyncing = false

        // Deduplicate after every foreground sync
        scheduleDeduplication()
    }

    var statusDescription: String {
        if isSyncing { return "Sincronizando…" }
        return iCloudAvailable ? "Conectado" : "Indisponível"
    }

    // MARK: - Enable / Disable cloud sync

    @MainActor
    func enableCloudSync() async throws {
        guard !syncEnabled else { return }
        guard Self.canUseCloudKitInCurrentEnvironment() else {
            syncError = "Sincronização iCloud indisponível nesta build."
            throw NSError(domain: "CloudSync", code: 2, userInfo: [NSLocalizedDescriptionKey: syncError!])
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        checkiCloudAvailability()
        guard iCloudAvailable else {
            syncError = "iCloud não está disponível neste dispositivo. Verifique se está conectado nas Configurações do sistema."
            throw NSError(domain: "CloudSync", code: 1, userInfo: [NSLocalizedDescriptionKey: syncError!])
        }

        // 1. Create cloud container
        let newContainer: ModelContainer
        do {
            newContainer = try Self.makeContainer(usingCloudKit: true)
        } catch {
            syncError = "Não foi possível criar o container iCloud: \(error.localizedDescription)"
            throw error
        }

        // 2. Update state and keep old container alive briefly for pending writes
        let oldContainer = container
        syncEnabled = true
        container = newContainer
        containerID = UUID()
        lastSyncDate = Date()

        registerForRemoteNotifications()
        setupRemoteChangeObservation()

        // Keep old container alive so pending writes finish
        Task { @MainActor in
            _ = oldContainer
            try? await Task.sleep(for: .seconds(3))
        }

        // 4. Trigger an immediate sync/save to push newly migrated data
        syncNow()
    }

    @MainActor
    func disableCloudSync() async throws {
        guard syncEnabled else { return }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        // 1. Create local container
        let newContainer: ModelContainer
        do {
            newContainer = try Self.makeContainer(usingCloudKit: false)
        } catch {
            syncError = "Não foi possível criar o container local: \(error.localizedDescription)"
            throw error
        }

        // 2. Update state
        let oldContainer = container
        syncEnabled = false
        container = newContainer
        containerID = UUID()
        teardownRemoteChangeObservation()

        // Keep old container alive so pending writes finish
        Task { @MainActor in
            _ = oldContainer
            try? await Task.sleep(for: .seconds(3))
        }
    }

    // MARK: - Multi-store migration

    /// One-time migration from the legacy single default.store to the new multi-store layout.
    private static func performStoreSplitMigrationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: storeSplitKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: storeSplitKey) }

        // If new stores already exist, skip (fresh install or already migrated)
        if FileManager.default.fileExists(atPath: privateStoreURL.path)
            || FileManager.default.fileExists(atPath: sharedStoreURL.path) {
            return
        }

        // Try to open the old single-store container at the default location
        let oldConfig = ModelConfiguration(schema: appSchema, cloudKitDatabase: .none)
        guard let oldContainer = try? ModelContainer(for: appSchema, configurations: oldConfig) else { return }

        let oldContext = ModelContext(oldContainer)

        // Quick check if old store has data
        var fdSettings = FetchDescriptor<AppSettings>()
        fdSettings.fetchLimit = 1
        let hasData = (try? !oldContext.fetch(fdSettings).isEmpty) ?? false

        var fdRecipe = FetchDescriptor<Recipe>()
        fdRecipe.fetchLimit = 1
        let hasRecipes = (try? !oldContext.fetch(fdRecipe).isEmpty) ?? false

        guard hasData || hasRecipes else { return }

        // Create new multi-store container for migration (local only)
        guard let newContainer = try? makeContainer(usingCloudKit: false) else { return }
        let newContext = ModelContext(newContainer)

        do {
            // Copy all data — SwiftData routes each model to its correct store by schema
            for item in try oldContext.fetch(FetchDescriptor<Category>()) {
                newContext.insert(copyCategory(item))
            }
            for item in try oldContext.fetch(FetchDescriptor<PantryItem>()) {
                newContext.insert(copyPantryItem(item))
            }
            for item in try oldContext.fetch(FetchDescriptor<GroceryItem>()) {
                newContext.insert(copyGroceryItem(item))
            }
            for item in try oldContext.fetch(FetchDescriptor<UtensilItem>()) {
                newContext.insert(copyUtensilItem(item))
            }
            for recipe in try oldContext.fetch(FetchDescriptor<Recipe>()) {
                newContext.insert(copyRecipe(recipe))
            }
            for message in try oldContext.fetch(FetchDescriptor<ChatMessage>()) {
                newContext.insert(copyChatMessage(message))
            }
            for settings in try oldContext.fetch(FetchDescriptor<AppSettings>()) {
                newContext.insert(copyAppSettings(settings))
            }
            try newContext.save()
            NSLog("[CloudSync] Store split migration completed successfully")
        } catch {
            NSLog("[CloudSync] Store split migration failed: %@", String(describing: error))
        }
    }

    // MARK: - Container factory

    private static func makeContainer(usingCloudKit: Bool) throws -> ModelContainer {
        let privateSchema = Schema([AppSettings.self, ChatMessage.self])
        let sharedSchema = Schema([
            PantryItem.self, GroceryItem.self, UtensilItem.self, Category.self,
            Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipePreparationMedia.self,
        ])

        let privateConfig = ModelConfiguration(
            "Private",
            schema: privateSchema,
            url: privateStoreURL,
            cloudKitDatabase: usingCloudKit ? .private(cloudKitContainerID) : .none
        )
        let sharedConfig = ModelConfiguration(
            "Shared",
            schema: sharedSchema,
            url: sharedStoreURL,
            cloudKitDatabase: usingCloudKit ? .automatic : .none
        )

        return try ModelContainer(for: appSchema, configurations: privateConfig, sharedConfig)
    }

    private static func canUseCloudKitInCurrentEnvironment() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        // The actual CloudKit entitlement check happens when creating the
        // SwiftData container. On device builds, avoid relying on SecTask APIs
        // that are not consistently exposed to Swift across SDK targets.
        return true
        #endif
    }

    private func registerForRemoteNotifications() {
        #if os(iOS)
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        #elseif os(macOS)
        DispatchQueue.main.async {
            NSApplication.shared.registerForRemoteNotifications()
        }
        #endif
    }

    // MARK: - Remote change observation & deduplication

    private func setupRemoteChangeObservation() {
        teardownRemoteChangeObservation()
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.scheduleDeduplication()
        }
    }

    private func teardownRemoteChangeObservation() {
        if let observer = remoteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            remoteChangeObserver = nil
        }
    }

    private func scheduleDeduplication() {
        deduplicationWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performDeduplication()
        }
        deduplicationWorkItem = work
        // Debounce: CloudKit can fire many notifications in rapid succession
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Removes duplicate records across all entity types.
    /// Safe to call from any thread; creates its own context.
    func performDeduplication() {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var totalDeleted = 0
        totalDeleted += deduplicateByID(PantryItem.self, keyPath: \.id, context: context)
        totalDeleted += deduplicateByID(GroceryItem.self, keyPath: \.id, context: context)
        totalDeleted += deduplicateByID(UtensilItem.self, keyPath: \.id, context: context)
        totalDeleted += deduplicateByID(Recipe.self, keyPath: \.id, context: context)
        totalDeleted += deduplicateByID(ChatMessage.self, keyPath: \.id, context: context)
        totalDeleted += deduplicateCategories(context: context)
        totalDeleted += deduplicateAppSettings(context: context)

        guard totalDeleted > 0 else { return }

        do {
            try context.save()
            lastSyncDate = Date()
            NSLog("[CloudSync] Deduplication removed %d duplicate(s)", totalDeleted)
        } catch {
            NSLog("[CloudSync] Deduplication save failed: %@", error.localizedDescription)
        }
    }

    /// Generic dedup: groups records by their UUID `id` and deletes extras.
    private func deduplicateByID<T: PersistentModel>(
        _ type: T.Type,
        keyPath: KeyPath<T, UUID>,
        context: ModelContext
    ) -> Int {
        guard let all = try? context.fetch(FetchDescriptor<T>()) else { return 0 }

        var seen = Set<UUID>()
        var deleted = 0

        for item in all {
            let id = item[keyPath: keyPath]
            if seen.contains(id) {
                context.delete(item)
                deleted += 1
            } else {
                seen.insert(id)
            }
        }
        return deleted
    }

    /// Categories: dedup by UUID and then by (name, type) to catch
    /// duplicates created by the seeder on a different device.
    private func deduplicateCategories(context: ModelContext) -> Int {
        guard let all = try? context.fetch(FetchDescriptor<Category>()) else { return 0 }

        var deleted = 0

        // Pass 1 — dedup by UUID
        var seenIDs = Set<UUID>()
        var surviving = [Category]()
        for cat in all {
            if seenIDs.contains(cat.id) {
                context.delete(cat)
                deleted += 1
            } else {
                seenIDs.insert(cat.id)
                surviving.append(cat)
            }
        }

        // Pass 2 — dedup by (name, type); keep the one with the lowest sortOrder
        surviving.sort { $0.sortOrder < $1.sortOrder }
        var seenKeys = Set<String>()
        for cat in surviving {
            let normalized = cat.name
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
            let key = "\(cat.type.rawValue)|\(normalized)"
            if seenKeys.contains(key) {
                context.delete(cat)
                deleted += 1
            } else {
                seenKeys.insert(key)
            }
        }

        return deleted
    }

    /// Keep only one AppSettings instance (the one that looks most configured).
    private func deduplicateAppSettings(context: ModelContext) -> Int {
        guard let all = try? context.fetch(FetchDescriptor<AppSettings>()), all.count > 1 else { return 0 }

        let sorted = all.sorted {
            ($0.hasCompletedOnboarding ? 1 : 0) > ($1.hasCompletedOnboarding ? 1 : 0)
        }
        for item in sorted.dropFirst() {
            context.delete(item)
        }
        return sorted.count - 1
    }

    // MARK: - Copy helpers

    private static func copyCategory(_ source: Category) -> Category {
        let copy = Category(
            name: source.name,
            type: source.type,
            iconName: source.iconName,
            sortOrder: source.sortOrder
        )
        copy.id = source.id
        return copy
    }

    private static func copyPantryItem(_ source: PantryItem) -> PantryItem {
        let copy = PantryItem(
            name: source.name,
            descriptionText: source.descriptionText,
            imageData: source.imageData,
            category: source.category,
            quantity: source.quantity,
            unit: source.unit,
            iconName: source.iconName,
            isLinkedToGrocery: source.isLinkedToGrocery,
            expirationDate: source.expirationDate,
            defaultExpiryDays: source.defaultExpiryDays,
            sortOrder: source.sortOrder
        )
        copy.id = source.id
        copy.addedAt = source.addedAt
        return copy
    }

    private static func copyGroceryItem(_ source: GroceryItem) -> GroceryItem {
        let copy = GroceryItem(
            name: source.name,
            descriptionText: source.descriptionText,
            imageData: source.imageData,
            category: source.category,
            quantity: source.quantity,
            unit: source.unit,
            iconName: source.iconName,
            isChecked: source.isChecked,
            isFixed: source.isFixed,
            linkedPantryItemId: source.linkedPantryItemId,
            defaultExpiryDays: source.defaultExpiryDays,
            sortOrder: source.sortOrder
        )
        copy.id = source.id
        copy.addedAt = source.addedAt
        return copy
    }

    private static func copyUtensilItem(_ source: UtensilItem) -> UtensilItem {
        let copy = UtensilItem(
            name: source.name,
            descriptionText: source.descriptionText,
            imageData: source.imageData,
            category: source.category,
            iconName: source.iconName,
            sortOrder: source.sortOrder
        )
        copy.id = source.id
        copy.addedAt = source.addedAt
        return copy
    }

    private static func copyRecipe(_ source: Recipe) -> Recipe {
        let copy = Recipe(
            name: source.name,
            descriptionText: source.descriptionText,
            imageData: source.imageData,
            externalURLString: source.externalURLString,
            category: source.category,
            tags: source.tags,
            prepTime: source.prepTime,
            cookTime: source.cookTime,
            servings: source.servings,
            calories: source.calories,
            difficulty: source.difficulty,
            isFavorite: source.isFavorite
        )
        copy.id = source.id
        copy.createdAt = source.createdAt
        copy.updatedAt = source.updatedAt

        // Deep-copy ingredients
        copy.ingredients = (source.ingredients ?? []).map { ing in
            let c = RecipeIngredient(
                name: ing.name,
                quantity: ing.quantity,
                unit: ing.unit,
                preparationState: ing.preparationState,
                iconName: ing.iconName,
                sortOrder: ing.sortOrder
            )
            c.id = ing.id
            return c
        }

        // Deep-copy steps
        copy.steps = (source.steps ?? []).map { step in
            let c = RecipeStep(
                order: step.order,
                instruction: step.instruction,
                durationMinutes: step.durationMinutes
            )
            c.id = step.id
            return c
        }

        // Deep-copy preparation media
        copy.preparationMedia = (source.preparationMedia ?? []).map { media in
            let c = RecipePreparationMedia(
                mediaType: media.mediaType,
                data: media.data,
                fileExtension: media.fileExtension,
                sortOrder: media.sortOrder
            )
            c.id = media.id
            return c
        }

        return copy
    }

    private static func copyChatMessage(_ source: ChatMessage) -> ChatMessage {
        let copy = ChatMessage(
            role: source.role,
            content: source.content,
            attachedRecipeIds: source.attachedRecipeIds,
            quickActions: source.quickActions
        )
        copy.id = source.id
        copy.timestamp = source.timestamp
        return copy
    }

    private static func copyAppSettings(_ source: AppSettings) -> AppSettings {
        let copy = AppSettings()
        copy.id = source.id
        copy.pantryDetailLevel = source.pantryDetailLevel
        copy.accentColorRaw = source.accentColorRaw
        copy.appearanceMode = source.appearanceMode
        copy.recipeViewMode = source.recipeViewMode
        copy.expiringItemsLeadDays = source.expiringItemsLeadDays
        copy.recipeCompatibilityThresholdPercentValue = source.recipeCompatibilityThresholdPercentValue
        copy.openAIAPIKey = source.openAIAPIKey
        copy.hasCompletedOnboarding = source.hasCompletedOnboarding
        copy.showUtensils = source.showUtensils
        copy.recipeGalleryColumns = source.recipeGalleryColumns
        copy.pantryGroupingModeRaw = source.pantryGroupingModeRaw
        copy.groceryGroupingModeRaw = source.groceryGroupingModeRaw
        return copy
    }
}
