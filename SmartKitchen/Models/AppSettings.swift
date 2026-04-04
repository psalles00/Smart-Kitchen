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

enum ListGroupingMode: String, Codable, CaseIterable, Identifiable {
    case category
    case marketSection

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .category: "Categoria"
        case .marketSection: "Seção no Mercado"
        }
    }

    var icon: String {
        switch self {
        case .category: "square.grid.2x2"
        case .marketSection: "cart"
        }
    }
}

// MARK: - Settings Model (singleton)

@Model
final class AppSettings {
    var id: UUID = UUID()
    var pantryDetailLevel: PantryDetailLevel = PantryDetailLevel.simple
    /// Stored as the raw string of AccentColorChoice.
    var accentColorRaw: String = AccentColorChoice.green.rawValue
    var appearanceMode: AppearanceMode = AppearanceMode.system
    var recipeViewMode: RecipeViewMode = RecipeViewMode.gallery
    var expiringItemsLeadDays: Int = 30
    var recipeCompatibilityThresholdPercentValue: Int? = 80
    /// Embedded API key for OpenAI.
    var openAIAPIKey: String = ""
    var hasCompletedOnboarding: Bool = false
    var showUtensils: Bool = false
    var recipeGalleryColumns: Int = 2
    var pantryGroupingMode: ListGroupingMode = ListGroupingMode.category
    var groceryGroupingMode: ListGroupingMode = ListGroupingMode.marketSection

    init() {
        self.id = UUID()
        self.pantryDetailLevel = .simple
        self.accentColorRaw = AccentColorChoice.green.rawValue
        self.appearanceMode = .system
        self.recipeViewMode = .gallery
        self.recipeGalleryColumns = 2
        self.expiringItemsLeadDays = 30
        self.recipeCompatibilityThresholdPercentValue = 80
        self.openAIAPIKey = ""
        self.hasCompletedOnboarding = false
        self.showUtensils = false
        self.pantryGroupingMode = .category
        self.groceryGroupingMode = .marketSection
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
