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
        let kcal: Double  // 0 means "skipped" — drawn as a faint placeholder
    }

    private let days: [Day] = [
        .init(label: "S", kcal: 1840),
        .init(label: "T", kcal: 2120),
        .init(label: "Q", kcal: 0),
        .init(label: "Q", kcal: 1980),
        .init(label: "S", kcal: 2210),
        .init(label: "S", kcal: 0),
        .init(label: "D", kcal: 1650),
    ]

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 16)

            chartCard
                .padding(.horizontal, 24)
                .frame(height: 240)

            OnboardingHeader(
                title: String(localized: "Calorias sem culpa."),
                subtitle: String(localized: "Conte macros nos dias que quiser. A IA do Smart Kitchen entende as lacunas e ainda dá ideias de receita com o que você tem em casa.")
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
                    Text(String(localized: "Esta semana"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("11.800 kcal")
                        .font(.cardTitle)
                }
                Spacer()
                aiChip
            }

            Chart {
                ForEach(Array(days.enumerated()), id: \.offset) { idx, day in
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
                        BarMark(
                            x: .value("Dia", day.label),
                            y: .value("kcal", 600)
                        )
                        .foregroundStyle(Color.secondary.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .annotation(position: .top, alignment: .center) {
                            Text("—")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
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
