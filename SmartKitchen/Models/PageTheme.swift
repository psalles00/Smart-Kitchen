import SwiftUI

enum PageTheme: String, Codable, CaseIterable {
    case home = "home"
    case lists = "lists"
    case recipes = "recipes"
    case nutrients = "nutrients"

    var accentColor: Color {
        switch self {
        case .home:
            Color(red: 0.75, green: 0.12, blue: 0.18)
        case .lists:
            Color(red: 0.20, green: 0.50, blue: 0.93)
        case .recipes:
            Color(red: 0.85, green: 0.58, blue: 0.12)
        case .nutrients:
            Color(red: 0.18, green: 0.66, blue: 0.36)
        }
    }

    var secondaryAccentColor: Color {
        switch self {
        case .home:
            Color(red: 0.90, green: 0.30, blue: 0.25)
        case .lists:
            Color(red: 0.42, green: 0.73, blue: 0.98)
        case .recipes:
            Color(red: 0.95, green: 0.70, blue: 0.20)
        case .nutrients:
            Color(red: 0.42, green: 0.84, blue: 0.58)
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .home:
            LinearGradient(colors: [secondaryAccentColor, accentColor], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .lists:
            LinearGradient(colors: [secondaryAccentColor, accentColor], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .recipes:
            LinearGradient(colors: [secondaryAccentColor, accentColor], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .nutrients:
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
        }
    }
}
