import SwiftUI
import SwiftData
import Charts

/// Tela dedicada de rastreio de peso.
///
/// - Apresenta o peso atual, a meta e o progresso em direção a ela.
/// - Mostra um gráfico de linhas com gradiente (linha → base) cobrindo TODO o histórico.
/// - Lista o histórico agrupado por ano (data + peso) com edição/exclusão por entrada.
/// - Acessível via botão na header da Nutrição e via atalho na home do Assistente.
struct WeightTrackerView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \NutritionProfile.createdAt, order: .forward) private var profiles: [NutritionProfile]
    @Query(sort: \WeightEntry.date, order: .reverse) private var allEntries: [WeightEntry]

    @State private var showLogSheet = false
    @State private var editingEntry: WeightEntry?

    private var profile: NutritionProfile? { profiles.first }
    private var useMetric: Bool { profile?.useMetric ?? true }
    private var unit: String { useMetric ? "kg" : "lbs" }
    private var accent: Color { PageTheme.nutrients.accentColor }

    // MARK: - Derived data

    private var sortedAscending: [WeightEntry] {
        allEntries.sorted { $0.date < $1.date }
    }

    private var currentWeightKg: Double? {
        allEntries.first?.weightKg ?? profile?.weightKg
    }

    private var firstWeightKg: Double? {
        sortedAscending.first?.weightKg
    }

    /// (year, items sorted by date descending).
    private var entriesByYear: [(year: Int, items: [WeightEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: allEntries) { calendar.component(.year, from: $0.date) }
        return groups.keys.sorted(by: >).map { year in
            (year, groups[year]!.sorted { $0.date > $1.date })
        }
    }

    private var yDomain: ClosedRange<Double> {
        var values = sortedAscending.map { displayWeight($0.weightKg) }
        if let goalKg = profile?.targetWeightKg {
            values.append(displayWeight(goalKg))
        }
        guard let minV = values.min(), let maxV = values.max() else {
            return 0...100
        }
        let padding = max((maxV - minV) * 0.18, 2)
        return (minV - padding)...(maxV + padding)
    }

    private func displayWeight(_ kg: Double) -> Double {
        useMetric ? kg : kg * 2.20462
    }

    private func formatWeight(_ kg: Double) -> String {
        String(format: "%.1f %@", displayWeight(kg), unit)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summaryCard
                chartCard
                historyCard
                Color.clear.frame(height: 40)
            }
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(String(localized: "Rastreio de peso"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .tint(accent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showLogSheet = true
                } label: {
                    Label(String(localized: "Registrar"), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showLogSheet) {
            LogWeightSheet(
                currentWeightKg: currentWeightKg ?? profile?.weightKg ?? 70,
                useMetric: useMetric,
                onSave: saveNew
            )
        }
        .sheet(item: $editingEntry) { entry in
            EditWeightSheet(
                entry: entry,
                useMetric: useMetric,
                onSave: { kg, date in update(entry, weightKg: kg, date: date) },
                onDelete: { delete(entry) }
            )
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        card {
            HStack(alignment: .top, spacing: 12) {
                if let current = currentWeightKg {
                    metric(label: String(localized: "Atual"), value: formatWeight(current))
                }
                if let goal = profile?.targetWeightKg {
                    metric(label: String(localized: "Meta"), value: formatWeight(goal))
                }
                if let current = currentWeightKg,
                   let goal = profile?.targetWeightKg,
                   abs(goal - current) > 0.05 {
                    metric(
                        label: String(localized: "Faltam"),
                        value: String(format: "%.1f %@", abs(displayWeight(goal) - displayWeight(current)), unit)
                    )
                } else if let first = firstWeightKg, let current = currentWeightKg, first != current {
                    let delta = displayWeight(current) - displayWeight(first)
                    let sign = delta >= 0 ? "+" : "−"
                    metric(
                        label: String(localized: "Variação"),
                        value: String(format: "%@%.1f %@", sign, abs(delta), unit)
                    )
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chart

    private var chartCard: some View {
        card {
            HStack {
                Text(String(localized: "Evolução"))
                    .font(.cardTitle)
                Spacer()
                Text(entryCountLabel(allEntries.count))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if sortedAscending.isEmpty {
                emptyMessage(String(localized: "Nenhum registro ainda. Toque em + para começar."))
            } else {
                let baseline = yDomain.lowerBound
                Chart {
                    ForEach(sortedAscending) { entry in
                        AreaMark(
                            x: .value(String(localized: "Data"), entry.date),
                            yStart: .value(String(localized: "Base"), baseline),
                            yEnd: .value(String(localized: "Peso"), displayWeight(entry.weightKg))
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.05),
                                    accent.opacity(0.18),
                                    accent.opacity(0.45)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value(String(localized: "Data"), entry.date),
                            y: .value(String(localized: "Peso"), displayWeight(entry.weightKg))
                        )
                        .foregroundStyle(accent)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        PointMark(
                            x: .value(String(localized: "Data"), entry.date),
                            y: .value(String(localized: "Peso"), displayWeight(entry.weightKg))
                        )
                        .foregroundStyle(accent)
                        .symbolSize(28)
                    }

                    if let goalKg = profile?.targetWeightKg {
                        RuleMark(y: .value(String(localized: "Meta"), displayWeight(goalKg)))
                            .foregroundStyle(.green.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text(String(localized: "Meta"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.green.opacity(0.12), in: .capsule)
                            }
                    }
                }
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 220)
            }
        }
    }

    // MARK: - History

    private var historyCard: some View {
        card {
            HStack {
                Text(String(localized: "Histórico"))
                    .font(.cardTitle)
                Spacer()
            }

            if allEntries.isEmpty {
                emptyMessage(String(localized: "Sem registros ainda."))
            } else {
                VStack(spacing: 16) {
                    ForEach(entriesByYear, id: \.year) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(String(group.year))
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(group.items.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            VStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, entry in
                                    historyRow(entry: entry)
                                    if index < group.items.count - 1 {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }
                            .background(Color(.tertiarySystemFill).opacity(0.4), in: .rect(cornerRadius: 12))
                        }
                    }
                }
            }
        }
    }

    private func historyRow(entry: WeightEntry) -> some View {
        Button {
            editingEntry = entry
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.date, format: .dateTime.day().month(.abbreviated))
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(entry.date, format: .dateTime.weekday(.wide))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatWeight(entry.weightKg))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared shells

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(.serifBody)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
    }

    private func entryCountLabel(_ count: Int) -> String {
        count == 1
            ? "1 \(String(localized: "registro"))"
            : "\(count) \(String(localized: "registros"))"
    }

    // MARK: - Mutations

    private func saveNew(_ weightKg: Double) {
        let entry = WeightEntry(date: .now, weightKg: weightKg)
        modelContext.insert(entry)
        if let profile {
            profile.weightKg = weightKg
            profile.updatedAt = .now
        }
        try? modelContext.save()
    }

    private func update(_ entry: WeightEntry, weightKg: Double, date: Date) {
        entry.weightKg = weightKg
        entry.date = date
        // Se a entrada continuar sendo a mais recente, espelha no perfil.
        let latest = allEntries.max(by: { $0.date < $1.date })
        if let latest, latest.id == entry.id, let profile {
            profile.weightKg = weightKg
            profile.updatedAt = .now
        }
        try? modelContext.save()
    }

    private func delete(_ entry: WeightEntry) {
        modelContext.delete(entry)
        // Se sobrou alguma entrada, atualiza o perfil para o peso mais recente remanescente.
        if let profile {
            let remaining = allEntries.filter { $0.id != entry.id }
            if let mostRecent = remaining.max(by: { $0.date < $1.date }) {
                profile.weightKg = mostRecent.weightKg
                profile.updatedAt = .now
            }
        }
        try? modelContext.save()
    }
}

// MARK: - Edit sheet

/// Sheet para editar/excluir um registro de peso existente. Inclui DatePicker e ação destrutiva.
private struct EditWeightSheet: View {
    @Environment(\.dismiss) private var dismiss

    let entry: WeightEntry
    let useMetric: Bool
    let onSave: (Double, Date) -> Void
    let onDelete: () -> Void

    @State private var wholeNumber: Int
    @State private var decimal: Int
    @State private var date: Date
    @State private var showDeleteConfirm = false

    init(entry: WeightEntry, useMetric: Bool, onSave: @escaping (Double, Date) -> Void, onDelete: @escaping () -> Void) {
        self.entry = entry
        self.useMetric = useMetric
        self.onSave = onSave
        self.onDelete = onDelete
        let displayValue = useMetric ? entry.weightKg : entry.weightKg * 2.20462
        let whole = Int(displayValue)
        let dec = min(9, max(0, Int((displayValue - Double(whole)) * 10 + 0.5)))
        _wholeNumber = State(initialValue: whole)
        _decimal = State(initialValue: dec)
        _date = State(initialValue: entry.date)
    }

    private var selectedValue: Double { Double(wholeNumber) + Double(decimal) / 10.0 }
    private var selectedKg: Double { useMetric ? selectedValue : selectedValue / 2.20462 }
    private var unit: String { useMetric ? "kg" : "lbs" }
    private var wholeRange: ClosedRange<Int> { useMetric ? 20...250 : 50...500 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Peso") {
                    HStack(spacing: 0) {
                        Picker("Inteiro", selection: $wholeNumber) {
                            ForEach(wholeRange, id: \.self) { num in
                                Text("\(num)").tag(num)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .clipped()

                        Text(",")
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Picker("Decimal", selection: $decimal) {
                            ForEach(0...9, id: \.self) { num in
                                Text("\(num)").tag(num)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .clipped()

                        Text(unit)
                            .font(.system(.title3, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
                    }
                    .frame(height: 130)
                }

                Section("Data") {
                    DatePicker(
                        "Quando",
                        selection: $date,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Excluir registro", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .modalNavigationTitle(String(localized: "Editar registro"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        onSave(selectedKg, date)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Excluir este registro?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Excluir", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancelar", role: .cancel) { }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
