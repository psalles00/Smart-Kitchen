import SwiftUI

enum PageTheme: String, Codable, CaseIterable {
    case home = "home"
    case lists = "lists"
    case recipes = "recipes"
    case nutrients = "nutrients"

    var gradient: LinearGradient {
        switch self {
        case .home:
            LinearGradient(colors: [Color.orange, Color.red.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .lists:
            LinearGradient(colors: [Color.blue, Color.cyan.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .recipes:
            LinearGradient(colors: [Color.orange.opacity(0.9), Color.yellow.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .nutrients:
            LinearGradient(colors: [Color.green, Color.mint.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
