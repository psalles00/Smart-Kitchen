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

    init() {
        // Seed demo data on first launch
        let context = ModelContext(CloudSyncService.shared.container)
        DataSeeder.seedIfNeeded(context: context)

        // Clean any existing duplicates from prior sync issues
        CloudSyncService.shared.performDeduplication()

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
