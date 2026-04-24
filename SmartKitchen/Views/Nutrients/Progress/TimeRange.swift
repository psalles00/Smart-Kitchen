import Foundation

/// Faixas de tempo usadas nos gráficos de progresso de nutrição.
enum NutritionTimeRange: String, CaseIterable, Identifiable {
    case week = "1S"
    case month = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case year = "1A"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        case .sixMonths: 180
        case .year: 365
        }
    }

    var startDate: Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -(days - 1), to: start) ?? start
    }

    var xAxisStrideDays: Int {
        switch self {
        case .week: 1
        case .month: 5
        case .threeMonths: 14
        case .sixMonths: 30
        case .year: 60
        }
    }
}
