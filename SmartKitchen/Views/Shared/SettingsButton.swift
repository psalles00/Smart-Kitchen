import SwiftUI

// MARK: - Environment key for opening settings from any page

private struct OpenSettingsActionKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openSettings: () -> Void {
        get { self[OpenSettingsActionKey.self] }
        set { self[OpenSettingsActionKey.self] = newValue }
    }
}

// MARK: - Environment key for scroll-to-top trigger

struct ScrollToTopTriggerKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: Int = 0
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

/// Reusable toolbar button that triggers an external action when tapped.
struct SettingsButton: View {
    var onTap: (() -> Void)? = nil
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        GlassButtonGroup {
            GlassGroupButton(systemImage: "gearshape") {
                if let onTap {
                    onTap()
                } else {
                    openSettings()
                }
            }
        }
    }
}
