import SwiftUI

/// Tabs available in the main tab bar.
enum AppTab: String, Hashable {
    case assistant
    case lists
    case recipes
    case nutrients
    case add

    var icon: String {
        switch self {
        case .assistant: "house"
        case .lists:     "list.bullet.clipboard"
        case .recipes:   "book.closed"
        case .nutrients: "chart.bar.doc.horizontal"
        case .add:       "plus"
        }
    }
}
