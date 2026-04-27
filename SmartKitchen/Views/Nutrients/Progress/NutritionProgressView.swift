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
    @Query(sort: \NutritionDayLog.dayStart, order: .reverse) private var allDayLogs: [NutritionDayLog]

    @State private var range: NutritionTimeRange = .month
    @State private var showLogWeight = false

    private var profile: NutritionProfile? { profiles.first }
    private var useMetric: Bool { profile?.useMetric ?? true }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                rangePicker
                    .padding(.horizontal, 16)

                scoreHeaderSection

                estimateHeader

                weightSection
                calorieSection
                macroAveragesSection
                statsSection
                statusInsightSection

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

    /// Macros agregados por dia, considerando apenas dias concluídos no range.
    private var completedMacrosInRange: [Date: DayMacros] {
        NutritionAveragesService.completedDayMacros(
            entries: allFoodEntries,
            logs: allDayLogs,
            startDate: range.startDate
        )
    }

    /// Resultado da média baseado no dia da semana de hoje, com fallback automático.
    private var calorieAverageResult: NutritionAverageResult {
        NutritionAveragesService.average(
            for: Date(),
            dayMacros: completedMacrosInRange
        )
    }

    private var calorieAvg: Int { calorieAverageResult.macros.calories }

    private var calorieSection: some View {
        progressCard(title: "Calorias") {
            HStack {
                Spacer()
                if !dailyCalories.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Média: \(calorieAvg) kcal")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                        if calorieAverageResult.basis != .none {
                            Text(calorieAverageResult.basis.shortDescription)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                    }
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

    private var macroAverageResult: NutritionAverageResult {
        NutritionAveragesService.average(
            for: Date(),
            dayMacros: completedMacrosInRange
        )
    }

    private var macroAverages: (protein: Int, carbs: Int, fat: Int) {
        let m = macroAverageResult.macros
        return (
            protein: Int(m.protein.rounded()),
            carbs: Int(m.carbs.rounded()),
            fat: Int(m.fat.rounded())
        )
    }

    private var macroAveragesSection: some View {
        progressCard(title: "Média de macros") {
            let avg = macroAverages
            HStack {
                Spacer()
                if macroAverageResult.basis != .none {
                    Text(macroAverageResult.basis.shortDescription)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
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

        // Sequências e dias-na-meta agora consideram apenas dias **concluídos**.
        let calendar = Calendar.current
        let completedDays = Set(
            allDayLogs
                .filter { $0.isCompleted }
                .map { calendar.startOfDay(for: $0.dayStart) }
        )

        // Dias na meta (±10% de calorias) restritos a dias concluídos no range.
        let goal = profile?.effectiveCalories ?? 0
        let daysOnTarget: Int = {
            guard goal > 0 else { return 0 }
            let entriesByDay = Dictionary(grouping: entriesInRange, by: { calendar.startOfDay(for: $0.timestamp) })
            return completedDays
                .filter { $0 >= range.startDate }
                .count(where: { day in
                    let cals = (entriesByDay[day] ?? []).reduce(0) { $0 + $1.calories }
                    let diff = abs(cals - goal)
                    return diff <= max(100, goal / 10)
                })
        }()

        // Sequência atual: dias concluídos consecutivos terminando em hoje (ou ontem se hoje ainda não foi concluído).
        var streak = 0
        var cursor = calendar.startOfDay(for: Date())
        if !completedDays.contains(cursor) {
            // permite contar até ontem
            if let prev = calendar.date(byAdding: .day, value: -1, to: cursor) {
                cursor = prev
            }
        }
        while completedDays.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        // Melhor sequência: varre todos os dias concluídos.
        let sortedDays = completedDays.sorted()
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

    // MARK: - Estimate header & insight

    /// Card destacado no topo da página: traz o ícone qualitativo
    /// (`NutritionScore`) referente à média do período + título e mensagem
    /// detalhada sobre o estado do usuário.
    @ViewBuilder
    private var scoreHeaderSection: some View {
        if let profile, profile.effectiveCalories > 0 {
            let goal = profile.effectiveCalories
            let distances = completedMacrosInRange.values.map { day in
                NutritionScore.dayDistanceValue(consumed: day.calories, goal: goal)
            }
            let sample = distances.count
            let score = NutritionScore.forPeriod(distances: distances)

            HStack(alignment: .center, spacing: 10) {
                Image(systemName: score.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(score.tint)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 4) {
                    Text(score.title)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text(scoreDetail(score: score, sample: sample, goal: goal))
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(score.tint.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(score.tint.opacity(0.20), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }

    private func scoreDetail(score: NutritionScore, sample: Int, goal: Int) -> String {
        guard sample > 0 else {
            return "Conclua pelo menos um dia para eu calcular uma média e te mostrar uma leitura mais fiel do seu progresso."
        }
        let avg = calorieAvg
        let diff = avg - goal
        let absDiff = abs(diff)
        let basis = "a média dos seus \(sample) dia\(sample == 1 ? "" : "s") concluído\(sample == 1 ? "" : "s") no período"
        switch score {
        case .noData:
            return "Conclua pelo menos um dia para eu calcular uma média e te mostrar uma leitura mais fiel do seu progresso."
        case .excellent:
            return "Sua média (\(avg) kcal) está bem próxima da meta de \(goal). Aqui estou olhando para \(basis)."
        case .good:
            if diff == 0 { return "Sua média (\(avg) kcal) está alinhada à meta. Aqui estou olhando para \(basis)." }
            let dir = diff > 0 ? "acima" : "abaixo"
            return "Sua média (\(avg) kcal) está \(absDiff) kcal \(dir) da meta. Continue assim. Aqui estou olhando para \(basis)."
        case .average:
            let dir = diff > 0 ? "acima" : "abaixo"
            return "Sua média (\(avg) kcal) está \(absDiff) kcal \(dir) da meta. Pequenos ajustes ajudam a aproximar. Aqui estou olhando para \(basis)."
        case .needsImprovement:
            let dir = diff > 0 ? "acima" : "abaixo"
            return "Sua média (\(avg) kcal) está \(absDiff) kcal \(dir) da meta — vale revisar porções e horários. Aqui estou olhando para \(basis)."
        }
    }

    /// Cabeçalho que reforça que o número apresentado é uma **estimativa** baseada
    @ViewBuilder
    private var estimateHeader: some View {
        let sample = macroAverageResult.basis.sampleSize
        let copy: String = {
            if sample == 0 {
                return "Ainda não tenho uma média para te mostrar por aqui. Assim que você concluir um dia de registro, eu passo a calcular essa estimativa com base nos dias fechados por você."
            }
            return "Os valores desta página são uma média tirada dos seus \(sample) dia\(sample == 1 ? "" : "s") concluído\(sample == 1 ? "" : "s"). Em outras palavras: só entram na conta os dias que você fechou, para a estimativa ficar mais fiel ao seu ritmo."
        }()

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.tertiary)
                .font(.system(size: 14))
            Text(copy)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    /// Card final com mensagem condicional sobre como o usuário está em relação à meta.
    /// Aparece após o card de hábitos e usa o accent de Nutrição.
    @ViewBuilder
    private var statusInsightSection: some View {
        if let profile, profile.effectiveCalories > 0, macroAverageResult.basis != .none {
            let goal = profile.effectiveCalories
            let avg = calorieAvg
            let diff = avg - goal
            let pct = Double(abs(diff)) / Double(goal)
            let sample = calorieAverageResult.basis.sampleSize

            let (icon, tint, title, message): (String, Color, String, String) = {
                if sample < 3 {
                    return (
                        "lightbulb.fill",
                        Color.yellow,
                        "Ainda poucos dados",
                        "Conclua mais dias para eu montar uma média mais estável e confiável."
                    )
                }
                if pct <= 0.10 {
                    return (
                        "checkmark.seal.fill",
                        PageTheme.nutrients.accentColor,
                        "Você está dentro da meta",
                        "Sua média está próxima do alvo (\(goal) kcal). Continue assim — consistência é o que importa."
                    )
                }
                if diff > 0 {
                    return (
                        "arrow.up.right.circle.fill",
                        Color.orange,
                        "Acima da meta em média",
                        "Considerando a média dos seus dias concluídos, você está consumindo cerca de \(diff) kcal acima da meta. Pequenos ajustes nas porções podem aproximar do objetivo."
                    )
                }
                return (
                    "arrow.down.right.circle.fill",
                    Color.blue,
                    "Abaixo da meta em média",
                    "Considerando a média dos seus dias concluídos, você está cerca de \(-diff) kcal abaixo da meta. Atenção a sinais de baixa energia."
                )
            }()

            progressCard(title: "Como você está") {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text(message)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
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
