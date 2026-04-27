import SwiftUI

/// Tile reutilizável para a week bar e o calendário mensal de Nutrição.
///
/// O tile representa um dia e adapta cores/ações conforme o `NutritionDayState`:
/// - hoje vazio   → cinza neutro (sem destaque verde — o destaque agora é só dos concluídos).
/// - hoje em andamento → fundo amarelo discreto.
/// - concluído   → fundo verde (accent de Nutrição).
/// - passado pendente (com ou sem registros) → fundo vermelho discreto.
/// - cancelado   → cinza levemente riscado.
/// - futuro      → bem dimmed, não interativo.
///
/// O ring de progresso só aparece quando faz sentido (hoje em andamento ou concluído).
struct NutritionDayTile: View {
    let date: Date
    let state: NutritionDayState
    let progress: Double
    let isSelected: Bool
    let showWeekday: Bool
    let onTap: () -> Void

    init(
        date: Date,
        state: NutritionDayState,
        progress: Double,
        isSelected: Bool,
        showWeekday: Bool = true,
        onTap: @escaping () -> Void
    ) {
        self.date = date
        self.state = state
        self.progress = progress
        self.isSelected = isSelected
        self.showWeekday = showWeekday
        self.onTap = onTap
    }

    private var isFuture: Bool { state == .future }

    var body: some View {
        Button {
            guard !isFuture else { return }
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            onTap()
        } label: {
            VStack(spacing: 4) {
                if showWeekday {
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(weekdayLabelColor)
                }

                ZStack {
                    backgroundLayer
                    ringLayer
                    Text(date.formatted(.dateTime.day()))
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(numberColor)
                        .strikethrough(state == .canceled, color: .secondary)
                }
                .frame(width: 36, height: 36)
                .overlay {
                    if isSelected {
                        Circle().stroke(Color.primary.opacity(0.4), lineWidth: 1.2)
                    }
                }
            }
            .opacity(isFuture ? 0.35 : 1)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Layers

    @ViewBuilder
    private var backgroundLayer: some View {
        let baseColor = stateBackgroundColor
        Circle().fill(baseColor)
        // Borda sutil para reforçar o contorno do dia.
        Circle().stroke(stateBorderColor, lineWidth: 1)
    }

    @ViewBuilder
    private var ringLayer: some View {
        // Ring só faz sentido para dias com consumo registrado (em andamento ou concluído).
        if state == .todayInProgress || state == .completed {
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1.0)))
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }

    // MARK: - Color mapping

    private var stateBackgroundColor: Color {
        switch state {
        case .future:           return Color.secondary.opacity(0.06)
        case .todayEmpty:       return Color.secondary.opacity(0.10)
        case .todayInProgress:  return Color.yellow.opacity(0.18)
        case .completed:        return PageTheme.nutrients.accentColor.opacity(0.18)
        case .pastInProgress:   return Color.yellow.opacity(0.18)
        case .pastEmpty:        return Color.secondary.opacity(0.08)
        case .canceled:         return Color.secondary.opacity(0.08)
        }
    }

    private var stateBorderColor: Color {
        switch state {
        case .future, .todayEmpty, .canceled, .pastEmpty: return Color.secondary.opacity(0.18)
        case .todayInProgress, .pastInProgress:           return Color.yellow.opacity(0.45)
        case .completed:                                  return PageTheme.nutrients.accentColor.opacity(0.55)
        }
    }

    private var ringColor: Color {
        switch state {
        case .completed:                          return PageTheme.nutrients.accentColor
        case .todayInProgress, .pastInProgress:   return Color.yellow
        default:                                  return .clear
        }
    }

    private var numberColor: Color {
        switch state {
        case .future:           return .secondary
        case .canceled:         return .secondary
        case .pastEmpty:        return .secondary
        case .completed:        return PageTheme.nutrients.accentColor
        default:                return .primary
        }
    }

    private var weekdayLabelColor: Color {
        isSelected ? .primary : .secondary
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        let day = date.formatted(date: .abbreviated, time: .omitted)
        let stateText: String
        switch state {
        case .future:          stateText = "futuro"
        case .todayEmpty:      stateText = "hoje, sem registros"
        case .todayInProgress: stateText = "hoje, em andamento"
        case .completed:       stateText = "concluído"
        case .pastInProgress:  stateText = "iniciado e pendente"
        case .pastEmpty:       stateText = "sem registros, pendente"
        case .canceled:        stateText = "cancelado"
        }
        return "\(day), \(stateText)"
    }
}
