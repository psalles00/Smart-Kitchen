import SwiftUI
import SwiftData

/// Lista de entradas recentes / frequentes — permite "re-logar" tocando no item,
/// criando uma nova FoodEntry com timestamp no dia selecionado.
struct RecentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var allEntries: [FoodEntry]

    let logDate: Date

    @State private var segment: Segment = .recents

    private enum Segment: String, CaseIterable, Identifiable {
        case recents = "Recentes"
        case frequent = "Frequentes"
        var id: String { rawValue }
    }

    // MARK: - Data shaping

    /// Lista única por (nome, caloria) mostrando a entrada mais recente.
    private var recentUnique: [FoodEntry] {
        var seen = Set<String>()
        var result: [FoodEntry] = []
        for entry in allEntries {
            let key = dedupeKey(for: entry)
            if seen.insert(key).inserted {
                result.append(entry)
                if result.count >= 50 { break }
            }
        }
        return result
    }

    /// Entradas agrupadas por (nome, caloria) com contagem; ordenadas por frequência.
    private var frequentGroups: [FrequentGroup] {
        var buckets: [String: FrequentGroup] = [:]
        for entry in allEntries {
            let key = dedupeKey(for: entry)
            if var existing = buckets[key] {
                existing.count += 1
                if entry.timestamp > existing.template.timestamp {
                    existing.template = entry
                }
                buckets[key] = existing
            } else {
                buckets[key] = FrequentGroup(key: key, count: 1, template: entry)
            }
        }
        return buckets.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.template.timestamp > $1.template.timestamp
        }
    }

    private func dedupeKey(for entry: FoodEntry) -> String {
        "\(entry.name.lowercased())#\(entry.calories)"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Segmento", selection: $segment) {
                    ForEach(Segment.allCases) { seg in
                        Text(seg.rawValue).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

                contentList
            }
            .modalNavigationTitle("Recentes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .tint(PageTheme.nutrients.accentColor)
        }
    }

    @ViewBuilder
    private var contentList: some View {
        switch segment {
        case .recents:
            if recentUnique.isEmpty {
                emptyState(icon: "clock", message: "Nenhum registro ainda.\nComece adicionando uma entrada manual.")
            } else {
                List {
                    ForEach(recentUnique) { entry in
                        Button { relog(entry) } label: {
                            SavedMealRow(entry: entry, subtitle: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        case .frequent:
            if frequentGroups.isEmpty {
                emptyState(icon: "repeat", message: "Nenhum alimento frequente ainda.")
            } else {
                List {
                    ForEach(frequentGroups) { group in
                        Button { relog(group.template) } label: {
                            SavedMealRow(entry: group.template, subtitle: "\(group.count)× registrado")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(PageTheme.nutrients.accentColor.opacity(0.5))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func relog(_ template: FoodEntry) {
        let now = Date.now
        let cal = Calendar.current
        let day = cal.dateComponents([.year, .month, .day], from: logDate)
        let time = cal.dateComponents([.hour, .minute], from: now)
        var merged = DateComponents()
        merged.year = day.year; merged.month = day.month; merged.day = day.day
        merged.hour = time.hour; merged.minute = time.minute
        let finalDate = cal.date(from: merged) ?? logDate

        let copy = FoodEntry(
            name: template.name,
            calories: template.calories,
            proteinG: template.proteinG,
            carbsG: template.carbsG,
            fatG: template.fatG,
            mealType: MealType.suggestion(for: finalDate),
            source: .manual,
            timestamp: finalDate,
            emoji: template.emoji,
            servingSizeGrams: template.servingSizeGrams
        )
        modelContext.insert(copy)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Frequent group model

private struct FrequentGroup: Identifiable {
    var id: String { key }
    let key: String
    var count: Int
    var template: FoodEntry
}

// MARK: - Row

private struct SavedMealRow: View {
    let entry: FoodEntry
    let subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(entry.calories) kcal")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(PageTheme.nutrients.accentColor)
                    if let subtitle {
                        Text("·").foregroundStyle(.tertiary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    macroTag("P", Int(entry.proteinG))
                    macroTag("C", Int(entry.carbsG))
                    macroTag("G", Int(entry.fatG))
                }
            }

            Spacer()

            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(PageTheme.nutrients.accentColor)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let filename = entry.imageFilename,
           let img = FoodImageStore.shared.loadImage(filename: filename) {
            Image(platformImage: img)
                .resizable()
                .scaledToFill()
        } else if let emoji = entry.emoji, !emoji.isEmpty {
            ZStack {
                Rectangle().fill(PageTheme.nutrients.cardGradient)
                Text(emoji).font(.title2)
            }
        } else {
            ZStack {
                Rectangle().fill(PageTheme.nutrients.cardGradient)
                Image(systemName: entry.mealType.icon)
                    .foregroundStyle(.white)
            }
        }
    }

    private func macroTag(_ label: String, _ value: Int) -> some View {
        Text("\(label) \(value)g")
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(PageTheme.nutrients.accentColor.opacity(0.08), in: .capsule)
    }
}
