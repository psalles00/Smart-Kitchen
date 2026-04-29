import Foundation

/// Macros consumidos em um único dia (snapshot agregado).
struct DayMacros: Equatable {
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = DayMacros(calories: 0, protein: 0, carbs: 0, fat: 0)
}

/// Base utilizada para apresentar a média ao usuário.
enum NutritionAverageBasis: Equatable {
    /// Média calculada apenas com dias concluídos do mesmo dia da semana.
    case perWeekday(weekday: Int, sample: Int)
    /// Média do grupo (útil seg–qui ou fim de semana sex–dom) — fallback.
    case group(isWeekend: Bool, sample: Int)
    /// Média geral de todos os dias concluídos — fallback final.
    case overall(sample: Int)
    /// Sem dados suficientes.
    case none
}

struct NutritionAverageResult: Equatable {
    var macros: DayMacros
    var basis: NutritionAverageBasis
}

/// Calcula médias diárias de macros a partir de dias já agregados.
///
/// A lógica usa três camadas de fallback:
/// 1. Média do mesmo dia da semana (ex.: "média de quartas-feiras") quando há
///    pelo menos um dia comparável daquele weekday no histórico.
/// 2. Caso contrário, média do grupo a que o dia pertence:
///    - Dias úteis: segunda, terça, quarta, quinta (Calendar weekday 2..5).
///    - Fim de semana: sexta, sábado, domingo (Calendar weekday 6, 7, 1).
///    O agrupamento "sex+sab+dom" é intencional — sextas costumam se comportar
///    socialmente como fim de semana (jantares fora, etc.).
/// 3. Caso ainda não haja dados, média geral de todos os dias disponíveis.
/// 4. Se nem isso existir, retorna `.none`.
enum NutritionAveragesService {

    /// Constrói um dicionário `[diaInicio: macros]` a partir de qualquer dia com
    /// registro de alimento. Essa base é usada pela tela de Progresso para começar
    /// a gerar médias já no primeiro dia preenchido.
    static func recordedDayMacros(
        entries: [FoodEntry],
        startDate: Date? = nil,
        calendar: Calendar = .current
    ) -> [Date: DayMacros] {
        var totals: [Date: DayMacros] = [:]

        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            if let startDate, day < calendar.startOfDay(for: startDate) {
                continue
            }

            var current = totals[day] ?? .zero
            current.calories += entry.calories
            current.protein += entry.proteinG
            current.carbs += entry.carbsG
            current.fat += entry.fatG
            totals[day] = current
        }

        return totals
    }

    /// Constrói um dicionário `[diaInicio: macros]` para os dias concluídos no
    /// range fornecido. Usa `NutritionDayLog` como fonte de verdade.
    static func completedDayMacros(
        entries: [FoodEntry],
        logs: [NutritionDayLog],
        startDate: Date? = nil,
        calendar: Calendar = .current
    ) -> [Date: DayMacros] {
        let completedDays: Set<Date> = Set(
            logs
                .filter { $0.isCompleted }
                .map { calendar.startOfDay(for: $0.dayStart) }
                .filter { day in
                    guard let start = startDate else { return true }
                    return day >= calendar.startOfDay(for: start)
                }
        )

        guard !completedDays.isEmpty else { return [:] }

        var totals: [Date: DayMacros] = [:]
        for day in completedDays { totals[day] = .zero }

        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            guard completedDays.contains(day) else { continue }
            var current = totals[day] ?? .zero
            current.calories += entry.calories
            current.protein += entry.proteinG
            current.carbs += entry.carbsG
            current.fat += entry.fatG
            totals[day] = current
        }
        return totals
    }

    /// Retorna a média de macros para um dia-alvo (usa o `weekday` do alvo para
    /// escolher o bucket). Quando `targetDate` é `nil`, retorna média geral.
    static func average(
        for targetDate: Date?,
        dayMacros totals: [Date: DayMacros],
        calendar: Calendar = .current
    ) -> NutritionAverageResult {
        guard !totals.isEmpty else {
            return NutritionAverageResult(macros: .zero, basis: .none)
        }

        // Camada 1 — média do mesmo dia da semana.
        if let target = targetDate {
            let targetWeekday = calendar.component(.weekday, from: target)
            let sameWeekday = totals.filter { calendar.component(.weekday, from: $0.key) == targetWeekday }
            if !sameWeekday.isEmpty {
                return NutritionAverageResult(
                    macros: mean(of: Array(sameWeekday.values)),
                    basis: .perWeekday(weekday: targetWeekday, sample: sameWeekday.count)
                )
            }

            // Camada 2 — grupo útil/fim de semana.
            let targetIsWeekend = isWeekendBucket(weekday: targetWeekday)
            let group = totals.filter {
                isWeekendBucket(weekday: calendar.component(.weekday, from: $0.key)) == targetIsWeekend
            }
            if !group.isEmpty {
                return NutritionAverageResult(
                    macros: mean(of: Array(group.values)),
                    basis: .group(isWeekend: targetIsWeekend, sample: group.count)
                )
            }
        }

        // Camada 3 — média geral.
        return NutritionAverageResult(
            macros: mean(of: Array(totals.values)),
            basis: .overall(sample: totals.count)
        )
    }

    // MARK: - Helpers

    /// Sex/Sab/Dom = fim de semana. Seg/Ter/Qua/Qui = dia útil.
    /// Comentário: classificar sexta como fim de semana é uma decisão de produto
    /// — o padrão alimentar de sexta tende a se aproximar do fim de semana.
    static func isWeekendBucket(weekday: Int) -> Bool {
        // Calendar.weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday.
        // Útil = 2,3,4,5 ; Fim de semana = 6,7,1 (sex, sab, dom).
        switch weekday {
        case 2, 3, 4, 5: return false
        default:         return true
        }
    }

    static func mean(of values: [DayMacros]) -> DayMacros {
        guard !values.isEmpty else { return .zero }
        let count = Double(values.count)
        let totalKcal = values.reduce(0) { $0 + $1.calories }
        let totalP = values.reduce(0.0) { $0 + $1.protein }
        let totalC = values.reduce(0.0) { $0 + $1.carbs }
        let totalF = values.reduce(0.0) { $0 + $1.fat }
        return DayMacros(
            calories: Int((Double(totalKcal) / count).rounded()),
            protein: totalP / count,
            carbs: totalC / count,
            fat: totalF / count
        )
    }
}

// MARK: - Display helpers

extension NutritionAverageBasis {
    /// Texto curto em pt-BR para badges ("Média de quartas-feiras", etc.).
    var shortDescription: String {
        switch self {
        case .perWeekday(let weekday, _):
            return String(localized: "Média de \(Self.weekdayName(weekday).lowercased())")
        case .group(let isWeekend, _):
            return isWeekend ? String(localized: "Média de fim de semana") : String(localized: "Média de dias úteis")
        case .overall:
            return String(localized: "Média geral")
        case .none:
            return String(localized: "Sem dados")
        }
    }

    var sampleSize: Int {
        switch self {
        case .perWeekday(_, let n), .group(_, let n), .overall(let n): return n
        case .none: return 0
        }
    }

    private static func weekdayName(_ weekday: Int) -> String {
        // Plural: "domingos", "segundas-feiras", etc.
        switch weekday {
        case 1: return String(localized: "domingos")
        case 2: return String(localized: "segundas-feiras")
        case 3: return String(localized: "terças-feiras")
        case 4: return String(localized: "quartas-feiras")
        case 5: return String(localized: "quintas-feiras")
        case 6: return String(localized: "sextas-feiras")
        case 7: return String(localized: "sábados")
        default: return String(localized: "dias")
        }
    }
}
