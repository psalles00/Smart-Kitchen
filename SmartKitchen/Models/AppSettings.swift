import Foundation
import SwiftData
import SwiftUI

// MARK: - Enums

enum PantryDetailLevel: String, Codable, CaseIterable, Identifiable {
    case simple   // Name only
    case detailed // Name + quantity + unit

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .simple:   "Simples"
        case .detailed: "Detalhado"
        }
    }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .system: "Sistema"
        case .light:  "Claro"
        case .dark:   "Escuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }
}

enum RecipeViewMode: String, Codable, CaseIterable, Identifiable {
    case gallery
    case list

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .gallery: "Galeria"
        case .list:    "Lista"
        }
    }

    var icon: String {
        switch self {
        case .gallery: "square.grid.2x2"
        case .list:    "list.bullet"
        }
    }
}

enum ListsSortOption: String, Codable, CaseIterable, Identifiable {
    case custom
    case name
    case addedAt
    case expirationDate

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .custom: "Personalizada"
        case .name: "Nome"
        case .addedAt: "Data"
        case .expirationDate: "Validade"
        }
    }
}

// MARK: - Settings Model (singleton)

@Model
final class AppSettings {
    var id: UUID
    var pantryDetailLevel: PantryDetailLevel
    /// Stored as the raw string of AccentColorChoice.
    var accentColorRaw: String
    var appearanceMode: AppearanceMode
    var recipeViewMode: RecipeViewMode
    var expiringItemsLeadDays: Int
    var recipeCompatibilityThresholdPercentValue: Int?
    /// Embedded API key for OpenAI.
    var openAIAPIKey: String
    var hasCompletedOnboarding: Bool

    init() {
        self.id = UUID()
        self.pantryDetailLevel = .simple
        self.accentColorRaw = AccentColorChoice.green.rawValue
        self.appearanceMode = .system
        self.recipeViewMode = .gallery
        self.expiringItemsLeadDays = 30
        self.recipeCompatibilityThresholdPercentValue = 80
        self.openAIAPIKey = ""
        self.hasCompletedOnboarding = false
    }

    @Transient
    var accentColorChoice: AccentColorChoice {
        get { AccentColorChoice(rawValue: accentColorRaw) ?? .green }
        set { accentColorRaw = newValue.rawValue }
    }

    @Transient
    var recipeCompatibilityThresholdPercent: Int {
        get { recipeCompatibilityThresholdPercentValue ?? 80 }
        set { recipeCompatibilityThresholdPercentValue = newValue }
    }
}
