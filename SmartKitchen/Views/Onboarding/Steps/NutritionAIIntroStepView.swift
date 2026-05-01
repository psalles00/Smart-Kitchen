import SwiftUI
import Charts

/// Phase 1 — Step 4. Communicates: "Calorias sem culpa" + "Assistente IA".
/// Shows an animated weekly bar chart where some days are intentionally
/// blank ("sem obrigação"), plus a pulsing AI chip badge.
struct NutritionAIIntroStepView: View {
    let onContinue: () -> Void

    @State private var animationKey = 0

    private struct Day: Identifiable {
        let id = UUID()
        let label: String
        let kcal: Double  // 0 means "skipped" — drawn as a dotted skeleton
    }

    /// Only logged days carry a value; unlogged days are intentionally
    /// blank so the chart visually reinforces "we ignore missing days".
    private let days: [Day] = [
        .init(label: "S", kcal: 1840),
        .init(label: "T", kcal: 2120),
        .init(label: "Q", kcal: 0),
        .init(label: "Q", kcal: 1980),
        .init(label: "S", kcal: 0),
        .init(label: "S", kcal: 2210),
        .init(label: "D", kcal: 1650),
    ]

    /// Smart average uses logged days only.
    private var loggedAverage: Int {
        let logged = days.filter { $0.kcal > 0 }
        guard !logged.isEmpty else { return 0 }
        return Int(logged.map(\.kcal).reduce(0, +) / Double(logged.count))
    }

    private var loggedDaysCount: Int {
        days.filter { $0.kcal > 0 }.count
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 16)

            chartCard
                .padding(.horizontal, 24)
                .frame(height: 240)

            OnboardingHeader(
                title: String(localized: "Pulou um dia? Sem problema."),
                subtitle: String(localized: "O Savoria calcula uma média inteligente apenas com os dias que você registrou — nada de zerar sua semana porque você esqueceu de logar.")
            )

            Spacer()

            OnboardingPrimaryButton(
                title: String(localized: "Continuar"),
                action: onContinue
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .onAppear { animationKey &+= 1 }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Média de \(loggedDaysCount) dias registrados"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(loggedAverage)")
                            .font(.cardTitle)
                        Text("kcal/dia")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                aiChip
            }

            Chart {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if day.kcal > 0 {
                        BarMark(
                            x: .value("Dia", day.label),
                            y: .value("kcal", day.kcal)
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [Color.primary, Color.primary.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        // Unlogged day: dashed skeleton, no annotation.
                        BarMark(
                            x: .value("Dia", day.label),
                            yStart: .value("zero", 0),
                            yEnd: .value("kcal", 2400)
                        )
                        .foregroundStyle(Color.clear)
                        .annotation(position: .overlay, alignment: .center) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    Color.secondary.opacity(0.35),
                                    style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])
                                )
                                .frame(height: 90)
                        }
                    }
                }

                RuleMark(y: .value("Média", Double(loggedAverage)))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(String(localized: "Média"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(preset: .aligned) { _ in
                    AxisValueLabel()
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .id(animationKey) // re-trigger entrance animation on appear
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(neutralSurfaceColor)
        )
    }

    private var aiChip: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = sin(t * 2.4) * 0.5 + 0.5

            HStack(spacing: 6) {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.purple, Color.blue],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.purple.opacity(0.5 + pulse * 0.4), radius: 6 + pulse * 4)
                Text(String(localized: "Assistente IA"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.primary.opacity(0.06))
            )
        }
    }
}
