import SwiftUI

/// Tabs available in the main tab bar.
enum AppTab: String, Hashable {
    case assistant
    case lists
    case recipes
    case nutrients
    case commandBar

    var icon: String {
        switch self {
        case .assistant:  "house"
        case .lists:      "list.bullet.clipboard"
        case .recipes:    "book.closed"
        case .nutrients:  "fork.knife"
        case .commandBar: "sparkle.magnifyingglass"
        }
    }

    var pageTheme: PageTheme? {
        switch self {
        case .assistant:
            .home
        case .lists:
            .lists
        case .recipes:
            .recipes
        case .nutrients:
            .nutrients
        case .commandBar:
            nil
        }
    }
}
