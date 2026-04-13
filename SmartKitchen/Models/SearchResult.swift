import Foundation

/// The type of entity a search result represents.
enum SearchResultType: String {
    case pantryItem
    case groceryItem
    case recipe
    case utensil
    case suggestion   // from ItemDatabase (not yet added)
    case action       // create, ask assistant, etc.
}

/// A unified search result returned by `UniversalSearchService`.
struct SearchResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String            // SF Symbol or icon filename
    let type: SearchResultType
    let score: Double           // higher = better match
    let objectID: UUID?         // reference to the underlying SwiftData model
    let iconFilename: String?   // for custom icon images (items_database)
    /// Whether the item with the same name exists in the other list too.
    var isAlsoInOtherList: Bool = false

    /// Section label displayed as a badge next to the result.
    var typeLabel: String {
        switch type {
        case .pantryItem:  "Despensa"
        case .groceryItem: "Mercado"
        case .recipe:      "Receita"
        case .utensil:     "Utensílio"
        case .suggestion:  "Sugestão"
        case .action:      ""
        }
    }

    /// Secondary label for items in both lists.
    var secondaryTypeLabel: String? {
        guard isAlsoInOtherList else { return nil }
        switch type {
        case .pantryItem: return "Mercado"
        case .groceryItem: return "Despensa"
        default: return nil
        }
    }

    /// Accent color key for the type badge.
    var typeTint: String {
        switch type {
        case .pantryItem:  "orange"
        case .groceryItem: "green"
        case .recipe:      "red"
        case .utensil:     "purple"
        case .suggestion:  "blue"
        case .action:      "gray"
        }
    }

    var secondaryTypeTint: String? {
        guard isAlsoInOtherList else { return nil }
        switch type {
        case .pantryItem: return "green"
        case .groceryItem: return "orange"
        default: return nil
        }
    }
}

/// A recent action tracked for the Command Bar empty state.
struct RecentAction: Codable, Identifiable {
    let id: UUID
    let title: String
    let type: String          // matches SearchResultType rawValue
    let objectID: UUID?
    let iconName: String?
    let timestamp: Date

    init(title: String, type: SearchResultType, objectID: UUID? = nil, iconName: String? = nil) {
        self.id = UUID()
        self.title = title
        self.type = type.rawValue
        self.objectID = objectID
        self.iconName = iconName
        self.timestamp = .now
    }
}
