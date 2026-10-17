import Foundation
import Observation
import SwiftData
import CloudKit
import SQLite3

/// In-memory model that aggregates every choice the user makes through the
/// onboarding flow. Nothing is persisted to SwiftData until the very last
/// step (`OnboardingStep.preparing`) commits everything atomically. This keeps
/// the database clean if the user kills the app halfway through.
@Observable
final class OnboardingState {
    /// Current step index inside `OnboardingStep.allCases`.
    var stepIndex: Int = 0

    // MARK: - Phase 2 selections (≥3 each)
    /// Identifiers of pantry items chosen on the pantry catalog screen.
    var selectedPantryItemIDs: Set<String> = []
    /// Identifiers of grocery items chosen on the grocery catalog screen.
    var selectedGroceryItemIDs: Set<String> = []
    /// Identifiers of recipe templates chosen on the recipe interests screen.
    var selectedRecipeTemplateIDs: Set<String> = []

    // MARK: - Phase 4 nutrition
    /// Mirrors `NutritionProfile` fields. Only persisted on the preparing step.
    var nutritionGoalRaw: String? = nil       // WeightGoal raw value
    var nutritionSexRaw: String? = nil        // NutritionSex raw value
    var nutritionBirthday: Date? = nil
    var nutritionHeightCm: Double = 170
    var nutritionWeightKg: Double = 70
    var nutritionActivityRaw: String? = nil   // ActivityLevel raw value
    var nutritionWeeklyChangeKg: Double = 0.5
    /// Goal-rate input mode used on the rate step. The internal source of
    /// truth is always `nutritionWeeklyChangeKg` — when the user picks a
    /// target weight + months, we convert.
    var nutritionRateMode: RateInputMode = .targetWeight
    /// Target weight (kg) the user wants to reach. Only used when
    /// `nutritionRateMode == .targetWeight`. Default = current weight ± 5kg
    /// computed lazily by the view.
    var nutritionTargetWeightKg: Double = 65
    /// Number of months to reach the target weight.
    var nutritionTargetMonths: Int = 3

    // MARK: - Phase 4.5 discovery
    /// Optional source that tells us where the user first heard about Savoria.
    /// Kept in-memory during onboarding and later mirrored to UserDefaults.
    var discoverySourceID: String? = nil

    // MARK: - Phase 5 paywall
    /// Tracks the plan the user previewed in the paywall (annual/monthly).
    var selectedPlanID: String? = nil
    /// Prevents requesting the App Store review more than once per onboarding
    /// run if the user navigates back and forth near the end.
    var didRequestAppStoreReview: Bool = false

    // MARK: - Computed gates
    var canAdvancePantrySelection: Bool { selectedPantryItemIDs.count >= 3 }
    var canAdvanceGrocerySelection: Bool { selectedGroceryItemIDs.count >= 3 }
    var canAdvanceRecipeSelection: Bool { selectedRecipeTemplateIDs.count >= 2 }
    var canAdvanceDiscoverySource: Bool { discoverySourceID != nil }
}

/// Goal-rate input mode for `RateStepView`.
enum RateInputMode: String, CaseIterable, Identifiable {
    case targetWeight  // "Quero chegar a X kg em Y meses"
    case perWeek       // "X kg por semana"

    var id: String { rawValue }
}

/// Kept outside the view tree: enabling the existing CloudKit stores rebuilds
/// ContentView. Recovery must survive that rebuild without repeating setup.
@MainActor
@Observable
final class ICloudOnboardingRecovery {
    static let shared = ICloudOnboardingRecovery()
    private static let pendingKey = "Savoria.iCloudOnboardingRecovery.pending"
    private static let completedKey = "Savoria.iCloudOnboardingRecovery.completed"

    struct Summary: Equatable {
        var items = 0
        var recipes = 0
        var foodEntries = 0
        var conversations = 0
        var weightEntries = 0
        var configured = false
        var hasUserData: Bool { configured || items + recipes + foodEntries + conversations + weightEntries > 0 }

        static func read(in context: ModelContext) throws -> Self {
            Summary(items: try context.fetchCount(FetchDescriptor<UnifiedItem>()),
                    recipes: try context.fetchCount(FetchDescriptor<Recipe>()),
                    foodEntries: try context.fetchCount(FetchDescriptor<FoodEntry>()),
                    conversations: try context.fetchCount(FetchDescriptor<ChatConversation>()),
                    weightEntries: try context.fetchCount(FetchDescriptor<WeightEntry>()),
                    configured: try context.fetch(FetchDescriptor<AppSettings>()).contains { $0.hasCompletedOnboarding }
                        || context.fetch(FetchDescriptor<NutritionProfile>()).contains { $0.hasCompletedOnboarding })
        }
    }

    enum Phase: Equatable { case idle, checking, waiting, available, delayed, failed(String) }

    struct Actions {
        var checkAccount: () async throws -> Void
        var enable: () async throws -> Void
        var read: () throws -> Summary
        var complete: () throws -> Void
        var wait: () async throws -> Void = { try await Task.sleep(for: .seconds(2)) }

        static var live: Self {
            Actions(checkAccount: {
                #if targetEnvironment(simulator)
                throw NSError(domain: "CloudRecovery", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "A recuperação do iCloud precisa ser validada em um dispositivo Apple real.")])
                #else
                guard try await CKContainer(identifier: CloudSyncService.cloudKitContainerID).accountStatus() == .available else {
                    throw NSError(domain: "CloudRecovery", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "iCloud não está disponível neste dispositivo. Verifique se está conectado nas Configurações do sistema.")])
                }
                #endif
            }, enable: {
                let sync = CloudSyncService.shared
                if !sync.syncEnabled {
                    try await makeCheckpoint(sync: sync)
                    try Task.checkCancellation()
                    try await sync.enableCloudSync()
                }
                guard sync.isUsingCloudKitContainer else {
                    throw NSError(domain: "CloudRecovery", code: 3, userInfo: [NSLocalizedDescriptionKey: String(localized: "Não foi possível inicializar a sincronização com iCloud neste dispositivo.")])
                }
                sync.syncNow()
            }, read: {
                // Always use the CURRENT container, never a context from the
                // welcome view that was replaced when sync became active.
                try Summary.read(in: ModelContext(CloudSyncService.shared.container))
            }, complete: {
                let context = ModelContext(CloudSyncService.shared.container)
                guard try Summary.read(in: context).hasUserData else { throw RecoveryError.noData }
                // Do not seed selections, alter nutrition targets, restore
                // purchases or mutate seeded AppSettings while the user's
                // real settings may still be arriving from CloudKit.
            })
        }
    }

    private enum RecoveryError: LocalizedError {
        case noData, storesUnavailable
        var errorDescription: String? {
            switch self {
            case .noData: String(localized: "Seus dados ainda não estão disponíveis. Tente novamente.")
            case .storesUnavailable: String(localized: "Não foi possível proteger os bancos locais. A recuperação não foi iniciada.")
            }
        }
    }
    private let defaults: UserDefaults
    private let actions: Actions
    private var task: Task<Void, Never>?
    private var operationID = UUID()
    private(set) var isPresented: Bool
    private(set) var phase: Phase = .idle
    private(set) var summary = Summary()
    var isBusy: Bool { phase == .checking || phase == .waiting }
    var hasCompletedRecovery: Bool { defaults.bool(forKey: Self.completedKey) }

    init(defaults: UserDefaults = .standard, actions: Actions? = nil) {
        self.defaults = defaults
        self.actions = actions ?? .live
        isPresented = defaults.bool(forKey: Self.pendingKey)
    }

    func present() { isPresented = true }

    func dismiss() {
        operationID = UUID()
        task?.cancel(); task = nil
        isPresented = false
        defaults.set(false, forKey: Self.pendingKey)
        phase = .idle
    }

    func start() {
        guard task == nil else { return }
        isPresented = true
        defaults.set(true, forKey: Self.pendingKey)
        phase = .checking
        let id = UUID()
        operationID = id
        task = Task { [weak self] in
            guard let self else { return }
            defer { if operationID == id { task = nil } }
            guard operationID == id, !Task.isCancelled else { return }
            do {
                summary = try actions.read()
                if summary.hasUserData { phase = .available; return }
                try await actions.checkAccount()
                try Task.checkCancellation()
                try await actions.enable()
                try Task.checkCancellation()
                phase = .waiting
                for _ in 0..<30 {
                    summary = try actions.read()
                    if summary.hasUserData { phase = .available; return }
                    try await actions.wait()
                    try Task.checkCancellation()
                }
                phase = .delayed // A timeout is NOT proof of an empty account.
            } catch is CancellationError {
                // Leave sync and all stores as they are; never roll back data.
            } catch {
                if operationID == id { phase = .failed(error.localizedDescription) }
            }
        }
    }

    func finish() -> Bool {
        guard phase == .available else { return false }
        do {
            try actions.complete()
            defaults.set(true, forKey: Self.completedKey)
            dismiss()
            return true
        } catch {
            phase = .failed(error.localizedDescription)
            return false
        }
    }

    func refreshAvailableSummary() {
        guard isPresented, phase == .available else { return }
        do { summary = try actions.read() }
        catch { phase = .failed(error.localizedDescription) }
    }

    /// Preserve the exact local stores and external blobs before changing the
    /// existing sync flag. Unique checkpoints are never pruned or auto-restored.
    private static func makeCheckpoint(sync: CloudSyncService) async throws {
        let expected = Set([CloudSyncService.privateStoreURL.standardizedFileURL, CloudSyncService.sharedStoreURL.standardizedFileURL])
        guard expected.isSubset(of: Set(sync.container.configurations.map { $0.url.standardizedFileURL })) else { throw RecoveryError.storesUnavailable }
        try sync.container.mainContext.save()
        let stores = [CloudSyncService.privateStoreURL, CloudSyncService.sharedStoreURL]
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let destination = base.appendingPathComponent("iCloudRecoveryCheckpoints/\(UUID().uuidString)", isDirectory: true)
        let preferences = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        let preferenceData = try PropertyListSerialization.data(fromPropertyList: preferences, format: .binary, options: 0)
        let media = [FileManager.default.temporaryDirectory.appendingPathComponent("RecipeMediaCache")]
        try await Task.detached(priority: .utility) {
            let fm = FileManager.default
            try fm.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for store in stores {
                guard fm.fileExists(atPath: store.path) else { throw RecoveryError.storesUnavailable }
                for source in [store, URL(fileURLWithPath: store.path + "-wal"), URL(fileURLWithPath: store.path + "-shm"), store.deletingLastPathComponent().appendingPathComponent(".\(store.deletingPathExtension().lastPathComponent)_SUPPORT")] where fm.fileExists(atPath: source.path) {
                    try fm.copyItem(at: source, to: destination.appendingPathComponent(source.lastPathComponent))
                }
            }
            for source in media where fm.fileExists(atPath: source.path) {
                try fm.copyItem(at: source, to: destination.appendingPathComponent(source.lastPathComponent))
            }
            for store in stores {
                var database: OpaquePointer?
                guard sqlite3_open_v2(destination.appendingPathComponent(store.lastPathComponent).path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                    if let database { sqlite3_close(database) }
                    throw RecoveryError.storesUnavailable
                }
                defer { sqlite3_close(database) }
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, "PRAGMA quick_check", -1, &statement, nil) == SQLITE_OK else { throw RecoveryError.storesUnavailable }
                defer { sqlite3_finalize(statement) }
                guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0), String(cString: value) == "ok" else { throw RecoveryError.storesUnavailable }
            }
            try preferenceData.write(to: destination.appendingPathComponent("preferences.plist"), options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.appendingPathComponent("preferences.plist").path)
        }.value
    }
}
