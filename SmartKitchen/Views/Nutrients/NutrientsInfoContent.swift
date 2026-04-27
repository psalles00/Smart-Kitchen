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

                if profile?.hasCompletedOnboarding == true {
                    Text(statusLine)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.88))
                        .lineLimit(2)
                } else {
                    Text("Configure seu perfil para ver suas metas.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                }
            }

            Spacer()

            if profile?.hasCompletedOnboarding == true {
                Button(action: onTapScore) {
                    VStack(spacing: 4) {
                        Image(systemName: score.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .symbolRenderingMode(.hierarchical)

                        Text(score.title)
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: 92)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(score.title). Toque para ver progresso.")
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Composição de texto

    private var dateLine: String {
        let relative = relativeLabel(for: selectedDate)
        let full = fullDateString(for: selectedDate)
        return "\(relative) · \(full)"
    }

    private var statusLine: String {
        switch selectedDayState {
        case .future:           return "Dia futuro"
        case .todayEmpty:       return "Sem registros ainda"
        case .todayInProgress:  return "Registro em andamento"
        case .completed:        return "Dia concluído"
        case .pastInProgress:   return "Dia iniciado e não concluído"
        case .pastEmpty:        return "Sem registros neste dia"
        case .canceled:         return "Dia marcado como vazio"
        }
    }

    private func relativeLabel(for date: Date) -> String {
        if calendar.isDateInToday(date) { return "Hoje" }
        if calendar.isDateInYesterday(date) { return "Ontem" }
        if calendar.isDateInTomorrow(date) { return "Amanhã" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt-BR")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).localizedCapitalized
    }

    private func fullDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt-BR")
        formatter.dateFormat = "d 'de' MMMM"
        return formatter.string(from: date)
    }
}
