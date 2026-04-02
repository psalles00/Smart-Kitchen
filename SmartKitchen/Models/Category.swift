import Foundation
import SwiftData
import SwiftUI

enum CategoryType: String, Codable, CaseIterable, Identifiable {
    case pantry
    case grocery
    case recipe
    case utensil

    var id: String { rawValue }

    var canonicalType: CategoryType {
        switch self {
        case .pantry, .grocery: .pantry
        case .recipe: .recipe
        case .utensil: .utensil
        }
    }

    var isListType: Bool {
        switch self {
        case .pantry, .grocery, .utensil: true
        case .recipe: false
        }
    }

    var displayName: LocalizedStringKey {
        switch self {
        case .pantry: "Despensa"
        case .grocery: "Mercado"
        case .recipe: "Receitas"
        case .utensil: "Utensílios"
        }
    }
}

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var type: CategoryType = CategoryType.pantry
    var iconName: String? = nil
    var sortOrder: Int = 0

    init(name: String, type: CategoryType, iconName: String? = nil, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.iconName = iconName
        self.sortOrder = sortOrder
    }
}
