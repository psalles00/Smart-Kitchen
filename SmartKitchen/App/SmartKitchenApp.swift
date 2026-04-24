import SwiftUI
import SwiftData
import CloudKit

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
            Button("Buscar e Adicionar…") {
                openCommandBarAction?()
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()

            Button(newItemCommandAction?.title ?? "Novo") {
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
    #if os(iOS)
    @UIApplicationDelegateAdaptor(SmartKitchenAppDelegate.self) var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(SmartKitchenAppDelegate.self) var appDelegate
    #endif

    @Environment(\.scenePhase) private var scenePhase
    @State private var cloudSync = CloudSyncService.shared
    @State private var didRunPostLaunchBootstrap = false

    init() {
        // Must be called after all stored properties are initialized
        #if os(iOS)
        _ = StatusBarSwizzle.install
        Self.configureNavigationAppearance()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(cloudSync.container)
                .id(cloudSync.containerID)
                .recipeImportInboxHost()
                .onOpenURL { url in
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
                    await runPostLaunchBootstrapIfNeeded()
                }
                .onChange(of: scenePhase) { oldValue, newValue in
                    if newValue == .active {
                        cloudSync.syncNow()
                        // Reschedule expiry notifications
                        let ctx = cloudSync.container.mainContext
                        let descriptor = FetchDescriptor<AppSettings>()
                        if let settings = try? ctx.fetch(descriptor).first {
                            NotificationService.shared.rescheduleExpiryNotifications(context: ctx, settings: settings)
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
        .defaultSize(width: 1100, height: 750)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            MacNewItemCommands()
            CommandGroup(replacing: .appSettings) {
                Button("Configurações…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        #endif
    }

    @MainActor
    private func runPostLaunchBootstrapIfNeeded() async {
        guard !didRunPostLaunchBootstrap else { return }
        didRunPostLaunchBootstrap = true

        // Let the first frame render before running store maintenance.
        try? await Task.sleep(for: .milliseconds(350))

        let context = ModelContext(cloudSync.container)
        DataSeeder.seedIfNeeded(context: context)
        UnifiedItemMigration.migrateIfNeeded(context: context)
        _ = BackupManager.shared.restoreLatestBackupIfCurrentStoreNeedsRecovery(context: context)

        cloudSync.activateCloudSyncIfNeededOnLaunch()
    }

    // MARK: - Appearance

    #if os(iOS)
    private static func configureNavigationAppearance() {
        // Variable font registered as "PlayfairDisplay-Regular" — use UIFontDescriptor for weights
        let baseName = "PlayfairDisplay-Regular"
        let largeTitleFont: UIFont = {
            if let base = UIFont(name: baseName, size: 34) {
                let desc = base.fontDescriptor.addingAttributes([
                    .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold.rawValue]
                ])
                return UIFont(descriptor: desc, size: 34)
            }
            return .systemFont(ofSize: 34, weight: .bold)
        }()
        let titleFont: UIFont = {
            if let base = UIFont(name: baseName, size: 17) {
                let desc = base.fontDescriptor.addingAttributes([
                    .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold.rawValue]
                ])
                return UIFont(descriptor: desc, size: 17)
            }
            return .systemFont(ofSize: 17, weight: .semibold)
        }()

        UINavigationBar.appearance().largeTitleTextAttributes = [.font: largeTitleFont]
        UINavigationBar.appearance().titleTextAttributes = [.font: titleFont]
    }
    #endif
}
