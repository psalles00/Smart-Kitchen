import SwiftUI

/// Bloco informativo exibido na faixa colorida do header da aba Nutrição.
/// - Linha 1: data relativa + data completa do dia selecionado.
/// - Linha 2: status do dia (mesmo texto que aparece no banner do dashboard).
/// - Direita: ícone qualitativo (`NutritionScore`) — toque abre a página de Progresso.
struct NutrientsInfoContent: View {
    var profile: NutritionProfile? = nil
    var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    var selectedDayState: NutritionDayState = .todayEmpty
    var caloriesConsumed: Int = 0
    var onTapScore: () -> Void = {}

    private var calendar: Calendar { .current }
    private var goal: Int { profile?.effectiveCalories ?? 0 }
    private let secondaryLineOpacity: Double = 0.85

    private var score: NutritionScore {
        guard goal > 0 else { return .noData }
        switch selectedDayState {
        case .todayEmpty, .pastEmpty, .canceled, .future:
            return .noData
        case .todayInProgress, .pastInProgress, .completed:
            return NutritionScore.forDay(consumed: caloriesConsumed, goal: goal)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateLine)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 4)

                if profile?.hasCompletedOnboarding == true {
                    Text(statusLine)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(secondaryLineOpacity))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else {
                    Text("Configure seu perfil para ver suas metas.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(secondaryLineOpacity))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            Spacer()

            if profile?.hasCompletedOnboarding == true {
                Button(action: onTapScore) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: score.systemImage)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .symbolRenderingMode(.hierarchical)

                        Text(score.title)
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(width: 92, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "\(score.title). Toque para ver progresso."))
            }
        }
        .padding(.bottom, 4)
        .frame(height: ExpandedPageHeaderMetrics.iosCompactInfoHeight)
    }

    // MARK: - Composição de texto

    private var dateLine: String {
        let relative = relativeLabel(for: selectedDate)
        let full = fullDateString(for: selectedDate)
        return String(localized: "\(relative) · \(full)")
    }

    private var statusLine: String {
        switch selectedDayState {
        case .future:           return String(localized: "Dia futuro")
        case .todayEmpty:       return String(localized: "Sem registros ainda")
        case .todayInProgress:  return String(localized: "Registro em andamento")
        case .completed:        return String(localized: "Dia concluído")
        case .pastInProgress:   return String(localized: "Dia iniciado e não concluído")
        case .pastEmpty:        return String(localized: "Sem registros neste dia")
        case .canceled:         return String(localized: "Dia marcado como vazio")
        }
    }

    private func relativeLabel(for date: Date) -> String {
        if calendar.isDateInToday(date) { return String(localized: "Hoje") }
        if calendar.isDateInYesterday(date) { return String(localized: "Ontem") }
        if calendar.isDateInTomorrow(date) { return String(localized: "Amanhã") }
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.current().formattingLocale
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).localizedCapitalized
    }

    private func fullDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.current().formattingLocale
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return formatter.string(from: date)
    }
}
