import Foundation
import SwiftData
import SwiftUI

enum CategoryType: String, Codable, CaseIterable, Identifiable {
    case pantry
    case grocery
    case recipe

    var id: String { rawValue }

    var canonicalType: CategoryType {
        switch self {
        case .pantry, .grocery: .pantry
        case .recipe: .recipe
        }
    }

    var isListType: Bool {
        switch self {
        case .pantry, .grocery: true
        case .recipe: false
        }
    }

    var displayName: LocalizedStringKey {
        switch self {
        case .pantry: "Despensa"
        case .grocery: "Mercado"
        case .recipe: "Receitas"
        }
    }
}

@Model
final class Category {
    var id: UUID
    var name: String
    var type: CategoryType
    var iconName: String?
    var sortOrder: Int

    init(name: String, type: CategoryType, iconName: String? = nil, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.iconName = iconName
        self.sortOrder = sortOrder
    }
}
