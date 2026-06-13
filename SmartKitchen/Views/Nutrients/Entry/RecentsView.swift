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
        case favorites = "Favoritos"
        case recents = "Recentes"
        case frequent = "Frequentes"
        case registered = "Registrados"
        var id: String { rawValue }
    }

    /// Histórico cronológico completo (sem dedupe). Limitado para performance.
    private var registeredAll: [FoodEntry] {
        Array(allEntries.prefix(300))
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

    /// Conjunto de chaves dedupe que estão favoritadas (qualquer entrada com
    /// aquela chave marcada como favorita conta como favorita).
    private var favoriteKeys: Set<String> {
        Set(allEntries.filter { $0.isFavorite }.map { dedupeKey(for: $0) })
    }

    /// Lista única por chave entre as entradas favoritas, mostrando a mais recente.
    private var favoriteUnique: [FoodEntry] {
        let favKeys = favoriteKeys
        var seen = Set<String>()
        var result: [FoodEntry] = []
        for entry in allEntries {
            let key = dedupeKey(for: entry)
            guard favKeys.contains(key) else { continue }
            if seen.insert(key).inserted {
                result.append(entry)
            }
        }
        return result
    }

    private func isFavorite(_ entry: FoodEntry) -> Bool {
        favoriteKeys.contains(dedupeKey(for: entry))
    }

    /// Alterna favorito propagando para todas as entradas com a mesma chave,
    /// para que a marca persista mesmo após relogs/duplicatas.
    private func toggleFavorite(for entry: FoodEntry) {
        let key = dedupeKey(for: entry)
        let newValue = !favoriteKeys.contains(key)
        for e in allEntries where dedupeKey(for: e) == key {
            e.isFavorite = newValue
        }
        try? modelContext.save()
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
            .modalNavigationTitle(String(localized: "Alimentos salvos"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .tint(Color.primary.opacity(0.82))
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    @ViewBuilder
    private var contentList: some View {
        switch segment {
        case .favorites:
            if favoriteUnique.isEmpty {
                emptyState(icon: "star", message: "Nenhum favorito ainda.\nMarque alimentos com a estrela em Recentes ou Frequentes.")
            } else {
                List {
                    ForEach(favoriteUnique) { entry in
                        favoriteRow(entry)
                    }
                }
                .savedFoodsListStyle()
                .scrollContentBackground(.hidden)
            }
        case .recents:
            if recentUnique.isEmpty {
                emptyState(icon: "clock", message: "Nenhum registro ainda.\nComece adicionando uma entrada manual.")
            } else {
                List {
                    ForEach(recentUnique) { entry in
                        favoriteRow(entry)
                    }
                }
                .savedFoodsListStyle()
                .scrollContentBackground(.hidden)
            }
        case .frequent:
            if frequentGroups.isEmpty {
                emptyState(icon: "repeat", message: "Nenhum alimento frequente ainda.")
            } else {
                List {
                    ForEach(frequentGroups) { group in
                        favoriteRow(group.template, subtitle: "\(group.count)× registrado")
                    }
                }
                .savedFoodsListStyle()
                .scrollContentBackground(.hidden)
            }
        case .registered:
            if registeredAll.isEmpty {
                emptyState(icon: "list.bullet.rectangle", message: "Nenhum alimento registrado ainda.")
            } else {
                List {
                    ForEach(registeredAll) { entry in
                        favoriteRow(entry, subtitle: Self.dateSubtitle(entry.timestamp))
                    }
                }
                .savedFoodsListStyle()
                .scrollContentBackground(.hidden)
            }
        }
    }

    private static func dateSubtitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLocalization.current().formattingLocale
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }

    @ViewBuilder
    private func favoriteRow(_ entry: FoodEntry, subtitle: String? = nil) -> some View {
        let favorite = isFavorite(entry)
        Button { relog(entry) } label: {
            SavedMealRow(entry: entry, subtitle: subtitle, isFavorite: favorite)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                toggleFavorite(for: entry)
            } label: {
                Label(favorite ? "Desfavoritar" : "Favoritar",
                      systemImage: favorite ? "star.slash.fill" : "star.fill")
            }
            .tint(Color.primary.opacity(0.72))
        }
        .contextMenu {
            Button {
                toggleFavorite(for: entry)
            } label: {
                Label(favorite ? "Remover dos favoritos" : "Adicionar aos favoritos",
                      systemImage: favorite ? "star.slash" : "star")
            }
        }
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Color.primary.opacity(0.42))
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
        // Propaga marca de favorito para que duplicatas mantenham a mesma chave
        // visível no segmento Favoritos.
        copy.isFavorite = isFavorite(template)
        modelContext.insert(copy)
        try? modelContext.save()
        dismiss()
    }
}

private extension View {
    @ViewBuilder
    func savedFoodsListStyle() -> some View {
        #if os(macOS)
        self.listStyle(.automatic)
        #else
        self.listStyle(.insetGrouped)
        #endif
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
    var isFavorite: Bool = false

    private var rowAccent: Color {
        Color.primary.opacity(0.82)
    }

    private var thumbnailFill: Color {
        Color.primary.opacity(0.08)
    }

    private var thumbnailStroke: Color {
        Color.primary.opacity(0.07)
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(rowAccent)
                    }
                }
                Group {
                HStack(spacing: 6) {
                    Text("\(entry.calories) kcal")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(rowAccent)
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
            }

            Spacer()

            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(rowAccent)
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
                Rectangle().fill(thumbnailFill)
                Rectangle().stroke(thumbnailStroke, lineWidth: 1)
                Text(emoji).font(.title2)
            }
        } else {
            ZStack {
                Rectangle().fill(thumbnailFill)
                Rectangle().stroke(thumbnailStroke, lineWidth: 1)
                Image(systemName: entry.mealType.icon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(rowAccent)
            }
        }
    }

    private func macroTag(_ label: String, _ value: Int) -> some View {
        Text("\(label) \(value)g")
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.055), in: .capsule)
    }
}
