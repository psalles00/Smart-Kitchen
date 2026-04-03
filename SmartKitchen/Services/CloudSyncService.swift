import Foundation
import SwiftData
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
    
    private(set) var container: ModelContainer
    private(set) var containerID = UUID()
    private static let appSchema = Schema([
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

    private static let cloudKitContainerID = "iCloud.com.pedrosalles.smartkitchen.sync"

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

        // Keep old container alive so pending writes finish
        Task { @MainActor in
            _ = oldContainer
            try? await Task.sleep(for: .seconds(3))
        }
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

        // Keep old container alive so pending writes finish
        Task { @MainActor in
            _ = oldContainer
            try? await Task.sleep(for: .seconds(3))
        }
    }

    // MARK: - Helpers

    private static func makeContainer(usingCloudKit: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: appSchema,
            cloudKitDatabase: usingCloudKit ? .private(cloudKitContainerID) : .none
        )
        return try ModelContainer(for: appSchema, configurations: configuration)
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
            category: source.category,
            quantity: source.quantity,
            unit: source.unit,
            iconName: source.iconName,
            isLinkedToGrocery: source.isLinkedToGrocery,
            expirationDate: source.expirationDate,
            sortOrder: source.sortOrder
        )
        copy.id = source.id
        copy.addedAt = source.addedAt
        return copy
    }

    private static func copyGroceryItem(_ source: GroceryItem) -> GroceryItem {
        let copy = GroceryItem(
            name: source.name,
            category: source.category,
            quantity: source.quantity,
            unit: source.unit,
            iconName: source.iconName,
            isChecked: source.isChecked,
            isFixed: source.isFixed,
            linkedPantryItemId: source.linkedPantryItemId,
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
        return copy
    }
}
