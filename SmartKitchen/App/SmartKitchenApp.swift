import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

@main
struct SmartKitchenApp: App {
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            Recipe.self,
            RecipeIngredient.self,
            RecipeStep.self,
            RecipePreparationMedia.self,
            PantryItem.self,
            GroceryItem.self,
            Category.self,
            ChatMessage.self,
            AppSettings.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Seed demo data on first launch
        let context = ModelContext(modelContainer)
        DataSeeder.seedIfNeeded(context: context)

        // Must be called after all stored properties are initialized
        #if os(iOS)
        Self.configureNavigationAppearance()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .defaultSize(width: 1100, height: 750)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
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
