import SwiftUI
import SwiftData
import CloudKit
import CoreText

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Notification.Name {
    static let openSettings = Notification.Name("com.smartkitchen.openSettings")
    /// Posted when the user taps the Assistant widget (Lock Screen / Home Screen).
    /// The root view responds by revealing the fullscreen assistant in AI chat mode,
    /// which in turn auto-focuses the text field (keyboard opens automatically).
    static let openAssistantFromWidget = Notification.Name("com.smartkitchen.openAssistantFromWidget")
    /// Posted when the user taps the AI Chat widget. Reveals the fullscreen assistant
    /// in AI chat mode (conversation interface, keyboard open).
    static let openAIChatFromWidget = Notification.Name("com.smartkitchen.openAIChatFromWidget")
    /// Posted when the user taps a nutrition logging widget.
    /// `userInfo["action"]` carries one of the `NutritionLogWidgetAction` raw values.
    static let openNutritionLogFromWidget = Notification.Name("com.smartkitchen.openNutritionLogFromWidget")
    /// Posted when the user taps a pending day on the Home page.
    /// `userInfo["date"]` carries the `Date` (startOfDay) to focus on Nutrição.
    static let openNutritionAtDate = Notification.Name("com.smartkitchen.openNutritionAtDate")
    /// Posted whenever a Nutrition day is completed, canceled, or reopened.
    /// Views with derived snapshots use it to refresh immediately after mutations.
    static let nutritionDayLogChanged = Notification.Name("com.smartkitchen.nutritionDayLogChanged")
    /// Posted when the Savoria/Home page should recalculate all derived content.
    static let homeDataShouldRefresh = Notification.Name("com.smartkitchen.homeDataShouldRefresh")
    /// Posted on iOS when the Appearance setting changes so the root view can
    /// update its preferred color scheme immediately.
    static let appearanceModeChanged = Notification.Name("com.smartkitchen.appearanceModeChanged")
}

@MainActor
enum WidgetDeepLinkStore {
    private static var pendingNutritionLogAction: String?

    static func postNutritionLogAction(_ action: String) {
        pendingNutritionLogAction = action
        NotificationCenter.default.post(
            name: .openNutritionLogFromWidget,
            object: nil,
            userInfo: ["action": action]
        )
    }

    static func consumePendingNutritionLogAction() -> String? {
        let action = pendingNutritionLogAction
        pendingNutritionLogAction = nil
        return action
    }
}

// MARK: - App Delegate for CloudKit Share Acceptance

#if os(iOS)
class SmartKitchenAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task {
            try? await SharingService.shared.acceptShare(metadata: cloudKitShareMetadata)
            await SharingService.shared.refreshShare()
        }
    }
}
#elseif os(macOS)
class SmartKitchenAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task {
            try? await SharingService.shared.acceptShare(metadata: metadata)
            await SharingService.shared.refreshShare()
        }
    }
}
#endif

#if os(macOS)
struct NewItemCommandAction {
    let title: String
    let perform: () -> Void
}

private struct NewItemCommandActionKey: FocusedValueKey {
    typealias Value = NewItemCommandAction
}

private struct OpenCommandBarActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newItemCommandAction: NewItemCommandAction? {
        get { self[NewItemCommandActionKey.self] }
        set { self[NewItemCommandActionKey.self] = newValue }
    }

    var openCommandBarAction: (() -> Void)? {
        get { self[OpenCommandBarActionKey.self] }
        set { self[OpenCommandBarActionKey.self] = newValue }
    }
}

struct MacNewItemCommands: Commands {
    @FocusedValue(\.newItemCommandAction) private var newItemCommandAction
    @FocusedValue(\.openCommandBarAction) private var openCommandBarAction

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "Buscar e Adicionar…")) {
                openCommandBarAction?()
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()

            Button(newItemCommandAction?.title ?? String(localized: "Novo")) {
                newItemCommandAction?.perform()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(newItemCommandAction == nil)
        }
    }
}
#endif

@main
struct SmartKitchenApp: App {
    #if os(macOS)
    private static let macMinimumWindowSize = CGSize(width: 1100, height: 750)
    private static let macSettingsWindowSize = CGSize(width: 1240, height: 860)
    #endif

    #if os(iOS)
    @UIApplicationDelegateAdaptor(SmartKitchenAppDelegate.self) var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(SmartKitchenAppDelegate.self) var appDelegate
    #endif

    @Environment(\.scenePhase) private var scenePhase
    @State private var cloudSync = CloudSyncService.shared
    @State private var subscriptionManager = SubscriptionManager()
    @State private var didRunPostLaunchBootstrap = false
    /// Drives the splash screen overlay: stays `false` until the data layer
    /// (SwiftData container + seeders + migrations + backup recovery) has
    /// finished its post-launch bootstrap. While `false`, the user cannot
    /// interact with the app — they see the centered logo splash instead.
    @State private var isLaunchContentMounted = false
    @State private var didLaunchContentAppear = false
    @State private var isAppReady = false
    @State private var launchAppearanceMode: AppearanceMode = .launchPreference
    /// Last time we ran the on-foreground maintenance work
    /// (`syncNow` + reschedule expiry notifications). Used to throttle that
    /// work so brief background hops don't repeatedly hit the model
    /// context and the notification center on the main thread, which on
    /// real devices shows up as a stutter the first time the user
    /// interacts after returning to the app.
    @State private var lastForegroundMaintenance: Date = Date()
    /// Last time we refreshed StoreKit entitlements on foreground. StoreKit
    /// calls go through `Transaction.currentEntitlements`, which can take
    /// several hundred ms on real devices the first time after a long
    /// suspension. Throttling stops short foreground hops from re-running
    /// the entire entitlement check (and the implicit JIT setup that
    /// follows) which contributes to the post-resume jank.
    @State private var lastEntitlementRefresh: Date = Date()
    @State private var pendingSceneLeaveSaveTask: Task<Void, Never>?
    @State private var pendingForegroundResumeTask: Task<Void, Never>?
    @State private var foregroundResumeTraceCounter = 0

    init() {
        // Must be called after all stored properties are initialized
        PerformanceLogger.event(.launch, "SmartKitchenApp.init body begin")
        #if os(iOS)
        _ = StatusBarSwizzle.install
        PerformanceLogger.event(.launch, "after StatusBarSwizzle.install")
        Self.configureNavigationAppearance()
        PerformanceLogger.event(.launch, "after configureNavigationAppearance")
        #endif
        Self.logBuildConfiguration()
        PerformanceLogger.event(.launch, "after logBuildConfiguration")

        // Wire the perf logger early so every subsequent UIApplication
        // lifecycle notification and CloudKit remote-change burst is
        // recorded relative to launch. This is the source of truth used to
        // diagnose post-foreground stutters.
        PerformanceLogger.installLifecycleObservers()
        PerformanceLogger.installMainThreadHangDetector()
        PerformanceLogger.installCloudKitMirrorObserver()
        #if os(iOS)
        ActionTrace.shared.install()
        #endif
        PerformanceLogger.event(.launch, "SmartKitchenApp.init body end")
    }

    var body: some Scene {
        // PERF DIAG: log every time SwiftUI evaluates the scene body.
        PerformanceLogger.event(.launch, "SmartKitchenApp.body evaluated")
        return WindowGroup {
            // PERF DIAG: log first window-group content build.
            let _ = PerformanceLogger.event(.launch, "WindowGroup content building")
            ZStack {
                if isLaunchContentMounted {
                    ContentView()
                        .modelContainer(cloudSync.container)
                        .id(cloudSync.containerID)
                        .environment(subscriptionManager)
                        .opacity(isAppReady ? 1 : 0)
                        .allowsHitTesting(isAppReady)
                        .accessibilityHidden(!isAppReady)
                        .onAppear {
                            didLaunchContentAppear = true
                            PerformanceLogger.event(.launch, "ContentView onAppear", metadata: "visible=\(isAppReady)")
                        }
                }

                if !isAppReady {
                    SplashView()
                        .zIndex(1)
                        .onAppear {
                            PerformanceLogger.event(.launch, "SplashView appeared")
                        }
                }
            }
            .preferredColorScheme(launchAppearanceMode.colorScheme)
            .onReceive(NotificationCenter.default.publisher(for: .appearanceModeChanged)) { _ in
                launchAppearanceMode = .launchPreference
            }
            #if os(macOS)
            .frame(
                minWidth: Self.macMinimumWindowSize.width,
                minHeight: Self.macMinimumWindowSize.height
            )
            #endif
            // Sheets hosted OUTSIDE `.id(cloudSync.containerID)` survive
            // the ContentView teardown that happens when CloudKit
            // activation swaps the `ModelContainer` shortly after launch.
            // Attaching the share-import host here is the load-bearing
            // fix for the recurrent "compartilhar abre e fecha o modal"
            // bug — see `SharedImportInboxHost` for details.
            .recipeImportInboxHost()
            .sharedImportInboxHost(isPresentationEnabled: isAppReady && scenePhase == .active)
                .onOpenURL { url in
                    RecipeImportLogger.info("app onOpenURL received url=\(url.absoluteString)")
                    // Widget deep links
                    if url.scheme == "smartkitchen", url.host == "assistant" {
                        NotificationCenter.default.post(name: .openAssistantFromWidget, object: nil)
                        return
                    }
                    if url.scheme == "smartkitchen", url.host == "aichat" {
                        NotificationCenter.default.post(name: .openAIChatFromWidget, object: nil)
                        return
                    }
                    if Self.isNutritionLogDeepLink(url) {
                        let action = Self.nutritionLogAction(from: url)
                        WidgetDeepLinkStore.postNutritionLogAction(action)
                        return
                    }
                    if SharedImportInbox.shared.ingest(url: url) {
                        return
                    }
                    _ = RecipeImportInbox.shared.ingest(url: url)
                }
                .task {
                    _ = SharedImportInbox.shared.claimPendingFromBridge()
                    syncLaunchAppearanceFromSettings()
                    FeatureGate.shared.subscriptionManager = subscriptionManager
                    PerformanceLogger.event(.subscriptions, "subscriptionManager.loadProducts begin")
                    let loadStart = Date()
                    await subscriptionManager.loadProducts()
                    PerformanceLogger.event(.subscriptions, "subscriptionManager.loadProducts end", metadata: String(format: "tookMs=%.1f", Date().timeIntervalSince(loadStart) * 1000))
                    PerformanceLogger.event(.subscriptions, "subscriptionManager.refreshEntitlements (launch) begin")
                    let refreshStart = Date()
                    await subscriptionManager.refreshEntitlements()
                    lastEntitlementRefresh = Date()
                    PerformanceLogger.event(.subscriptions, "subscriptionManager.refreshEntitlements (launch) end", metadata: String(format: "tookMs=%.1f", Date().timeIntervalSince(refreshStart) * 1000))
                    await runPostLaunchBootstrapIfNeeded()
                }
                .onChange(of: scenePhase) { oldValue, newValue in
                    PerformanceLogger.event(.scenePhase, "scenePhase \(oldValue) -> \(newValue)")
                    if newValue == .active {
                        scheduleForegroundResumeWork()
                    } else {
                        cancelForegroundResumeWork(reason: "\(oldValue)->\(newValue)")
                    }
                    // Autosave is disabled on the main context to avoid races
                    // with CloudKit remote-change notifications. Persist any
                    // pending edits whenever the scene leaves the foreground.
                    //
                    // Defer the save to a Task so the scenePhase transition
                    // animation completes first. Saving the main context with
                    // CloudKit-mirrored changes pending was producing ~480ms
                    // main-thread hangs during the `active -> inactive ->
                    // background` sequence. Running it async lets UIKit finish
                    // the transition before we pay that cost.
                    let isLeavingForeground = oldValue != .background
                        && (newValue == .inactive || newValue == .background)
                    if isLeavingForeground {
                        let ctx = cloudSync.container.mainContext
                        let hasChanges = ctx.hasChanges
                        if PerformanceLogger.isEnabled {
                            PerformanceLogger.event(
                                .cloudSync,
                                "scene-leave save inspection",
                                metadata: "hasChanges=\(hasChanges) inserted=\(ctx.insertedModelsArray.count) changed=\(ctx.changedModelsArray.count) deleted=\(ctx.deletedModelsArray.count)"
                            )
                        }
                        if hasChanges {
                            scheduleSceneLeaveSave(
                                reason: "\(oldValue)->\(newValue)",
                                delay: newValue == .background ? .milliseconds(30) : .milliseconds(160)
                            )
                        }
                    }
                }
        }
        #if os(macOS)
        .defaultSize(
            width: Self.macMinimumWindowSize.width,
            height: Self.macMinimumWindowSize.height
        )
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            MacNewItemCommands()
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(cloudSync.container)
                .environment(subscriptionManager)
                .frame(
                    minWidth: Self.macSettingsWindowSize.width,
                    minHeight: Self.macSettingsWindowSize.height
                )
        }
        .defaultSize(
            width: Self.macSettingsWindowSize.width,
            height: Self.macSettingsWindowSize.height
        )
        #endif
    }

    @MainActor
    private func scheduleSceneLeaveSave(reason: String, delay: Duration) {
        pendingSceneLeaveSaveTask?.cancel()
        pendingSceneLeaveSaveTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            defer { pendingSceneLeaveSaveTask = nil }

            let ctx = cloudSync.container.mainContext
            guard ctx.hasChanges else {
                PerformanceLogger.event(
                    .cloudSync,
                    "scene-leave save skipped (no pending changes)",
                    metadata: "reason=\(reason)"
                )
                return
            }

            do {
                try PerformanceLogger.measure(.cloudSync, "scene-leave save", metadata: "reason=\(reason)") {
                    try ctx.save()
                }
            } catch {
                PerformanceLogger.error(
                    .cloudSync,
                    "scene-leave save failed",
                    metadata: "reason=\(reason) error=\(error.localizedDescription)"
                )
            }
        }
    }

    @MainActor
    private func scheduleForegroundResumeWork() {
        let traceID: String
        if PerformanceLogger.isEnabled {
            foregroundResumeTraceCounter += 1
            traceID = "fg-\(foregroundResumeTraceCounter)"
        } else {
            traceID = "foreground"
        }

        let didClaimSharedImport = PerformanceLogger.measure(.scenePhase, "claimPendingFromBridge", metadata: "trace=\(traceID)") {
            SharedImportInbox.shared.claimPendingFromBridge()
        }
        PerformanceLogger.event(.scenePhase, "foreground resume entered", metadata: "trace=\(traceID) claimedSharedImport=\(didClaimSharedImport)")

        let now = Date()
        let entitlementElapsed = now.timeIntervalSince(lastEntitlementRefresh)
        let maintenanceElapsed = now.timeIntervalSince(lastForegroundMaintenance)
        let shouldRefreshEntitlements = entitlementElapsed >= 300
        let shouldRunMaintenance = maintenanceElapsed >= 300

        guard shouldRefreshEntitlements || shouldRunMaintenance else {
            PerformanceLogger.event(
                .scenePhase,
                "foreground resume work skipped",
                metadata: "trace=\(traceID) entitlementElapsed=\(Int(entitlementElapsed))s maintenanceElapsed=\(Int(maintenanceElapsed))s"
            )
            return
        }

        pendingForegroundResumeTask?.cancel()
        PerformanceLogger.event(
            .scenePhase,
            "foreground resume work scheduled",
            metadata: "trace=\(traceID) refreshEntitlements=\(shouldRefreshEntitlements) maintenance=\(shouldRunMaintenance)"
        )

        pendingForegroundResumeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled, scenePhase == .active else {
                PerformanceLogger.event(.scenePhase, "foreground resume work cancelled before subscriptions", metadata: "trace=\(traceID)")
                return
            }

            if shouldRefreshEntitlements {
                lastEntitlementRefresh = Date()
                PerformanceLogger.event(.subscriptions, "refreshEntitlements begin", metadata: "trace=\(traceID)")
                let t0 = Date()
                await subscriptionManager.refreshEntitlements()
                PerformanceLogger.event(
                    .subscriptions,
                    "refreshEntitlements end",
                    metadata: String(format: "trace=\(traceID) tookMs=%.1f", Date().timeIntervalSince(t0) * 1000)
                )
            } else {
                PerformanceLogger.event(.subscriptions, "refreshEntitlements skipped (throttled)", metadata: "trace=\(traceID) elapsed=\(Int(entitlementElapsed))s")
            }

            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, scenePhase == .active else {
                PerformanceLogger.event(.scenePhase, "foreground resume work cancelled before maintenance", metadata: "trace=\(traceID)")
                return
            }

            if shouldRunMaintenance {
                lastForegroundMaintenance = Date()
                PerformanceLogger.event(.cloudSync, "foreground maintenance running", metadata: "trace=\(traceID)")
                PerformanceLogger.measure(.cloudSync, "syncNow (deferred foreground)", metadata: "trace=\(traceID)") {
                    cloudSync.syncNow()
                }

                let ctx = cloudSync.container.mainContext
                let descriptor = FetchDescriptor<AppSettings>()
                PerformanceLogger.measure(.notifications, "rescheduleExpiryNotifications", metadata: "trace=\(traceID)") {
                    if let settings = try? ctx.fetch(descriptor).first {
                        NotificationService.shared.rescheduleExpiryNotifications(context: ctx, settings: settings)
                    }
                }
            } else {
                PerformanceLogger.event(.cloudSync, "foreground maintenance skipped (throttled)", metadata: "trace=\(traceID) elapsed=\(Int(maintenanceElapsed))s")
            }

            pendingForegroundResumeTask = nil
        }
    }

    @MainActor
    private func cancelForegroundResumeWork(reason: String) {
        guard pendingForegroundResumeTask != nil else { return }
        pendingForegroundResumeTask?.cancel()
        pendingForegroundResumeTask = nil
        PerformanceLogger.event(.scenePhase, "foreground resume work cancelled", metadata: "reason=\(reason)")
    }

    @MainActor
    private func runPostLaunchBootstrapIfNeeded() async {
        guard !didRunPostLaunchBootstrap else { return }
        didRunPostLaunchBootstrap = true

        PerformanceLogger.event(.launch, "runPostLaunchBootstrap begin")
        let bootstrapStart = Date()
        syncLaunchAppearanceFromSettings()

        // Let the splash render its first frame before doing heavy work.
        try? await Task.sleep(for: .milliseconds(50))

        // PERF: warm up the bundled item / category databases on a
        // background queue, in parallel with the SwiftData bootstrap work
        // that runs on the main actor below. These caches are touched
        // synchronously by the very first list / search / icon resolver
        // call on the UI; warming them off-main here means the first user
        // interaction never has to pay their build cost.
        let warmupTask = Task.detached(priority: .userInitiated) {
            PerformanceLogger.measure(.launch, "warmupDatabases") {
                _ = CategoryDatabase.shared
                ItemDatabase.shared.prewarm()
            }
        }

        let context = ModelContext(cloudSync.container)
        PerformanceLogger.measure(.dataSeeder, "DataSeeder.seedIfNeeded") {
            DataSeeder.seedIfNeeded(context: context)
        }
        syncLaunchAppearanceFromSettings()
        PerformanceLogger.measure(.migration, "UnifiedItemMigration.migrateIfNeeded") {
            UnifiedItemMigration.migrateIfNeeded(context: context)
        }
        PerformanceLogger.measure(.backup, "BackupManager.restoreLatestBackupIfCurrentStoreNeedsRecovery") {
            _ = BackupManager.shared.restoreLatestBackupIfCurrentStoreNeedsRecovery(context: context)
        }

        PerformanceLogger.measure(.cloudSync, "activateCloudSyncIfNeededOnLaunch") {
            cloudSync.activateCloudSyncIfNeededOnLaunch()
        }

        // Wait for the prewarm to finish before lifting the splash so the
        // first frame of ContentView already sees populated caches. This is
        // bounded — building one language index over 16k entries takes a
        // handful of ms on modern hardware and runs concurrently with the
        // seeder above.
        await warmupTask.value

        // Mount ContentView behind the splash first. The first SwiftUI /
        // SwiftData @Query subscription pass is the expensive part on real
        // devices, so paying it while the skeleton is still visible avoids
        // revealing a half-mounted UI that stutters for the next few frames.
        isLaunchContentMounted = true
        PerformanceLogger.event(.launch, "launch content prewarm mount requested")

        let prewarmStart = Date()
        while !didLaunchContentAppear && Date().timeIntervalSince(prewarmStart) < 2.0 {
            try? await Task.sleep(for: .milliseconds(50))
        }

        try? await Task.sleep(for: .milliseconds(700))

        // Lift the splash after the initial ContentView mount has had at
        // least one frame and one short settling window.
        isAppReady = true
        PerformanceLogger.event(.launch, "runPostLaunchBootstrap end (splash lifted)", metadata: String(format: "tookMs=%.1f", Date().timeIntervalSince(bootstrapStart) * 1000))
    }

    @MainActor
    private func syncLaunchAppearanceFromSettings() {
        let context = ModelContext(cloudSync.container)
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        guard let settings = try? context.fetch(descriptor).first else { return }
        settings.appearanceMode.persistForLaunch()
        launchAppearanceMode = settings.appearanceMode
    }

    // MARK: - Appearance

    #if os(iOS)
    private static func configureNavigationAppearance() {
        let largeTitleFont = makeBrandedNavigationFont(size: 34, weight: 760)
        let titleFont = makeBrandedNavigationFont(size: 17, weight: 650)

        UINavigationBar.appearance().largeTitleTextAttributes = [.font: largeTitleFont]
        UINavigationBar.appearance().titleTextAttributes = [.font: titleFont]
    }

    private static func makeBrandedNavigationFont(size: CGFloat, weight: CGFloat) -> UIFont {
        guard let base = UIFont(name: "Bricolage Grotesque", size: size) else {
            return .systemFont(ofSize: size, weight: size >= 30 ? .bold : .semibold)
        }

        let opticalSize = min(max(size, 12), 96)
        let variation: [NSNumber: NSNumber] = [
            1869640570: NSNumber(value: Double(opticalSize)),
            2003265652: NSNumber(value: Double(weight)),
            2003072104: 100
        ]
        let descriptor = base.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variation
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    #endif

    private static func logBuildConfiguration() {
        #if DEBUG
        print("SmartKitchen build configuration: DEBUG")
        #endif
    }

    private static func isNutritionLogDeepLink(_ url: URL) -> Bool {
        guard url.scheme == "smartkitchen" else { return false }
        let host = url.host ?? ""
        return host == "foodlog" || host == "nutrition-log"
    }

    private static func nutritionLogAction(from url: URL) -> String {
        if let queryAction = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "action" })?
            .value,
           !queryAction.isEmpty {
            return queryAction
        }

        return url.pathComponents.dropFirst().first ?? "menu"
    }
}
