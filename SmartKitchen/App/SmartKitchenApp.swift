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
    /// Posted when the user taps a pending day on the Home page.
    /// `userInfo["date"]` carries the `Date` (startOfDay) to focus on Nutrição.
    static let openNutritionAtDate = Notification.Name("com.smartkitchen.openNutritionAtDate")
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
    @State private var isAppReady = false
    /// Last time we ran the on-foreground maintenance work
    /// (`syncNow` + reschedule expiry notifications). Used to throttle that
    /// work so brief background hops don't repeatedly hit the model
    /// context and the notification center on the main thread, which on
    /// real devices shows up as a stutter the first time the user
    /// interacts after returning to the app.
    @State private var lastForegroundMaintenance: Date = .distantPast
    /// Last time we refreshed StoreKit entitlements on foreground. StoreKit
    /// calls go through `Transaction.currentEntitlements`, which can take
    /// several hundred ms on real devices the first time after a long
    /// suspension. Throttling stops short foreground hops from re-running
    /// the entire entitlement check (and the implicit JIT setup that
    /// follows) which contributes to the post-resume jank.
    @State private var lastEntitlementRefresh: Date = .distantPast

    init() {
        // Must be called after all stored properties are initialized
        #if os(iOS)
        _ = StatusBarSwizzle.install
        Self.configureNavigationAppearance()
        #endif
        Self.logBuildConfiguration()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .modelContainer(cloudSync.container)
                    .id(cloudSync.containerID)
                    .environment(subscriptionManager)
                    // Hide ContentView entirely while the splash is up so it
                    // can't capture taps and so its first frame work happens
                    // off the user's critical path.
                    .opacity(isAppReady ? 1 : 0)
                    .allowsHitTesting(isAppReady)

                if !isAppReady {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeOut(duration: 0.25), value: isAppReady)
            #if os(macOS)
            .frame(
                minWidth: Self.macMinimumWindowSize.width,
                minHeight: Self.macMinimumWindowSize.height
            )
            #endif
            .environment(\.sharedImportPresentationEnabled, isAppReady && scenePhase == .active)
                // Sheets hosted OUTSIDE `.id(cloudSync.containerID)` survive
                // the ContentView teardown that happens when CloudKit
                // activation swaps the `ModelContainer` shortly after launch.
                // Attaching the share-import host here is the load-bearing
                // fix for the recurrent "compartilhar abre e fecha o modal"
                // bug — see `SharedImportInboxHost` for details.
                .recipeImportInboxHost()
                .sharedImportInboxHost()
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
                    if SharedImportInbox.shared.ingest(url: url) {
                        return
                    }
                    _ = RecipeImportInbox.shared.ingest(url: url)
                }
                .task {
                    _ = SharedImportInbox.shared.claimPendingFromBridge()
                    FeatureGate.shared.subscriptionManager = subscriptionManager
                    await subscriptionManager.loadProducts()
                    await subscriptionManager.refreshEntitlements()
                    await runPostLaunchBootstrapIfNeeded()
                }
                .onChange(of: scenePhase) { oldValue, newValue in
                    if newValue == .active {
                        _ = SharedImportInbox.shared.claimPendingFromBridge()
                        // Refresh subscription state on foreground so
                        // expirations / external upgrades land promptly.
                        // Throttle to once per 5 min — StoreKit calls are
                        // not free on real devices and the user's
                        // entitlement doesn't realistically change every
                        // 30 s of background.
                        let now = Date()
                        if now.timeIntervalSince(lastEntitlementRefresh) >= 300 {
                            lastEntitlementRefresh = now
                            Task { await subscriptionManager.refreshEntitlements() }
                        }
                        // Throttle: avoid running sync + notification reschedule
                        // every time the user briefly leaves and returns. The
                        // previous unconditional behaviour caused noticeable
                        // jank on the first interaction after foregrounding.
                        if now.timeIntervalSince(lastForegroundMaintenance) >= 60 {
                            lastForegroundMaintenance = now
                            cloudSync.syncNow()
                            // Defer the notification reschedule one runloop tick
                            // so it never competes with the first frame the user
                            // sees after returning.
                            Task { @MainActor in
                                let ctx = cloudSync.container.mainContext
                                let descriptor = FetchDescriptor<AppSettings>()
                                if let settings = try? ctx.fetch(descriptor).first {
                                    NotificationService.shared.rescheduleExpiryNotifications(context: ctx, settings: settings)
                                }
                            }
                        }
                    }
                    // Autosave is disabled on the main context to avoid races
                    // with CloudKit remote-change notifications. Persist any
                    // pending edits whenever the scene leaves the foreground.
                    if newValue == .inactive || newValue == .background {
                        let ctx = cloudSync.container.mainContext
                        if ctx.hasChanges {
                            try? ctx.save()
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
    private func runPostLaunchBootstrapIfNeeded() async {
        guard !didRunPostLaunchBootstrap else { return }
        didRunPostLaunchBootstrap = true

        // Let the splash render its first frame before doing heavy work.
        try? await Task.sleep(for: .milliseconds(50))

        // PERF: warm up the bundled item / category databases on a
        // background queue, in parallel with the SwiftData bootstrap work
        // that runs on the main actor below. These caches are touched
        // synchronously by the very first list / search / icon resolver
        // call on the UI; warming them off-main here means the first user
        // interaction never has to pay their build cost.
        let warmupTask = Task.detached(priority: .userInitiated) {
            _ = CategoryDatabase.shared
            ItemDatabase.shared.prewarm()
        }

        let context = ModelContext(cloudSync.container)
        DataSeeder.seedIfNeeded(context: context)
        UnifiedItemMigration.migrateIfNeeded(context: context)
        _ = BackupManager.shared.restoreLatestBackupIfCurrentStoreNeedsRecovery(context: context)

        cloudSync.activateCloudSyncIfNeededOnLaunch()

        // Wait for the prewarm to finish before lifting the splash so the
        // first frame of ContentView already sees populated caches. This is
        // bounded — building one language index over 16k entries takes a
        // handful of ms on modern hardware and runs concurrently with the
        // seeder above.
        await warmupTask.value

        // Lift the splash now that the data layer is ready and ContentView
        // can render with all SwiftData stores fully prepared.
        isAppReady = true
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
        #else
        print("SmartKitchen build configuration: RELEASE")
        #endif
    }
}
