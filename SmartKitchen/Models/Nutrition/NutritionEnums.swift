import Foundation
import SwiftUI

// MARK: - Sex / Gender

enum NutritionSex: String, Codable, CaseIterable, Identifiable {
    case male
    case female
    case other

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .male:   "Masculino"
        case .female: "Feminino"
        case .other:  "Outro"
        }
    }

    var icon: String {
        switch self {
        case .male:   "figure.stand"
        case .female: "figure.stand.dress"
        case .other:  "person.fill"
        }
    }
}

// MARK: - Activity Level

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary
    case light
    case moderate
    case active
    case veryActive
    case extraActive

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .sedentary:   "Sedentário"
        case .light:       "Leve"
        case .moderate:    "Moderado"
        case .active:      "Ativo"
        case .veryActive:  "Muito ativo"
        case .extraActive: "Extremamente ativo"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .sedentary:   "Pouco ou nenhum exercício"
        case .light:       "Exercício leve 1–3x por semana"
        case .moderate:    "Exercício moderado 3–5x por semana"
        case .active:      "Exercício intenso 6–7x por semana"
        case .veryActive:  "Exercício muito intenso diário"
        case .extraActive: "Treino físico pesado ou trabalho manual"
        }
    }

    /// Multiplicador do TDEE sobre o BMR.
    var multiplier: Double {
        switch self {
        case .sedentary:   1.2
        case .light:       1.375
        case .moderate:    1.55
        case .active:      1.725
        case .veryActive:  1.9
        case .extraActive: 2.0
        }
    }
}

// MARK: - Weight Goal

enum WeightGoal: String, Codable, CaseIterable, Identifiable {
    case lose
    case maintain
    case gain

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .lose:     "Perder peso"
        case .maintain: "Manter peso"
        case .gain:     "Ganhar peso"
        }
    }

    var icon: String {
        switch self {
        case .lose:     "arrow.down.circle"
        case .maintain: "equal.circle"
        case .gain:     "arrow.up.circle"
        }
    }
}

// MARK: - Meal Type

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack
    case other

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .breakfast: "Café da manhã"
        case .lunch:     "Almoço"
        case .dinner:    "Jantar"
        case .snack:     "Lanche"
        case .other:     "Outra"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch:     "sun.max.fill"
        case .dinner:    "moon.fill"
        case .snack:     "cup.and.saucer.fill"
        case .other:     "fork.knife"
        }
    }

    var sortIndex: Int {
        switch self {
        case .breakfast: 0
        case .lunch:     1
        case .snack:     2
        case .dinner:    3
        case .other:     4
        }
    }

    /// Sugere o tipo de refeição mais provável conforme a hora do dia.
    static func suggestion(for date: Date = .now, calendar: Calendar = .current) -> MealType {
        switch calendar.component(.hour, from: date) {
        case 5..<11:  return .breakfast
        case 11..<15: return .lunch
        case 15..<18: return .snack
        case 18..<23: return .dinner
        default:      return .snack
        }
    }
}

// MARK: - Food Source

enum FoodSource: String, Codable, CaseIterable, Identifiable {
    case manual
    case snapFood
    case nutritionLabel
    case textInput
    case voiceInput
    case assistant

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .manual:          "Manual"
        case .snapFood:        "Foto"
        case .nutritionLabel:  "Rótulo"
        case .textInput:       "Texto"
        case .voiceInput:      "Voz"
        case .assistant:       "Assistente"
        }
    }

    var icon: String {
        switch self {
        case .manual:          "square.and.pencil"
        case .snapFood:        "camera"
        case .nutritionLabel:  "barcode.viewfinder"
        case .textInput:       "text.cursor"
        case .voiceInput:      "mic"
        case .assistant:       "sparkles"
        }
    }
}
