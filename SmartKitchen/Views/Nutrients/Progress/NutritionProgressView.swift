import SwiftUI
import SwiftData
import Charts

/// Tela de progresso nutricional — gráficos de peso, calorias, médias de macros e estatísticas.
/// Push a partir do botão de gráfico no header da aba Nutrição.
struct NutritionProgressView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \NutritionProfile.createdAt) private var profiles: [NutritionProfile]
    @Query(sort: \WeightEntry.date, order: .reverse) private var allWeightEntries: [WeightEntry]
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var allFoodEntries: [FoodEntry]

    @State private var range: NutritionTimeRange = .week
    @State private var showLogWeight = false

    private var profile: NutritionProfile? { profiles.first }
    private var useMetric: Bool { profile?.useMetric ?? true }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                rangePicker
                    .padding(.horizontal, 16)

                weightSection
                calorieSection
                macroAveragesSection
                statsSection

                Color.clear.frame(height: 40)
            }
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Progresso")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .tint(PageTheme.nutrients.accentColor)
        .sheet(isPresented: $showLogWeight) {
            if let profile {
                LogWeightSheet(
                    currentWeightKg: currentWeightKg ?? profile.weightKg,
                    useMetric: profile.useMetric,
                    onSave: saveWeight
                )
            }
        }
    }

    // MARK: - Range picker

    private var rangePicker: some View {
        Picker("Período", selection: $range) {
            ForEach(NutritionTimeRange.allCases) { r in
                Text(r.rawValue).tag(r)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Weight

    private var weightEntries: [WeightEntry] {
        let startDate = range.startDate
        return allWeightEntries
            .filter { $0.date >= startDate }
            .sorted { $0.date < $1.date }
    }

    private var currentWeightKg: Double? {
        allWeightEntries.first?.weightKg ?? profile?.weightKg
    }

    private func displayWeight(_ kg: Double) -> Double {
        useMetric ? kg : kg * 2.20462
    }

    private var weightUnit: String { useMetric ? "kg" : "lbs" }

    private var weightSection: some View {
        progressCard(title: "Peso") {
            HStack(spacing: 0) {
                Spacer()
                Button {
                    showLogWeight = true
                } label: {
                    Label("Registrar", systemImage: "plus.circle.fill")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(PageTheme.nutrients.accentColor)
                }
                .buttonStyle(.plain)
            }

            if weightEntries.isEmpty {
                emptyMessage("Nenhum registro ainda. Toque em Registrar para começar.")
            } else {
                HStack(spacing: 16) {
                    if let current = currentWeightKg {
                        statBadge(label: "Atual", value: String(format: "%.1f %@", displayWeight(current), weightUnit))
                    }
                    if let goal = profile?.targetWeightKg {
                        statBadge(label: "Meta", value: String(format: "%.1f %@", displayWeight(goal), weightUnit))
                    }
                    Spacer()
                }

                Chart {
                    ForEach(weightEntries) { entry in
                        LineMark(
                            x: .value("Data", entry.date, unit: .day),
                            y: .value("Peso", displayWeight(entry.weightKg))
                        )
                        .foregroundStyle(PageTheme.nutrients.accentColor)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        PointMark(
                            x: .value("Data", entry.date, unit: .day),
                            y: .value("Peso", displayWeight(entry.weightKg))
                        )
                        .foregroundStyle(PageTheme.nutrients.accentColor)
                        .symbolSize(30)
                    }

                    if let goalKg = profile?.targetWeightKg {
                        RuleMark(y: .value("Meta", displayWeight(goalKg)))
                            .foregroundStyle(.green.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    }
                }
                .chartYScale(domain: weightYDomain)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: range.xAxisStrideDays)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 180)
            }
        }
    }

    private var weightYDomain: ClosedRange<Double> {
        var weights = weightEntries.map { displayWeight($0.weightKg) }
        if let goalKg = profile?.targetWeightKg { weights.append(displayWeight(goalKg)) }
        guard let minW = weights.min(), let maxW = weights.max() else { return 0...100 }
        let padding = max((maxW - minW) * 0.15, 2)
        return (minW - padding)...(maxW + padding)
    }

    // MARK: - Calories

    private var dailyCalories: [(date: Date, calories: Int)] {
        bucketFoodByDay(\.calories)
    }

    private var calorieAvg: Int {
        let totalDays = dailyCalories.filter { $0.calories > 0 }.count
        guard totalDays > 0 else { return 0 }
        return dailyCalories.reduce(0) { $0 + $1.calories } / totalDays
    }

    private var calorieSection: some View {
        progressCard(title: "Calorias") {
            HStack {
                Spacer()
                if !dailyCalories.isEmpty {
                    Text("Média: \(calorieAvg) kcal")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if dailyCalories.allSatisfy({ $0.calories == 0 }) {
                emptyMessage("Nenhuma refeição registrada no período.")
            } else {
                Chart {
                    ForEach(dailyCalories, id: \.date) { item in
                        BarMark(
                            x: .value("Data", item.date, unit: .day),
                            y: .value("Calorias", item.calories)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    PageTheme.nutrients.accentColor.opacity(0.6),
                                    PageTheme.nutrients.accentColor
                                ],
                                startPoint: .bottom, endPoint: .top
                            )
                        )
                        .cornerRadius(4)
                    }

                    if let goal = profile?.effectiveCalories, goal > 0 {
                        RuleMark(y: .value("Meta", goal))
                            .foregroundStyle(PageTheme.nutrients.accentColor.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: range.xAxisStrideDays)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 180)
            }
        }
    }

    // MARK: - Macro averages

    private var macroAverages: (protein: Int, carbs: Int, fat: Int) {
        let totals = bucketFoodByDayMacros()
        let daysWithFood = totals.filter { $0.calories > 0 }.count
        guard daysWithFood > 0 else { return (0, 0, 0) }
        let totalP = totals.reduce(0.0) { $0 + $1.protein }
        let totalC = totals.reduce(0.0) { $0 + $1.carbs }
        let totalF = totals.reduce(0.0) { $0 + $1.fat }
        return (
            protein: Int((totalP / Double(daysWithFood)).rounded()),
            carbs: Int((totalC / Double(daysWithFood)).rounded()),
            fat: Int((totalF / Double(daysWithFood)).rounded())
        )
    }

    private var macroAveragesSection: some View {
        progressCard(title: "Média de macros") {
            let avg = macroAverages
            macroRow(
                label: "Proteína",
                current: avg.protein,
                goal: profile?.effectiveProteinG ?? 0,
                tint: Color(red: 0.20, green: 0.50, blue: 0.93)
            )
            macroRow(
                label: "Carbos",
                current: avg.carbs,
                goal: profile?.effectiveCarbsG ?? 0,
                tint: Color(red: 0.85, green: 0.58, blue: 0.12)
            )
            macroRow(
                label: "Gordura",
                current: avg.fat,
                goal: profile?.effectiveFatG ?? 0,
                tint: Color(red: 0.90, green: 0.75, blue: 0.15)
            )
        }
    }

    private func macroRow(label: String, current: Int, goal: Int, tint: Color) -> some View {
        let progress = goal > 0 ? min(Double(current) / Double(goal), 1.0) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                Spacer()
                Text("\(current)g / \(goal)g")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.14))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(6, geo.size.width * progress))
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Stats

    private var stats: (streak: Int, best: Int, daysOnTarget: Int, totalEntries: Int) {
        let entriesInRange = allFoodEntries.filter { $0.timestamp >= range.startDate }
        let totalEntries = entriesInRange.count

        let byDay = Dictionary(grouping: entriesInRange, by: {
            Calendar.current.startOfDay(for: $0.timestamp)
        })
        let goal = profile?.effectiveCalories ?? 0
        let daysOnTarget: Int = {
            guard goal > 0 else { return 0 }
            return byDay.values.count(where: { dayEntries in
                let cals = dayEntries.reduce(0) { $0 + $1.calories }
                let diff = abs(cals - goal)
                return diff <= max(100, goal / 10)
            })
        }()

        // Sequência a partir de hoje contando dias consecutivos com pelo menos 1 registro.
        let calendar = Calendar.current
        let loggedDays = Set(allFoodEntries.map { calendar.startOfDay(for: $0.timestamp) })
        var streak = 0
        var cursor = calendar.startOfDay(for: Date())
        while loggedDays.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        // Melhor sequência: varre todos os dias registrados.
        let sortedDays = loggedDays.sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for day in sortedDays {
            if let prev = previous, let next = calendar.date(byAdding: .day, value: 1, to: prev), next == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }

        return (streak, best, daysOnTarget, totalEntries)
    }

    private var statsSection: some View {
        progressCard(title: "Hábitos") {
            let s = stats
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statTile(icon: "flame.fill", label: "Sequência atual", value: "\(s.streak) dias", color: .orange)
                statTile(icon: "trophy.fill", label: "Melhor sequência", value: "\(s.best) dias", color: .yellow)
                statTile(icon: "target", label: "Dias na meta", value: "\(s.daysOnTarget)", color: PageTheme.nutrients.accentColor)
                statTile(icon: "fork.knife", label: "Registros", value: "\(s.totalEntries)", color: Color(red: 0.20, green: 0.50, blue: 0.93))
            }
        }
    }

    private func statTile(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    // MARK: - Shared card shell

    private func progressCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.cardTitle)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func statBadge(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(.serifBody)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
    }

    // MARK: - Bucketing helpers

    private func bucketFoodByDay(_ keyPath: KeyPath<FoodEntry, Int>) -> [(date: Date, calories: Int)] {
        let calendar = Calendar.current
        let start = range.startDate
        let today = calendar.startOfDay(for: Date())
        let entriesInRange = allFoodEntries.filter { $0.timestamp >= start }
        let grouped = Dictionary(grouping: entriesInRange, by: {
            calendar.startOfDay(for: $0.timestamp)
        })

        var result: [(date: Date, calories: Int)] = []
        var cursor = start
        while cursor <= today {
            let total = grouped[cursor]?.reduce(0) { $0 + $1[keyPath: keyPath] } ?? 0
            result.append((date: cursor, calories: total))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private func bucketFoodByDayMacros() -> [(date: Date, calories: Int, protein: Double, carbs: Double, fat: Double)] {
        let calendar = Calendar.current
        let start = range.startDate
        let today = calendar.startOfDay(for: Date())
        let entriesInRange = allFoodEntries.filter { $0.timestamp >= start }
        let grouped = Dictionary(grouping: entriesInRange, by: {
            calendar.startOfDay(for: $0.timestamp)
        })

        var result: [(date: Date, calories: Int, protein: Double, carbs: Double, fat: Double)] = []
        var cursor = start
        while cursor <= today {
            let entries = grouped[cursor] ?? []
            let cal = entries.reduce(0) { $0 + $1.calories }
            let p = entries.reduce(0.0) { $0 + $1.proteinG }
            let c = entries.reduce(0.0) { $0 + $1.carbsG }
            let f = entries.reduce(0.0) { $0 + $1.fatG }
            result.append((cursor, cal, p, c, f))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    // MARK: - Actions

    private func saveWeight(_ weightKg: Double) {
        let entry = WeightEntry(date: .now, weightKg: weightKg)
        modelContext.insert(entry)
        if let profile {
            profile.weightKg = weightKg
            profile.updatedAt = .now
        }
        try? modelContext.save()
    }
}
