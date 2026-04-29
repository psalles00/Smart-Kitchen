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

    /// Cores discretas e modernas usadas para indicar status (sem bordas).
    private static let modernAmber = Color(red: 0.96, green: 0.78, blue: 0.26)
    private static let modernGreen = Color(red: 0.31, green: 0.74, blue: 0.46)

    /// Há fundo destacado para esse dia? Usado no week view (rounded rect)
    /// e no month view (circle) — apenas quando há significado real
    /// (hoje, em andamento, concluído) ou quando o dia está selecionado.
    private var hasFill: Bool {
        switch state {
        case .todayEmpty, .todayInProgress, .pastInProgress, .completed:
            return true
        default:
            return isSelected
        }
    }

    var body: some View {
        Button {
            guard !isFuture else { return }
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            onTap()
        } label: {
            content
                .opacity(isFuture ? 0.35 : 1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Layouts

    @ViewBuilder
    private var content: some View {
        if showWeekday {
            // Week view: rounded rect cobrindo dia da semana + número.
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(weekdayLabelColor)
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(numberColor)
                    .strikethrough(state == .canceled, color: .secondary)
            }
            .padding(.vertical, 6)
            .frame(width: 38)
            .background {
                if hasFill {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(stateBackgroundColor)
                } else if showsDottedOutline {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            Color.secondary.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])
                        )
                }
            }
        } else {
            // Month view: continua usando círculo, sem borda — exceto pelos
            // dias passados sem registros, que recebem uma borda pontilhada
            // sutil para indicar que existem (mas estão vazios).
            ZStack {
                if hasFill {
                    Circle().fill(stateBackgroundColor)
                } else if showsDottedOutline {
                    Circle()
                        .strokeBorder(
                            Color.secondary.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])
                        )
                }
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(numberColor)
                    .strikethrough(state == .canceled, color: .secondary)
            }
            .frame(width: 32, height: 32)
        }
    }

    /// Mostra apenas em dias que não estão ativos/preenchidos e não são futuros:
    /// hoje sem registros nunca cai aqui (tem fundo cinza), futuro fica dimmed.
    /// Sobra o caso `pastEmpty` (passado sem registros) — exatamente o pedido.
    private var showsDottedOutline: Bool {
        guard !hasFill, !isFuture else { return false }
        switch state {
        case .pastEmpty:
            return true
        default:
            return false
        }
    }

    // MARK: - Color mapping

    private var stateBackgroundColor: Color {
        // Estados com significado vencem qualquer destaque de seleção.
        switch state {
        case .todayInProgress, .pastInProgress:
            return Self.modernAmber.opacity(isSelected ? 0.32 : 0.22)
        case .completed:
            return Self.modernGreen.opacity(isSelected ? 0.32 : 0.22)
        case .todayEmpty:
            return Self.todayNeutralFill
        default:
            // Selecionado sem estado especial: sutil indicador neutro.
            return isSelected ? Self.todayNeutralFill : .clear
        }
    }

    /// Cinza neutro #F8F8FA (com fallback para modo escuro).
    private static var todayNeutralFill: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.secondarySystemBackground
                : UIColor(red: 248/255, green: 248/255, blue: 250/255, alpha: 1)
        })
        #else
        return neutralSurfaceColor
        #endif
    }

    private var numberColor: Color {
        switch state {
        case .future:           return .secondary
        case .canceled:         return .secondary
        case .pastEmpty:        return .secondary
        case .completed:        return Self.modernGreen
        case .todayInProgress, .pastInProgress: return .primary
        default:                return .primary
        }
    }

    private var weekdayLabelColor: Color {
        if state == .completed { return Self.modernGreen.opacity(0.9) }
        return isSelected ? .primary : .secondary
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
