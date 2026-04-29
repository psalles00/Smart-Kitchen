import SwiftUI

/// Avaliação qualitativa do dia (e do período) baseada em quão próximo do
/// alvo de calorias o consumo está. Usada no header da aba Nutrição (ícone
/// substituindo a porcentagem) e replicada no topo da página de Progresso.
enum NutritionScore: Int, CaseIterable {
    case excellent = 0
    case good = 1
    case average = 2
    case needsImprovement = 3
    case noData = 4

    var systemImage: String {
        switch self {
        case .excellent:        return "medal.star"
        case .good:             return "hand.thumbsup"
        case .average:          return "hand.thumbsdown.hand.thumbsup"
        case .needsImprovement: return "hand.thumbsdown"
        case .noData:           return "questionmark.circle"
        }
    }

    var title: String {
        switch self {
        case .excellent:        return String(localized: "Excelente!")
        case .good:             return String(localized: "Indo bem!")
        case .average:          return String(localized: "Na média")
        case .needsImprovement: return String(localized: "Dá pra melhorar!")
        case .noData:           return String(localized: "Sem dados")
        }
    }

    var tint: Color {
        switch self {
        case .excellent:        return Color(red: 0.96, green: 0.78, blue: 0.20) // dourado
        case .good:             return PageTheme.nutrients.accentColor
        case .average:          return Color.orange
        case .needsImprovement: return Color.red
        case .noData:           return .secondary
        }
    }

    /// Mede um único dia: distância relativa do consumo à meta (0..1).
    /// - 0 → consumo igual à meta (excelente).
    /// - 1 → consumo zero ou ≥ 2× a meta (péssimo).
    private static func dayDistance(consumed: Int, goal: Int) -> Double {
        guard goal > 0 else { return 1 }
        let ratio = Double(consumed) / Double(goal)
        // simétrico: abaixo e acima penalizam.
        let diff = abs(ratio - 1.0)
        return min(diff, 1.0)
    }

    /// Score do dia atual baseado em calorias consumidas vs. meta.
    static func forDay(consumed: Int, goal: Int) -> NutritionScore {
        guard goal > 0 else { return .noData }
        let distance = dayDistance(consumed: consumed, goal: goal)
        switch distance {
        case ..<0.10:  return .excellent       // ±10%
        case ..<0.25:  return .good            // ±25%
        case ..<0.40:  return .average         // ±40%
        default:       return .needsImprovement
        }
    }

    /// Score agregado de uma janela: média das distâncias dos dias com registro.
    static func forPeriod(distances: [Double]) -> NutritionScore {
        guard !distances.isEmpty else { return .noData }
        let avg = distances.reduce(0, +) / Double(distances.count)
        switch avg {
        case ..<0.10:  return .excellent
        case ..<0.25:  return .good
        case ..<0.40:  return .average
        default:       return .needsImprovement
        }
    }

    static func dayDistanceValue(consumed: Int, goal: Int) -> Double {
        dayDistance(consumed: consumed, goal: goal)
    }
}
