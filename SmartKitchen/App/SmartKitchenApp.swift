import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

extension Notification.Name {
    static let openSettings = Notification.Name("com.smartkitchen.openSettings")
}

@main
struct SmartKitchenApp: App {
    @State private var cloudSync = CloudSyncService.shared

    init() {
        // Seed demo data on first launch
        let context = ModelContext(CloudSyncService.shared.container)
        DataSeeder.seedIfNeeded(context: context)

        // Must be called after all stored properties are initialized
        #if os(iOS)
        Self.configureNavigationAppearance()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(cloudSync.container)
                .id(cloudSync.containerID)
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 750)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
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
