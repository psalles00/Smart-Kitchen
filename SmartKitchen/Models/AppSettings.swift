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
    case validade

    var id: String { rawValue }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = ListGroupingMode(rawValue: raw) ?? .category
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var displayName: LocalizedStringKey {
        switch self {
        case .category: "Categoria"
        case .marketSection: "Seção no Mercado"
        case .validade: "Validade"
        }
    }

    var icon: String {
        switch self {
        case .category: "square.grid.2x2"
        case .marketSection: "cart"
        case .validade: "calendar"
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
    /// Quando true (padrão), o modo Ideias de receitas só sugere receitas que
    /// usem itens presentes na despensa. Optional para resiliência a migrações.
    var recipeIdeasFilterByPantryValue: Bool? = true
    /// Embedded API key for OpenAI.
    var openAIAPIKey: String = ""
    var hasCompletedOnboarding: Bool = false
    var showUtensils: Bool = false
    var recipeGalleryColumns: Int = 3
    /// Stored as raw strings to keep persisted settings resilient to schema changes.
    var pantryGroupingModeRaw: String = ListGroupingMode.category.rawValue
    var groceryGroupingModeRaw: String = ListGroupingMode.marketSection.rawValue
    var lastAddItemDestinationRaw: String = AddItemDestination.grocery.rawValue

    // MARK: - Notifications
    var notificationsEnabled: Bool = true
    var expiryNotificationsEnabled: Bool = true
    /// JSON-encoded array of Int (days before expiry to notify). Default: [3, 1, 0]
    var expiryReminderDaysJSON: String = "[3, 1, 0]"
    /// Hour of day (0-23) to deliver expiry notifications.
    var expiryNotificationHour: Int = 9
    var lowStockNotificationsEnabled: Bool = false

    init() {
        self.id = UUID()
        self.pantryDetailLevel = .simple
        self.accentColorRaw = AccentColorChoice.green.rawValue
        self.appearanceMode = .system
        self.recipeViewMode = .gallery
        self.recipeGalleryColumns = 3
        self.expiringItemsLeadDays = 30
        self.recipeCompatibilityThresholdPercentValue = 80
        self.recipeIdeasFilterByPantryValue = true
        self.openAIAPIKey = ""
        self.hasCompletedOnboarding = false
        self.showUtensils = false
        self.pantryGroupingModeRaw = ListGroupingMode.category.rawValue
        self.groceryGroupingModeRaw = ListGroupingMode.marketSection.rawValue
        self.lastAddItemDestinationRaw = AddItemDestination.grocery.rawValue
        self.notificationsEnabled = true
        self.expiryNotificationsEnabled = true
        self.expiryReminderDaysJSON = "[3, 1, 0]"
        self.expiryNotificationHour = 9
        self.lowStockNotificationsEnabled = false
    }

    @Transient
    var expiryReminderDays: [Int] {
        get {
            (try? JSONDecoder().decode([Int].self, from: Data(expiryReminderDaysJSON.utf8))) ?? [3, 1, 0]
        }
        set {
            expiryReminderDaysJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[3, 1, 0]"
        }
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

    @Transient
    var recipeIdeasFilterByPantry: Bool {
        get { recipeIdeasFilterByPantryValue ?? true }
        set { recipeIdeasFilterByPantryValue = newValue }
    }

    @Transient
    var pantryGroupingMode: ListGroupingMode {
        get { ListGroupingMode(rawValue: pantryGroupingModeRaw) ?? .category }
        set { pantryGroupingModeRaw = newValue.rawValue }
    }

    @Transient
    var groceryGroupingMode: ListGroupingMode {
        get { ListGroupingMode(rawValue: groceryGroupingModeRaw) ?? .marketSection }
        set { groceryGroupingModeRaw = newValue.rawValue }
    }
}
