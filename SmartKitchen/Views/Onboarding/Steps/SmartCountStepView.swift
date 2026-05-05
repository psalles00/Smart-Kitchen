import SwiftUI

/// Phase 1 — Step 5. "Esqueceu de logar? Sem drama." Mostra 7 mini cards
/// (semana), 2 ficam vazios; uma linha pontilhada indica a média estimada
/// só com os dias logados; um selo "Contagem inteligente" surge.
struct SmartCountStepView: View {
    let onContinue: () -> Void

    @State private var revealedCards: Int = 0
    @State private var showAverageLine: Bool = false
    @State private var showBadge: Bool = false
    @State private var showHero = false
    @State private var showHeader = false
    @State private var showButton = false
    @State private var entranceTask: Task<Void, Never>? = nil
    @State private var loopTask: Task<Void, Never>? = nil

    private let days: [SmartDayMock] = [
        .init(label: String(localized: "Seg"), kcal: 1820, logged: true),
        .init(label: String(localized: "Ter"), kcal: 0,    logged: false),
        .init(label: String(localized: "Qua"), kcal: 1940, logged: true),
        .init(label: String(localized: "Qui"), kcal: 1750, logged: true),
        .init(label: String(localized: "Sex"), kcal: 0,    logged: false),
        .init(label: String(localized: "Sáb"), kcal: 2010, logged: true),
        .init(label: String(localized: "Dom"), kcal: 1880, logged: true),
    ]

    private var loggedAverage: Int {
        let logged = days.filter { $0.logged }
        let sum = logged.reduce(0) { $0 + $1.kcal }
        return logged.isEmpty ? 0 : Int(Double(sum) / Double(logged.count))
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)

            stage
                .padding(.horizontal, 18)
                .frame(height: 360)
                .opacity(showHero ? 1 : 0)
                .scaleEffect(showHero ? 1 : 0.94)
                .animation(.spring(response: 0.85, dampingFraction: 0.84), value: showHero)

            VStack(spacing: 0) {
            VStack(spacing: 12) {
                OnboardingFeatureChip(
                    icon: "flame.fill",
                    title: String(localized: "Calorias e macros"),
                    tint: Color(red: 0.55, green: 0.50, blue: 0.96)
                )
                .opacity(showHeader ? 1 : 0)
                .animation(.spring(response: 0.7, dampingFraction: 0.86), value: showHeader)

                OnboardingHeader(
                    title: String(localized: "Esqueceu de registrar um dia? Sem drama."),
                    subtitle: String(localized: "Calculamos sua média só com os dias que você logou.")
                )
                .opacity(showHeader ? 1 : 0)
                .offset(y: showHeader ? 0 : 14)
                .animation(.spring(response: 0.7, dampingFraction: 0.86), value: showHeader)
            }

                Spacer(minLength: 14)

                OnboardingPrimaryButton(
                    title: String(localized: "Continuar"),
                    action: onContinue
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 18)
                .animation(.spring(response: 0.74, dampingFraction: 0.86), value: showButton)
            }
        }
        .onAppear { beginEntrance() }
        .onDisappear {
            entranceTask?.cancel(); entranceTask = nil
            loopTask?.cancel(); loopTask = nil
        }
    }

    // MARK: - Stage

    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(neutralSurfaceColor)
                .shadow(color: .black.opacity(0.05), radius: 16, y: 8)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(String(localized: "Última semana"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if showBadge {
                        smartBadge
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                ZStack(alignment: .top) {
                    daysRow
                    if showAverageLine {
                        averageLine
                            .transition(.opacity)
                    }
                }
                .frame(height: 180)

                summaryCard
            }
            .padding(18)
        }
    }

    private var daysRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                if index < revealedCards {
                    DayCard(day: day, average: loggedAverage)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    DayCard(day: day, average: loggedAverage)
                        .opacity(0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var averageLine: some View {
        GeometryReader { proxy in
            // Average line crosses ~middle horizontally
            let y = proxy.size.height * 0.45
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 4, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width - 4, y: y))
                }
                .stroke(
                    Color.accentColor.opacity(0.85),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [4, 4])
                )

                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 9, weight: .bold))
                    Text("\(loggedAverage) kcal · " + String(localized: "média"))
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor))
                .position(x: proxy.size.width / 2, y: y - 12)
            }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Sua média não cai por dias em branco"))
                    .font(.system(size: 12, weight: .semibold))
                Text(String(localized: "Contamos apenas os dias com registro real."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.green.opacity(0.10))
        )
    }

    private var smartBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .bold))
            Text(String(localized: "Contagem inteligente"))
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [Color(red: 0.55, green: 0.50, blue: 0.96), Color(red: 0.86, green: 0.40, blue: 0.86)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
        )
    }

    // MARK: - Loop

    private func beginEntrance() {
        entranceTask?.cancel()
        showHero = false; showHeader = false; showButton = false
        revealedCards = 0; showAverageLine = false; showBadge = false

        entranceTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.35)) { showHero = true }
            await wait(120)
            // Comece a animar barras imediatamente, sem esperar header/botão.
            loopTask?.cancel()
            loopTask = Task { @MainActor in await runLoop() }
            await wait(80)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) { showHeader = true }
            await wait(140)
            withAnimation(.spring(response: 0.74, dampingFraction: 0.86)) { showButton = true }
        }
    }

    @MainActor
    private func runLoop() async {
        while !Task.isCancelled {
            withAnimation(.easeOut(duration: 0.25)) {
                revealedCards = 0
                showAverageLine = false
                showBadge = false
            }
            await wait(500)

            for index in 0..<days.count {
                if Task.isCancelled { return }
                if days[index].logged {
                    HapticManager.impact(style: .light)
                }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                    revealedCards = index + 1
                }
                await wait(150)
            }

            await wait(450)
            HapticManager.impact(style: .medium)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.84)) {
                showAverageLine = true
            }

            await wait(450)
            HapticManager.impact(style: .light)
            withAnimation(.spring(response: 0.65, dampingFraction: 0.7)) {
                showBadge = true
            }

            await wait(2400)
        }
    }

    private func wait(_ ms: UInt64) async {
        try? await Task.sleep(nanoseconds: ms * 1_000_000)
    }
}

// MARK: - Models & Subviews

private struct SmartDayMock {
    let label: String
    let kcal: Int
    let logged: Bool
}

private struct DayCard: View {
    let day: SmartDayMock
    let average: Int

    private var heightRatio: CGFloat {
        guard day.logged, average > 0 else { return 0.4 }
        return min(1.0, max(0.5, CGFloat(day.kcal) / CGFloat(max(average, 1)) * 0.7))
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 30, height: 130)

                if day.logged {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.55)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: 22, height: 130 * heightRatio)
                        .padding(.bottom, 4)
                } else {
                    Text("—")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .frame(width: 30, height: 130)
                }
            }
            Text(day.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(day.logged ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
