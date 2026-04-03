import SwiftUI

enum PageTheme: String, Codable, CaseIterable {
    case home = "home"
    case lists = "lists"
    case recipes = "recipes"
    case nutrients = "nutrients"

    var accentColor: Color {
        switch self {
        case .home:
            Color(red: 0.79, green: 0.57, blue: 0.23)
        case .lists:
            Color(red: 0.20, green: 0.50, blue: 0.93)
        case .recipes:
            Color(red: 0.91, green: 0.39, blue: 0.16)
        case .nutrients:
            Color(red: 0.18, green: 0.66, blue: 0.36)
        }
    }

    var secondaryAccentColor: Color {
        switch self {
        case .home:
            Color(red: 0.96, green: 0.78, blue: 0.44)
        case .lists:
            Color(red: 0.42, green: 0.73, blue: 0.98)
        case .recipes:
            Color(red: 0.98, green: 0.60, blue: 0.28)
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
}
