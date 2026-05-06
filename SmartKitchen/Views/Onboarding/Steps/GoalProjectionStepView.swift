import SwiftUI
import Charts

/// Phase 4 — Goal projection screen. Shown right before the paywall to
/// motivate the user with a visual story: "In N months you can reach Y kg".
/// Renders an animated chart with two trajectories (Without Savoria vs With
/// Savoria) and uses the same haptic + entrance pattern of the rest of the
/// onboarding flow.
struct GoalProjectionStepView: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    @State private var showHero = false
    @State private var showHeadline = false
    @State private var showChart = false
    @State private var chartProgress: Double = 0
    @State private var animatedWeight: Double = 0
    @State private var showSummary1 = false
    @State private var showSummary2 = false
    @State private var showButton = false
    @State private var pinPulse = false
    @State private var entranceTask: Task<Void, Never>? = nil

    private let primaryGradient = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.83, blue: 0.43),
            Color(red: 1.00, green: 0.53, blue: 0.62),
            Color(red: 0.82, green: 0.60, blue: 1.00)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    private var goal: WeightGoal {
        WeightGoal(rawValue: state.nutritionGoalRaw ?? "") ?? .maintain
    }

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                heroBadge
                    .opacity(showHero ? 1 : 0)
                    .scaleEffect(showHero ? 1 : 0.7)
                    .animation(.spring(response: 0.7, dampingFraction: 0.78), value: showHero)
                    .padding(.bottom, 18)

                headlineBlock
                    .opacity(showHeadline ? 1 : 0)
                    .offset(y: showHeadline ? 0 : 14)
                    .animation(.spring(response: 0.7, dampingFraction: 0.86), value: showHeadline)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)

                chartCard
                    .opacity(showChart ? 1 : 0)
                    .offset(y: showChart ? 0 : 18)
                    .animation(.spring(response: 0.85, dampingFraction: 0.84), value: showChart)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 14)

                summaryRow
                    .padding(.horizontal, 22)
                    .padding(.top, 4)

                Spacer(minLength: 16)

                OnboardingPrimaryButton(
                    title: String(localized: "Continuar"),
                    isEnabled: true,
                    action: onContinue
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 18)
                .animation(.spring(response: 0.7, dampingFraction: 0.86), value: showButton)
            }
        }
        .onAppear { startEntrance() }
        .onDisappear {
            entranceTask?.cancel()
            entranceTask = nil
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.99), Color(white: 0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Hero badge

    private var heroBadge: some View {
        ZStack {
            Circle()
                .fill(primaryGradient)
                .frame(width: 96, height: 96)
                .shadow(color: Color.pink.opacity(0.18), radius: 22, y: 10)

            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Headline

    private var headlineBlock: some View {
        VStack(spacing: 10) {
            Text(headlineTopText)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            headlineHero
                .font(.custom("Bricolage Grotesque", size: 30, relativeTo: .largeTitle).weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headlineTopText: String {
        switch goal {
        case .lose, .gain:
            let format = state.nutritionTargetMonths == 1
                ? String(localized: "Com o Savoria, em %lld mês")
                : String(localized: "Com o Savoria, em %lld meses")
            return String(format: format, state.nutritionTargetMonths)
        case .maintain:
            return String(localized: "Com o Savoria, daqui a alguns meses")
        }
    }

    private var monthsWord: String {
        state.nutritionTargetMonths == 1
            ? String(localized: "mês")
            : String(localized: "meses")
    }

    /// Hero headline. The numeric target weight (or pillar word for maintain)
    /// is rendered with the Savoria gradient.
    private var headlineHero: Text {
        switch goal {
        case .lose, .gain:
            let prefix = String(localized: "você terá conquistado seu objetivo de ")
            let target = String(format: "%.0f kg", animatedWeight)
            return Text(prefix).foregroundStyle(.primary)
                + Text(target).foregroundStyle(primaryGradient)
        case .maintain:
            let prefix = String(localized: "você estará ")
            let highlight = String(localized: "no controle")
            let suffix = String(localized: ", com hábitos consistentes.")
            return Text(prefix).foregroundStyle(.primary)
                + Text(highlight).foregroundStyle(primaryGradient)
                + Text(suffix).foregroundStyle(.primary)
        }
    }

    // MARK: - Chart card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                legendDot(color: .secondary.opacity(0.7), label: String(localized: "Sem o Savoria"))
                legendDot(gradient: primaryGradient, label: String(localized: "Com o Savoria"))
            }

            ZStack {
                Chart {
                    // Slow / partial trajectory — only shows the early
                    // portion to reinforce that without help the path is
                    // longer.
                    ForEach(slowSeries, id: \.x) { point in
                        LineMark(
                            x: .value("month", point.x),
                            y: .value("kg", point.y),
                            series: .value("series", "without")
                        )
                        .foregroundStyle(Color.secondary.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                        .interpolationMethod(.catmullRom)
                    }

                    // Soft gradient glow under the fast curve.
                    ForEach(fastSeriesAnimated, id: \.x) { point in
                        AreaMark(
                            x: .value("month", point.x),
                            yStart: .value("kgStart", yDomain.lowerBound),
                            yEnd: .value("kg", point.y),
                            series: .value("series", "with-glow")
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.00, green: 0.53, blue: 0.62).opacity(0.22),
                                    Color(red: 1.00, green: 0.53, blue: 0.62).opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }

                    // Fast / completed trajectory — animated by trimming
                    // through `chartProgress`.
                    ForEach(fastSeriesAnimated, id: \.x) { point in
                        LineMark(
                            x: .value("month", point.x),
                            y: .value("kg", point.y),
                            series: .value("series", "with")
                        )
                        .foregroundStyle(primaryGradient)
                        .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    }

                    if let last = fastSeriesAnimated.last,
                       chartProgress >= 0.98,
                       goal != .maintain {
                        PointMark(
                            x: .value("month", last.x),
                            y: .value("kg", last.y)
                        )
                        .foregroundStyle(primaryGradient)
                        .symbolSize(pinPulse ? 260 : 180)
                        .annotation(position: .top, alignment: .center, spacing: 4) {
                            Text(String(format: "%.0f kg", animatedWeight))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(primaryGradient)
                                )
                                .scaleEffect(pinPulse ? 1.08 : 1.0)
                        }
                    }
                }
                .chartXScale(domain: 0...Double(state.nutritionTargetMonths))
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: xAxisValues) { value in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(monthLabel(Int(v.rounded())))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(String(format: "%.0f", v))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 220)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(projectionCardSurface)
                .shadow(color: .black.opacity(0.06), radius: 18, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func legendDot(color: Color? = nil,
                           gradient: LinearGradient? = nil,
                           label: String) -> some View {
        HStack(spacing: 6) {
            if let gradient {
                Capsule()
                    .fill(gradient)
                    .frame(width: 18, height: 4)
            } else {
                Capsule()
                    .fill(color ?? .secondary)
                    .frame(width: 18, height: 4)
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Summary row

    private var summaryRow: some View {
        HStack(spacing: 10) {
            summaryChip(
                icon: "calendar",
                title: monthsLabel,
                subtitle: String(localized: "Prazo")
            )
            .opacity(showSummary1 ? 1 : 0)
            .offset(y: showSummary1 ? 0 : 10)
            .animation(.spring(response: 0.55, dampingFraction: 0.82), value: showSummary1)

            summaryChip(
                icon: goalIcon,
                title: targetSummary,
                subtitle: goalLabel
            )
            .opacity(showSummary2 ? 1 : 0)
            .offset(y: showSummary2 ? 0 : 10)
            .animation(.spring(response: 0.55, dampingFraction: 0.82), value: showSummary2)
        }
    }

    private func summaryChip(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(primaryGradient)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(Color.primary.opacity(0.05))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(projectionCardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var monthsLabel: String {
        "\(state.nutritionTargetMonths) " + monthsWord
    }

    private var targetSummary: String {
        switch goal {
        case .lose, .gain:
            return String(format: "%.0f kg", state.nutritionTargetWeightKg)
        case .maintain:
            return String(format: "%.0f kg", state.nutritionWeightKg)
        }
    }

    private var goalLabel: String {
        switch goal {
        case .lose: return String(localized: "Meta")
        case .gain: return String(localized: "Meta")
        case .maintain: return String(localized: "Manter")
        }
    }

    private var goalIcon: String {
        switch goal {
        case .lose: return "arrow.down.right.circle.fill"
        case .gain: return "arrow.up.right.circle.fill"
        case .maintain: return "equal.circle.fill"
        }
    }

    // MARK: - Series

    private struct Point { let x: Double; let y: Double }

    /// Full target trajectory from current weight to target weight
    /// across N months. Slightly eased (cubic) for a satisfying curve.
    private var fastSeries: [Point] {
        let months = max(1, state.nutritionTargetMonths)
        let start = state.nutritionWeightKg
        let end: Double
        switch goal {
        case .lose, .gain: end = state.nutritionTargetWeightKg
        case .maintain: end = state.nutritionWeightKg
        }
        let steps = 24
        return (0...steps).map { i in
            let t = Double(i) / Double(steps)
            // Smooth ease-in-out so the line decelerates as it nears the
            // target — feels like consistent progress.
            let eased = t < 0.5
                ? 2 * t * t
                : 1 - pow(-2 * t + 2, 2) / 2
            let x = Double(months) * t
            let y = start + (end - start) * eased
            return Point(x: x, y: y)
        }
    }

    /// Slow trajectory: only progresses ~30% of the way over the same time
    /// window. For maintain, oscillates around the current weight.
    private var slowSeries: [Point] {
        let months = max(1, state.nutritionTargetMonths)
        let start = state.nutritionWeightKg
        let end: Double
        switch goal {
        case .lose, .gain:
            let delta = (state.nutritionTargetWeightKg - start) * 0.30
            end = start + delta
        case .maintain:
            // Oscillating — show 4 small bumps around the current weight.
            let amp: Double = 1.6
            let steps = 24
            return (0...steps).map { i in
                let t = Double(i) / Double(steps)
                let x = Double(months) * t
                let y = start + sin(t * .pi * 4) * amp
                return Point(x: x, y: y)
            }
        }
        let steps = 24
        return (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let x = Double(months) * t
            let y = start + (end - start) * t
            return Point(x: x, y: y)
        }
    }

    /// Trims `fastSeries` according to `chartProgress`, plus interpolates
    /// the trailing point so the line draws smoothly during the entrance.
    private var fastSeriesAnimated: [Point] {
        guard chartProgress > 0 else { return [] }
        let pts = fastSeries
        let cutoff = chartProgress * Double(pts.count - 1)
        let lastIdx = Int(cutoff.rounded(.down))
        var trimmed = Array(pts.prefix(lastIdx + 1))
        // Interpolate up to `cutoff` for smooth animation.
        if lastIdx + 1 < pts.count {
            let frac = cutoff - Double(lastIdx)
            let a = pts[lastIdx]
            let b = pts[lastIdx + 1]
            trimmed.append(Point(
                x: a.x + (b.x - a.x) * frac,
                y: a.y + (b.y - a.y) * frac
            ))
        }
        return trimmed
    }

    // MARK: - Axis helpers

    private var xAxisValues: [Double] {
        let m = state.nutritionTargetMonths
        if m <= 3 {
            return (0...m).map(Double.init)
        } else if m <= 6 {
            return stride(from: 0, through: Double(m), by: 1).map { $0 }
        } else {
            return stride(from: 0, through: Double(m), by: 2).map { $0 }
        }
    }

    private func monthLabel(_ value: Int) -> String {
        if value == 0 { return String(localized: "Hoje") }
        return "\(value)" + (value == 1 ? "m" : "m")
    }

    private var yDomain: ClosedRange<Double> {
        let start = state.nutritionWeightKg
        let target: Double
        switch goal {
        case .lose, .gain: target = state.nutritionTargetWeightKg
        case .maintain: target = state.nutritionWeightKg
        }
        let lo = min(start, target) - 3
        let hi = max(start, target) + 3
        return lo...hi
    }

    // MARK: - Entrance

    private func startEntrance() {
        entranceTask?.cancel()
        showHero = false
        showHeadline = false
        showChart = false
        chartProgress = 0
        animatedWeight = state.nutritionWeightKg
        showSummary1 = false
        showSummary2 = false
        showButton = false
        pinPulse = false

        entranceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100 * 1_000_000)
            HapticManager.impact(style: .light)
            withAnimation { showHero = true }

            try? await Task.sleep(nanoseconds: 220 * 1_000_000)
            HapticManager.impact(style: .light)
            withAnimation { showHeadline = true }

            try? await Task.sleep(nanoseconds: 260 * 1_000_000)
            HapticManager.impact(style: .light)
            withAnimation { showChart = true }

            try? await Task.sleep(nanoseconds: 200 * 1_000_000)
            // Animate progress curve + counting weight in parallel.
            withAnimation(.easeInOut(duration: 1.6)) {
                chartProgress = 1
            }
            let targetW: Double = (goal == .maintain)
                ? state.nutritionWeightKg
                : state.nutritionTargetWeightKg
            withAnimation(.easeInOut(duration: 1.6)) {
                animatedWeight = targetW
            }
            try? await Task.sleep(nanoseconds: 400 * 1_000_000)
            HapticManager.impact(style: .light)
            try? await Task.sleep(nanoseconds: 400 * 1_000_000)
            HapticManager.impact(style: .light)
            try? await Task.sleep(nanoseconds: 800 * 1_000_000)
            HapticManager.impact(style: .medium)

            // Pin pulse pop.
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                pinPulse = true
            }

            try? await Task.sleep(nanoseconds: 120 * 1_000_000)
            HapticManager.impact(style: .light)
            withAnimation { showSummary1 = true }
            try? await Task.sleep(nanoseconds: 140 * 1_000_000)
            HapticManager.impact(style: .light)
            withAnimation { showSummary2 = true }
            try? await Task.sleep(nanoseconds: 220 * 1_000_000)
            HapticManager.impact(style: .light)
            withAnimation { showButton = true }
        }
    }
}

// MARK: - Color helper

private let projectionCardSurface: Color = {
    #if canImport(UIKit)
    return Color(uiColor: .secondarySystemBackground)
    #else
    return Color(white: 0.97)
    #endif
}()
