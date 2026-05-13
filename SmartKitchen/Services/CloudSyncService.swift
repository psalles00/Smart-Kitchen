import Foundation
import SwiftData
import CoreData
import CloudKit
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
    private static let storeRecoveryAttemptedKey = "SmartKitchen.storeRecoveryAttempted"
    private var remoteChangeObserver: Any?
    private var deduplicationWorkItem: DispatchWorkItem?
    private var shouldActivateCloudOnLaunch = false
    private var hasAttemptedCloudActivationOnLaunch = false

    private(set) var container: ModelContainer
    private(set) var containerID = UUID()
    private(set) var isUsingCloudKitContainer = false
    static let appSchema = Schema([
        Recipe.self,
        RecipeIngredient.self,
        RecipeIngredientSection.self,
        RecipeStep.self,
        RecipePreparationMedia.self,
        UnifiedItem.self,
        PantryItem.self,
        GroceryItem.self,
        UtensilItem.self,
        Category.self,
        DeletedDefaultCategory.self,
        ChatMessage.self,
        ChatConversation.self,
        AppSettings.self,
        NutritionProfile.self,
        FoodEntry.self,
        WeightEntry.self,
        NutritionDayLog.self,
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
        var localShouldActivate = syncPref && !skip && cloudKitAllowed

        // Ensure store directory exists
        try? FileManager.default.createDirectory(at: Self.storeDirectory, withIntermediateDirectories: true)

        // Migrate from legacy single store to multi-store layout (one-time)
        Self.performStoreSplitMigrationIfNeeded()

        // PERF/UX FIX: when iCloud sync is enabled, build the CloudKit-backed
        // ModelContainer EAGERLY at boot instead of opening a local container
        // first and swapping ~350 ms later. The previous two-step approach
        // changed `containerID` after launch, which forced the WindowGroup
        // `.id(cloudSync.containerID)` to destroy and recreate ContentView,
        // wiping all `@State` (selected tab, navigation path, sheets, etc.)
        // and competing for the main thread exactly when the user was
        // attempting their first interaction.
        //
        // SAFETY: this does NOT change store URLs, schema, or the CloudKit
        // container identifier — only when the same `makeContainer(usingCloudKit:)`
        // call happens. Same persistence layout that's been used for months;
        // no migration is triggered (destination URLs == current URLs).
        var openedCloudKitEagerly = false
        var initialContainer: ModelContainer
        var initialError: String? = nil

        if localShouldActivate {
            do {
                initialContainer = try Self.makeContainer(usingCloudKit: true)
                openedCloudKitEagerly = true
            } catch {
                NSLog("[CloudSync] Eager CloudKit container failed; falling back to local: %@", String(describing: error))
                do {
                    initialContainer = try Self.makeLocalContainerWithRecoveryIfNeeded()
                } catch {
                    NSLog("Local container failed, falling back to temporary store: %@", String(describing: error))
                    initialContainer = try! Self.makeEphemeralLocalContainer()
                    initialError = String(localized: "Não foi possível abrir o banco local. O app iniciou em modo temporário; reinicie e tente novamente.")
                }
            }
        } else {
            do {
                initialContainer = try Self.makeLocalContainerWithRecoveryIfNeeded()
            } catch {
                NSLog("Local container failed, falling back to temporary store: %@", String(describing: error))
                initialContainer = try! Self.makeEphemeralLocalContainer()
                initialError = String(localized: "Não foi possível abrir o banco local. O app iniciou em modo temporário; reinicie e tente novamente.")
            }
        }

        if openedCloudKitEagerly {
            isUsingCloudKitContainer = true
            hasAttemptedCloudActivationOnLaunch = true
            localShouldActivate = false
        }

        shouldActivateCloudOnLaunch = localShouldActivate
        container = initialContainer
        if let initialError { syncError = initialError }

        if openedCloudKitEagerly {
            lastSyncDate = Date()
        }

        // Disable main-context autosave. With CloudKit-backed SwiftData, the
        // autosave timer races with remote-change notifications and triggers
        // `_SwiftData_SwiftUI` precondition traps (brk #0x1) when the UI layer
        // holds refs to records mutated by the CloudKit mirror. The app
        // already performs explicit `try? context.save()` at every mutation
        // site; we save again on scenePhase transitions as a safety net.
        Self.disableAutosave(on: container)

        if syncPref && !cloudKitAllowed {
            UserDefaults.standard.set(false, forKey: Self.syncEnabledKey)
            syncError = String(localized: "Sincronização iCloud indisponível nesta build.")
            shouldActivateCloudOnLaunch = false
        }

        checkiCloudAvailability()

        // Wire CloudKit observers immediately when we opened the cloud
        // container eagerly. (When deferred, `activateCloudSyncIfNeededOnLaunch`
        // does this after the swap.)
        if openedCloudKitEagerly {
            registerForRemoteNotifications()
            setupRemoteChangeObservation()
        }
    }

    func checkiCloudAvailability() {
        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
    }

    func syncNow() {
        guard !isSyncing, syncEnabled, isUsingCloudKitContainer else { return }
        performSyncNow()
    }

    @MainActor
    func activateCloudSyncIfNeededOnLaunch() {
        guard shouldActivateCloudOnLaunch, !hasAttemptedCloudActivationOnLaunch else { return }
        hasAttemptedCloudActivationOnLaunch = true

        checkiCloudAvailability()
        guard iCloudAvailable else {
            shouldActivateCloudOnLaunch = false
            syncEnabled = false
            syncError = String(localized: "iCloud não está disponível neste dispositivo. Verifique se está conectado nas Configurações do sistema.")
            return
        }

        let newContainer: ModelContainer
        do {
            newContainer = try Self.makeContainer(usingCloudKit: true)
        } catch {
            NSLog("CloudKit container failed after local launch, staying local: %@", String(describing: error))
            shouldActivateCloudOnLaunch = false
            syncEnabled = false
            syncError = String(localized: "Não foi possível inicializar a sincronização com iCloud neste dispositivo.")
            return
        }

        do {
            try Self.migrateLocalDataIfNeeded(from: container, to: newContainer)
        } catch {
            NSLog("[CloudSync] Local-to-cloud launch migration failed: %@", String(describing: error))
        }

        let oldContainer = container
        container = newContainer
        Self.disableAutosave(on: container)
        containerID = UUID()
        isUsingCloudKitContainer = true
        shouldActivateCloudOnLaunch = false
        lastSyncDate = Date()

        registerForRemoteNotifications()
        setupRemoteChangeObservation()

        Task { @MainActor in
            _ = oldContainer
            try? await Task.sleep(for: .seconds(3))
        }

        performSyncNow()
    }

    private func performSyncNow() {
        isSyncing = true
        syncError = nil
        checkiCloudAvailability()

        // PERF: previously this created a brand-new `ModelContext(container)`
        // just to call `context.hasChanges` (which is always false for a
        // fresh context) and then `try context.save()`. That work was
        // pointless and added measurable latency on every foreground
        // (CloudKit-backed containers do non-trivial setup when a new
        // context is materialised). The main context is saved explicitly
        // at every mutation site and again on scene transitions, so all
        // we need here is to record the sync timestamp and schedule
        // deduplication.
        lastSyncDate = Date()
        isSyncing = false

        // Deduplicate after every foreground sync
        scheduleDeduplication()
    }

    var statusDescription: String {
        if isSyncing { return String(localized: "Sincronizando…") }
        if syncEnabled && !isUsingCloudKitContainer && shouldActivateCloudOnLaunch {
            return String(localized: "Preparando iCloud…")
        }
        return iCloudAvailable ? String(localized: "Conectado") : String(localized: "Indisponível")
    }

    // MARK: - Enable / Disable cloud sync

    @MainActor
    func enableCloudSync() async throws {
        guard !syncEnabled else { return }
        guard Self.canUseCloudKitInCurrentEnvironment() else {
            syncError = String(localized: "Sincronização iCloud indisponível nesta build.")
            throw NSError(domain: "CloudSync", code: 2, userInfo: [NSLocalizedDescriptionKey: syncError!])
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        checkiCloudAvailability()
        guard iCloudAvailable else {
            syncError = String(localized: "iCloud não está disponível neste dispositivo. Verifique se está conectado nas Configurações do sistema.")
            throw NSError(domain: "CloudSync", code: 1, userInfo: [NSLocalizedDescriptionKey: syncError!])
        }

        // 1. Create cloud container
        let newContainer: ModelContainer
        do {
            newContainer = try Self.makeContainer(usingCloudKit: true)
        } catch {
            syncError = String(localized: "Não foi possível criar o container iCloud: \(error.localizedDescription)")
            throw error
        }

        do {
            try Self.migrateLocalDataIfNeeded(from: container, to: newContainer)
        } catch {
            NSLog("[CloudSync] Local-to-cloud enable migration failed: %@", String(describing: error))
        }

        // 2. Update state and keep old container alive briefly for pending writes
        let oldContainer = container
        syncEnabled = true
        shouldActivateCloudOnLaunch = false
        hasAttemptedCloudActivationOnLaunch = true
        container = newContainer
        Self.disableAutosave(on: container)
        containerID = UUID()
        isUsingCloudKitContainer = true
        lastSyncDate = Date()

        registerForRemoteNotifications()
        setupRemoteChangeObservation()

        // Keep old container alive so pending writes finish
        Task { @MainActor in
            _ = oldContainer
            try? await Task.sleep(for: .seconds(3))
        }

        // 4. Trigger an immediate sync/save to push newly migrated data
        performSyncNow()
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
            syncError = String(localized: "Não foi possível criar o container local: \(error.localizedDescription)")
            throw error
        }

        // 2. Update state
        let oldContainer = container
        syncEnabled = false
        shouldActivateCloudOnLaunch = false
        hasAttemptedCloudActivationOnLaunch = false
        container = newContainer
        Self.disableAutosave(on: container)
        containerID = UUID()
        isUsingCloudKitContainer = false
        teardownRemoteChangeObservation()

        // Keep old container alive so pending writes finish
        Task { @MainActor in
            _ = oldContainer
            try? await Task.sleep(for: .seconds(3))
        }
    }

    @MainActor
    func resetAllDataLocallyAndInICloud() async throws {
        let shouldAttemptCloudReset = syncEnabled || isUsingCloudKitContainer || lastSyncDate != nil || SharingService.shared.isSharing

        if shouldAttemptCloudReset {
            guard Self.canUseCloudKitInCurrentEnvironment() else {
                throw NSError(
                    domain: "CloudSync",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Apagar os dados do iCloud só está disponível em um device físico com suporte a CloudKit.")]
                )
            }

            checkiCloudAvailability()
            guard iCloudAvailable else {
                throw NSError(
                    domain: "CloudSync",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Entre no iCloud neste dispositivo para apagar também os dados sincronizados do app.")]
                )
            }
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        teardownRemoteChangeObservation()

        if shouldAttemptCloudReset {
            try await Self.deleteAllCloudData()
        }

        let context = ModelContext(container)
        context.autosaveEnabled = false
        try Self.deleteAllLocalData(in: context)
        DataSeeder.seedIfNeeded(context: context)
        try context.save()

        NotificationService.shared.removeAllNotifications()
        BackupManager.shared.deleteAllBackups()
        SharingService.shared.resetLocalState()

        UserDefaults.standard.removeObject(forKey: Self.lastSyncDateKey)
        syncError = nil

        if isUsingCloudKitContainer {
            setupRemoteChangeObservation()
        }
    }

    // MARK: - Multi-store migration

    /// Legacy single-store default location (as used before the multi-store split).
    private static var legacyDefaultStoreURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("default.store")
    }

    /// Self-healing migration from the legacy single `default.store` to the new multi-store
    /// layout. Safe to re-run: if a previous run marked the flag but left the new stores empty,
    /// this will detect the legacy store and re-migrate user data.
    private static func performStoreSplitMigrationIfNeeded() {
        let fm = FileManager.default
        let legacyURL = legacyDefaultStoreURL

        // Fast-path: nothing to migrate from.
        guard fm.fileExists(atPath: legacyURL.path) else {
            if !UserDefaults.standard.bool(forKey: storeSplitKey) {
                UserDefaults.standard.set(true, forKey: storeSplitKey)
            }
            return
        }

        // Open the legacy single-store container at the default location.
        let oldConfig = ModelConfiguration(schema: appSchema, cloudKitDatabase: .none)
        guard let oldContainer = try? ModelContainer(for: appSchema, configurations: oldConfig) else {
            // Can't open legacy; don't flip the flag so we can try again later.
            return
        }
        let oldContext = ModelContext(oldContainer)

        // Determine if legacy store carries anything worth migrating.
        let legacyHasUserData = storeHasUserData(context: oldContext)
        let legacyHasSettings: Bool = {
            var fd = FetchDescriptor<AppSettings>()
            fd.fetchLimit = 1
            return (try? !oldContext.fetch(fd).isEmpty) ?? false
        }()

        guard legacyHasUserData || legacyHasSettings else {
            // Legacy store exists but is empty — archive it and mark complete.
            archiveLegacyStore(at: legacyURL)
            UserDefaults.standard.set(true, forKey: storeSplitKey)
            return
        }

        // Open (or create) the new multi-store container for migration (local only).
        guard let newContainer = try? makeContainer(usingCloudKit: false) else { return }
        let newContext = ModelContext(newContainer)

        // If new stores already carry real user data (recipes, items), don't overwrite.
        // Seeded-only defaults (categories / one blank AppSettings) do NOT count.
        if storeHasUserData(context: newContext) {
            NSLog("[CloudSync] New stores already contain user data; archiving legacy store without copying.")
            archiveLegacyStore(at: legacyURL)
            UserDefaults.standard.set(true, forKey: storeSplitKey)
            return
        }

        do {
            // Copy all data — SwiftData routes each model to its correct store by schema.
            for item in try oldContext.fetch(FetchDescriptor<Category>()) {
                newContext.insert(copyCategory(item))
            }
            for item in try oldContext.fetch(FetchDescriptor<DeletedDefaultCategory>()) {
                newContext.insert(copyDeletedDefaultCategory(item))
            }
            for item in try oldContext.fetch(FetchDescriptor<UnifiedItem>()) {
                newContext.insert(copyUnifiedItem(item))
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
            for conversation in try oldContext.fetch(FetchDescriptor<ChatConversation>()) {
                newContext.insert(copyChatConversation(conversation))
            }
            for settings in try oldContext.fetch(FetchDescriptor<AppSettings>()) {
                newContext.insert(copyAppSettings(settings))
            }
            try newContext.save()

            // Deduplicate immediately so seeded defaults don't collide with migrated copies.
            deduplicateAfterMigration(context: newContext)

            // Archive the legacy store so the migration cannot fire again accidentally.
            archiveLegacyStore(at: legacyURL)
            UserDefaults.standard.set(true, forKey: storeSplitKey)
            NSLog("[CloudSync] Store split migration completed successfully")
        } catch {
            // Do NOT mark the flag — allow the next launch to retry.
            NSLog("[CloudSync] Store split migration failed: %@", String(describing: error))
        }
    }

    /// Returns true when the store contains user-generated content that must not be overwritten.
    /// Seeded default categories and an empty AppSettings instance do NOT count as user data.
    private static func storeHasUserData(context: ModelContext) -> Bool {
        func nonEmpty<T: PersistentModel>(_ type: T.Type) -> Bool {
            var fd = FetchDescriptor<T>()
            fd.fetchLimit = 1
            return (try? !context.fetch(fd).isEmpty) ?? false
        }
        if nonEmpty(UnifiedItem.self) { return true }
        if nonEmpty(Recipe.self) { return true }
        if nonEmpty(PantryItem.self) { return true }
        if nonEmpty(GroceryItem.self) { return true }
        if nonEmpty(UtensilItem.self) { return true }
        if nonEmpty(ChatMessage.self) { return true }
        if nonEmpty(ChatConversation.self) { return true }
        // An AppSettings row that has finished onboarding also qualifies as user data.
        if let settings = try? context.fetch(FetchDescriptor<AppSettings>()),
           settings.contains(where: { $0.hasCompletedOnboarding }) {
            return true
        }
        return false
    }

    /// Returns true when the store has list/recipe content visible in the app.
    /// Private-only metadata such as chat/settings does not count here because
    /// a CloudKit destination with only private rows still needs the shared/list
    /// data copied across.
    private static func storeHasPrimaryUserContent(context: ModelContext) -> Bool {
        func nonEmpty<T: PersistentModel>(_ type: T.Type) -> Bool {
            var fd = FetchDescriptor<T>()
            fd.fetchLimit = 1
            return (try? !context.fetch(fd).isEmpty) ?? false
        }

        if nonEmpty(UnifiedItem.self) { return true }
        if nonEmpty(Recipe.self) { return true }
        if nonEmpty(PantryItem.self) { return true }
        if nonEmpty(GroceryItem.self) { return true }
        if nonEmpty(UtensilItem.self) { return true }
        return false
    }

    /// Move the legacy default.store files aside so the migration does not re-evaluate them.
    private static func archiveLegacyStore(at legacyURL: URL) {
        let fm = FileManager.default
        let timestamp = Int(Date().timeIntervalSince1970)
        let archiveDir = storeDirectory
            .appendingPathComponent("Recovery", isDirectory: true)
            .appendingPathComponent("legacy-default-\(timestamp)", isDirectory: true)

        do {
            try fm.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        } catch {
            NSLog("[CloudSync] Could not create legacy archive dir: %@", String(describing: error))
            return
        }

        let candidates = [
            legacyURL,
            URL(fileURLWithPath: legacyURL.path + "-wal"),
            URL(fileURLWithPath: legacyURL.path + "-shm"),
        ]

        for url in candidates where fm.fileExists(atPath: url.path) {
            let destination = archiveDir.appendingPathComponent(url.lastPathComponent)
            do {
                try fm.moveItem(at: url, to: destination)
            } catch {
                try? fm.removeItem(at: destination)
                try? fm.moveItem(at: url, to: destination)
            }
        }
    }

    /// Dedup pass run immediately after a migration copy, using the migration's own context.
    /// Mirrors the logic in `performDeduplication`, but against the freshly-populated new store
    /// so seeded defaults don't persist as duplicates of migrated rows.
    private static func deduplicateAfterMigration(context: ModelContext) {
        func dedupByUUID<T: PersistentModel>(_ type: T.Type, keyPath: KeyPath<T, UUID>) {
            guard let all = try? context.fetch(FetchDescriptor<T>()) else { return }
            var seen = Set<UUID>()
            for item in all {
                let id = item[keyPath: keyPath]
                if seen.contains(id) {
                    context.delete(item)
                } else {
                    seen.insert(id)
                }
            }
        }

        dedupByUUID(UnifiedItem.self, keyPath: \.id)
        dedupByUUID(PantryItem.self, keyPath: \.id)
        dedupByUUID(GroceryItem.self, keyPath: \.id)
        dedupByUUID(UtensilItem.self, keyPath: \.id)
        dedupByUUID(Recipe.self, keyPath: \.id)
        dedupByUUID(ChatMessage.self, keyPath: \.id)
        dedupByUUID(ChatConversation.self, keyPath: \.id)

        // Categories: dedup by UUID, then by (type, normalized name), keeping lowest sortOrder.
        if let categories = try? context.fetch(FetchDescriptor<Category>()) {
            var seenIDs = Set<UUID>()
            var surviving = [Category]()
            for cat in categories {
                if seenIDs.contains(cat.id) {
                    context.delete(cat)
                } else {
                    seenIDs.insert(cat.id)
                    surviving.append(cat)
                }
            }
            surviving.sort { $0.sortOrder < $1.sortOrder }
            var seenKeys = Set<String>()
            for cat in surviving {
                let normalized = cat.name
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .lowercased()
                let key = "\(cat.type.rawValue)|\(normalized)"
                if seenKeys.contains(key) {
                    context.delete(cat)
                } else {
                    seenKeys.insert(key)
                }
            }
        }

        // AppSettings: keep only one — prefer the one with completed onboarding.
        if let all = try? context.fetch(FetchDescriptor<AppSettings>()), all.count > 1 {
            let sorted = all.sorted {
                ($0.hasCompletedOnboarding ? 1 : 0) > ($1.hasCompletedOnboarding ? 1 : 0)
            }
            for item in sorted.dropFirst() {
                context.delete(item)
            }
        }

        try? context.save()
    }

    // MARK: - Container factory

    private static func makeContainer(usingCloudKit: Bool) throws -> ModelContainer {
        let privateSchema = Schema([
            AppSettings.self, ChatMessage.self, ChatConversation.self,
            NutritionProfile.self, FoodEntry.self, WeightEntry.self, NutritionDayLog.self,
        ])
        let sharedSchema = Schema([
            UnifiedItem.self, PantryItem.self, GroceryItem.self, UtensilItem.self, Category.self, DeletedDefaultCategory.self,
            Recipe.self, RecipeIngredient.self, RecipeIngredientSection.self, RecipeStep.self, RecipePreparationMedia.self,
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

    private static func makeLocalContainerWithRecoveryIfNeeded() throws -> ModelContainer {
        do {
            return try makeContainer(usingCloudKit: false)
        } catch {
            let alreadyAttempted = UserDefaults.standard.bool(forKey: storeRecoveryAttemptedKey)
            guard !alreadyAttempted else { throw error }

            UserDefaults.standard.set(true, forKey: storeRecoveryAttemptedKey)
            backupBrokenStoresForRecovery()

            return try makeContainer(usingCloudKit: false)
        }
    }

    /// Turns off the automatic save timer on the container's main context.
    /// Must be called for every container we swap into `self.container`.
    /// See `init()` for the rationale (autosave races with CloudKit remote
    /// changes and triggers `_SwiftData_SwiftUI` preconditions).
    private static func disableAutosave(on container: ModelContainer) {
        // `mainContext` and `autosaveEnabled` are `@MainActor`-isolated.
        // Hop to the main actor; the timer won't start before this runs
        // because SwiftUI binds to the container on the main actor as well.
        Task { @MainActor in
            container.mainContext.autosaveEnabled = false
        }
    }

    private static func makeEphemeralLocalContainer() throws -> ModelContainer {
        let fallbackDir = storeDirectory.appendingPathComponent("Fallback", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)

        let privateURL = fallbackDir.appendingPathComponent("Private-\(UUID().uuidString).store")
        let sharedURL = fallbackDir.appendingPathComponent("Shared-\(UUID().uuidString).store")

        let privateSchema = Schema([
            AppSettings.self, ChatMessage.self, ChatConversation.self,
            NutritionProfile.self, FoodEntry.self, WeightEntry.self, NutritionDayLog.self,
        ])
        let sharedSchema = Schema([
            UnifiedItem.self, PantryItem.self, GroceryItem.self, UtensilItem.self, Category.self, DeletedDefaultCategory.self,
            Recipe.self, RecipeIngredient.self, RecipeIngredientSection.self, RecipeStep.self, RecipePreparationMedia.self,
        ])

        let privateConfig = ModelConfiguration(
            "PrivateFallback",
            schema: privateSchema,
            url: privateURL,
            cloudKitDatabase: .none
        )
        let sharedConfig = ModelConfiguration(
            "SharedFallback",
            schema: sharedSchema,
            url: sharedURL,
            cloudKitDatabase: .none
        )

        return try ModelContainer(for: appSchema, configurations: privateConfig, sharedConfig)
    }

    @MainActor
    private static func migrateLocalDataIfNeeded(from sourceContainer: ModelContainer, to destinationContainer: ModelContainer) throws {
        let sourceContext = ModelContext(sourceContainer)
        let destinationContext = ModelContext(destinationContainer)

        guard storeHasPrimaryUserContent(context: sourceContext) else { return }
        guard !storeHasPrimaryUserContent(context: destinationContext) else { return }

        for item in try sourceContext.fetch(FetchDescriptor<Category>()) {
            destinationContext.insert(copyCategory(item))
        }
        for item in try sourceContext.fetch(FetchDescriptor<DeletedDefaultCategory>()) {
            destinationContext.insert(copyDeletedDefaultCategory(item))
        }
        for item in try sourceContext.fetch(FetchDescriptor<UnifiedItem>()) {
            destinationContext.insert(copyUnifiedItem(item))
        }
        for item in try sourceContext.fetch(FetchDescriptor<PantryItem>()) {
            destinationContext.insert(copyPantryItem(item))
        }
        for item in try sourceContext.fetch(FetchDescriptor<GroceryItem>()) {
            destinationContext.insert(copyGroceryItem(item))
        }
        for item in try sourceContext.fetch(FetchDescriptor<UtensilItem>()) {
            destinationContext.insert(copyUtensilItem(item))
        }
        for recipe in try sourceContext.fetch(FetchDescriptor<Recipe>()) {
            destinationContext.insert(copyRecipe(recipe))
        }
        for message in try sourceContext.fetch(FetchDescriptor<ChatMessage>()) {
            destinationContext.insert(copyChatMessage(message))
        }
        for conversation in try sourceContext.fetch(FetchDescriptor<ChatConversation>()) {
            destinationContext.insert(copyChatConversation(conversation))
        }
        for settings in try sourceContext.fetch(FetchDescriptor<AppSettings>()) {
            destinationContext.insert(copyAppSettings(settings))
        }

        try destinationContext.save()
        deduplicateAfterMigration(context: destinationContext)
        NSLog("[CloudSync] Migrated local data into CloudKit-backed stores before container swap")
    }

    private static func backupBrokenStoresForRecovery() {
        let fm = FileManager.default
        let recoveryDir = storeDirectory
            .appendingPathComponent("Recovery", isDirectory: true)
            .appendingPathComponent("store-\(Int(Date().timeIntervalSince1970))", isDirectory: true)

        try? fm.createDirectory(at: recoveryDir, withIntermediateDirectories: true)

        for baseURL in [privateStoreURL, sharedStoreURL] {
            let candidates = [
                baseURL,
                URL(fileURLWithPath: baseURL.path + "-wal"),
                URL(fileURLWithPath: baseURL.path + "-shm"),
            ]

            for url in candidates where fm.fileExists(atPath: url.path) {
                let destination = recoveryDir.appendingPathComponent(url.lastPathComponent)
                do {
                    try fm.moveItem(at: url, to: destination)
                } catch {
                    try? fm.removeItem(at: destination)
                    try? fm.moveItem(at: url, to: destination)
                }
            }
        }
    }

    private static func deleteAllCloudData() async throws {
        let database = CKContainer(identifier: cloudKitContainerID).privateCloudDatabase
        let zoneIDs = try await database.allRecordZones()
            .map(\.zoneID)
            .filter { $0 != CKRecordZone.default().zoneID }

        guard !zoneIDs.isEmpty else { return }
        _ = try await database.modifyRecordZones(saving: [], deleting: zoneIDs)
    }

    @MainActor
    private static func deleteAllLocalData(in context: ModelContext) throws {
        for recipe in try context.fetch(FetchDescriptor<Recipe>()) {
            context.delete(recipe)
        }
        try context.delete(model: UnifiedItem.self)
        try context.delete(model: PantryItem.self)
        try context.delete(model: GroceryItem.self)
        try context.delete(model: UtensilItem.self)
        try context.delete(model: DeletedDefaultCategory.self)
        try context.delete(model: Category.self)
        try context.delete(model: ChatMessage.self)
        try context.delete(model: ChatConversation.self)
        try context.delete(model: AppSettings.self)
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
        // Observe on the main queue so the handler never runs while the SwiftData
        // main context (used by @Query / UI) is mid-flight on the main thread.
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
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
            guard let self else { return }
            // `performDeduplication` is @MainActor; hop explicitly since a
            // DispatchWorkItem executed on the main queue does NOT provide the
            // MainActor isolation the compiler requires.
            Task { @MainActor in
                self.performDeduplication()
            }
        }
        deduplicationWorkItem = work
        // Debounce: CloudKit can fire many notifications in rapid succession
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Removes duplicate records across all entity types.
    /// Must run on the main actor: it uses `container.mainContext` so deletions
    /// propagate through the exact same context that `@Query` / UI bindings rely
    /// on, preventing UI from retaining zombie `PersistentModel` refs that the
    /// main-context autosave timer would later trap on (brk #0x1).
    @MainActor
    func performDeduplication() {
        let context = container.mainContext

        var totalDeleted = 0
        totalDeleted += deduplicateByID(UnifiedItem.self, keyPath: \.id, context: context)
        totalDeleted += deduplicateByID(PantryItem.self, keyPath: \.id, context: context)
        totalDeleted += deduplicateByID(GroceryItem.self, keyPath: \.id, context: context)
        totalDeleted += deduplicateByID(UtensilItem.self, keyPath: \.id, context: context)
        totalDeleted += deduplicateByID(Recipe.self, keyPath: \.id, context: context)
        totalDeleted += deduplicateByID(ChatMessage.self, keyPath: \.id, context: context)
        totalDeleted += deduplicateByID(ChatConversation.self, keyPath: \.id, context: context)
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

    private static func copyDeletedDefaultCategory(_ source: DeletedDefaultCategory) -> DeletedDefaultCategory {
        let copy = DeletedDefaultCategory(name: source.name, type: source.type)
        copy.id = source.id
        return copy
    }

    private static func copyUnifiedItem(_ source: UnifiedItem) -> UnifiedItem {
        let copy = UnifiedItem(
            name: source.name,
            descriptionText: source.descriptionText,
            imageData: source.imageData,
            category: source.category,
            quantity: source.quantity,
            unit: source.unit,
            iconName: source.iconName,
            isPantry: source.isPantry,
            isGrocery: source.isGrocery,
            isUtensil: source.isUtensil,
            pantrySortOrder: source.pantrySortOrder,
            grocerySortOrder: source.grocerySortOrder,
            utensilSortOrder: source.utensilSortOrder,
            isLinkedToGrocery: source.isLinkedToGrocery,
            expirationDate: source.expirationDate,
            defaultExpiryDays: source.defaultExpiryDays,
            isChecked: source.isChecked,
            isFixed: source.isFixed,
            linkedPantryItemId: source.linkedPantryItemId
        )
        copy.id = source.id
        copy.addedAt = source.addedAt
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
                sortOrder: ing.sortOrder,
                sectionID: ing.sectionID
            )
            c.id = ing.id
            return c
        }

        copy.ingredientSections = (source.ingredientSections ?? []).map { section in
            let c = RecipeIngredientSection(
                title: section.title,
                subtitle: section.subtitle,
                sortOrder: section.sortOrder,
                id: section.id
            )
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

    private static func copyChatConversation(_ source: ChatConversation) -> ChatConversation {
        let copy = ChatConversation(title: source.title)
        copy.id = source.id
        copy.createdAt = source.createdAt
        copy.updatedAt = source.updatedAt
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
        copy.hasCompletedOnboarding = source.hasCompletedOnboarding
        copy.showUtensils = source.showUtensils
        copy.recipeGalleryColumns = source.recipeGalleryColumns
        copy.pantryGroupingModeRaw = source.pantryGroupingModeRaw
        copy.groceryGroupingModeRaw = source.groceryGroupingModeRaw
        return copy
    }
}
