import SwiftUI

enum PageTheme: String, Codable, CaseIterable {
    case home = "home"
    case lists = "lists"
    case recipes = "recipes"
    case nutrients = "nutrients"
    /// Neutral gray theme used by the macOS Settings sidebar page.
    case settings = "settings"
    /// Neutral gray theme used by the macOS Assistente / Modo IA pages.
    case assistant = "assistant"

    var accentColor: Color {
        switch self {
        case .home:
            Color(hue: 14.0 / 360.0, saturation: 0.84, brightness: 0.75)
        case .lists:
            Color(red: 0.20, green: 0.50, blue: 0.93)
        case .recipes:
            Color(red: 0.85, green: 0.58, blue: 0.12)
        case .nutrients:
            Color(red: 0.18, green: 0.66, blue: 0.36)
        case .settings:
            // Cool slate gray
            Color(red: 0.42, green: 0.46, blue: 0.52)
        case .assistant:
            // Neutral warm gray
            Color(red: 0.50, green: 0.50, blue: 0.54)
        }
    }

    var secondaryAccentColor: Color {
        switch self {
        case .home:
            Color(hue: 14.0 / 360.0, saturation: 0.72, brightness: 0.90)
        case .lists:
            Color(red: 0.42, green: 0.73, blue: 0.98)
        case .recipes:
            Color(red: 0.95, green: 0.70, blue: 0.20)
        case .nutrients:
            Color(red: 0.42, green: 0.84, blue: 0.58)
        case .settings:
            Color(red: 0.62, green: 0.66, blue: 0.72)
        case .assistant:
            Color(red: 0.72, green: 0.72, blue: 0.76)
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .home, .lists, .recipes, .nutrients, .settings, .assistant:
            LinearGradient(colors: [secondaryAccentColor, accentColor], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var cardGradient: LinearGradient {
        LinearGradient(
            colors: [
                secondaryAccentColor.opacity(0.24),
                accentColor.opacity(0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var searchContext: SearchPageContext {
        switch self {
        case .home: .home
        case .lists: .lists
        case .recipes: .recipes
        case .nutrients: .nutrients
        case .settings: .home
        case .assistant: .home
        }
    }
}
