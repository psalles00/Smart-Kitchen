import SwiftUI

// MARK: - Environment key for presenting app settings from any page

private struct PresentAppSettingsActionKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var presentAppSettings: () -> Void {
        get { self[PresentAppSettingsActionKey.self] }
        set { self[PresentAppSettingsActionKey.self] = newValue }
    }
}

// MARK: - Environment key for opening a recipe in the Recipes tab

private struct OpenRecipeInRecipesTabKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: (UUID) -> Void = { _ in }
}

extension EnvironmentValues {
    var openRecipeInRecipesTab: (UUID) -> Void {
        get { self[OpenRecipeInRecipesTabKey.self] }
        set { self[OpenRecipeInRecipesTabKey.self] = newValue }
    }
}

// MARK: - Environment key for scroll-to-top trigger

struct ScrollToTopTriggerKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

extension EnvironmentValues {
    var scrollToTopTrigger: Int {
        get { self[ScrollToTopTriggerKey.self] }
        set { self[ScrollToTopTriggerKey.self] = newValue }
    }
}

// MARK: - Environment key for scroll-to-item from search

/// Identifies a specific item to scroll to and highlight after navigating from search.
struct ScrollToItemRequest: Equatable {
    let itemID: UUID
    let type: String // "pantryItem", "groceryItem", "recipe", "utensil"
}

private struct ScrollToItemKey: EnvironmentKey {
    static let defaultValue: ScrollToItemRequest? = nil
}

extension EnvironmentValues {
    var scrollToItem: ScrollToItemRequest? {
        get { self[ScrollToItemKey.self] }
        set { self[ScrollToItemKey.self] = newValue }
    }
}

// MARK: - Environment key for page background theme

/// When set, ExpandedPageLayout uses this theme (with cross-fade) for its background
/// instead of its own fixed pageTheme.
private struct BackgroundThemeKey: EnvironmentKey {
    static let defaultValue: PageTheme? = nil
}

extension EnvironmentValues {
    var backgroundTheme: PageTheme? {
        get { self[BackgroundThemeKey.self] }
        set { self[BackgroundThemeKey.self] = newValue }
    }
}

private struct VisiblePageThemeKey: EnvironmentKey {
    static let defaultValue: PageTheme? = nil
}

extension EnvironmentValues {
    var visiblePageTheme: PageTheme? {
        get { self[VisiblePageThemeKey.self] }
        set { self[VisiblePageThemeKey.self] = newValue }
    }
}

private struct UsesGlobalPageBackgroundKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var usesGlobalPageBackground: Bool {
        get { self[UsesGlobalPageBackgroundKey.self] }
        set { self[UsesGlobalPageBackgroundKey.self] = newValue }
    }
}

/// Reusable toolbar button that triggers an external action when tapped.
struct SettingsButton: View {
    var onTap: (() -> Void)? = nil
    @Environment(\.presentAppSettings) private var presentAppSettings

    var body: some View {
        GlassButtonGroup {
            GlassGroupButton(systemImage: "gearshape") {
                if let onTap {
                    onTap()
                } else {
                    presentAppSettings()
                }
            }
            .accessibilityIdentifier("savoria.settings")
        }
    }
}
