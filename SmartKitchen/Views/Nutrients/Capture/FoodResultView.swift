import SwiftUI
import SwiftData

/// Tela de revisão do resultado da IA antes de registrar a refeição.
/// Permite ajustar nome, porção (g) e tipo de refeição; macros e micros são escalonados.
struct FoodResultView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let analysis: FoodAnalysis
    let image: PlatformImage?
    let logDate: Date

    @State private var name: String = ""
    @State private var servingText: String = ""
    @State private var mealTypeRaw: String = MealType.snack.rawValue
    @State private var showMore: Bool = false
    @State private var servingUnit: ServingUnit = .grams

    private enum ServingUnit: String, CaseIterable, Identifiable {
        case grams = "g"
        case milliliters = "ml"

        var id: String { rawValue }
    }

    private var parsedServing: Double {
        Double(servingText.replacingOccurrences(of: ",", with: ".")) ?? analysis.servingSizeGrams
    }
    private var scaleFactor: Double {
        guard analysis.servingSizeGrams > 0 else { return 1 }
        return parsedServing / analysis.servingSizeGrams
    }

    // MARK: - Scaled values
    private var scaledCalories: Int { Int((Double(analysis.calories) * scaleFactor).rounded()) }
    private var scaledProtein: Int { Int((Double(analysis.protein) * scaleFactor).rounded()) }
    private var scaledCarbs: Int { Int((Double(analysis.carbs) * scaleFactor).rounded()) }
    private var scaledFat: Int { Int((Double(analysis.fat) * scaleFactor).rounded()) }

    private func scaledOpt(_ v: Double?) -> Double? {
        guard let v else { return nil }
        return (v * scaleFactor * 10).rounded() / 10
    }

    var body: some View {
        Form {
                heroSection

                Section("Alimento") {
                    TextField("Nome", text: $name)
                        .autocorrectionDisabled()
                }

                Section("Porção") {
                    HStack {
                        Text("Quantidade")
                        Spacer()
                        TextField("100", text: $servingText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Picker("", selection: $servingUnit) {
                            ForEach(ServingUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 88)
                        .labelsHidden()
                    }
                }

                Section("Nutrição") {
                    macroRow("Calorias", "\(scaledCalories) kcal")
                    macroRow("Proteína", "\(scaledProtein) g")
                    macroRow("Carbos", "\(scaledCarbs) g")
                    macroRow("Gordura", "\(scaledFat) g")
                }

                Section {
                    DisclosureGroup("Mais nutrientes", isExpanded: $showMore) {
                        optionalRow("Açúcar", value: scaledOpt(analysis.sugarG), unit: "g")
                        optionalRow("Açúcar adicionado", value: scaledOpt(analysis.addedSugarG), unit: "g")
                        optionalRow("Fibra", value: scaledOpt(analysis.fiberG), unit: "g")
                        optionalRow("Gordura saturada", value: scaledOpt(analysis.saturatedFatG), unit: "g")
                        optionalRow("Gordura mono", value: scaledOpt(analysis.monounsaturatedFatG), unit: "g")
                        optionalRow("Gordura poli", value: scaledOpt(analysis.polyunsaturatedFatG), unit: "g")
                        optionalRow("Colesterol", value: scaledOpt(analysis.cholesterolMg), unit: "mg")
                        optionalRow("Sódio", value: scaledOpt(analysis.sodiumMg), unit: "mg")
                        optionalRow("Potássio", value: scaledOpt(analysis.potassiumMg), unit: "mg")
                    }
                }

                Section("Refeição") {
                    Picker("Tipo", selection: $mealTypeRaw) {
                        ForEach(MealType.allCases.sorted(by: { $0.sortIndex < $1.sortIndex })) { meal in
                            Label(meal.displayName, systemImage: meal.icon).tag(meal.rawValue)
                        }
                    }
                }

                if let ids = analysis.cachedFoodIDs, !ids.isEmpty {
                    Section {
                        FoodCacheVoteView(foodIDs: ids)
                    }
                }
            }
            .macModalFormStyle(minWidth: 760, minHeight: 700)
            .platformScrollDismissesKeyboardInteractively()
            .modalNavigationTitle(String(localized: "Revisar refeição"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Registrar") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .tint(PageTheme.nutrients.accentColor)
        .onAppear {
            if name.isEmpty { name = analysis.name }
            if servingText.isEmpty {
                servingText = formatNumber(analysis.servingSizeGrams)
            }
            mealTypeRaw = MealType.suggestion(for: logDate).rawValue
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var heroSection: some View {
        Section {
            HStack {
                Spacer()
                if let image {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxHeight: 180)
                        .clipShape(.rect(cornerRadius: 14))
                } else if let emoji = analysis.emoji, !emoji.isEmpty {
                    Text(emoji).font(.system(size: 72))
                } else {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 44))
                        .foregroundStyle(PageTheme.nutrients.accentColor)
                        .padding(20)
                        .background(PageTheme.nutrients.cardGradient, in: .rect(cornerRadius: 14))
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    private func macroRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func optionalRow(_ label: String, value: Double?, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let value {
                Text("\(formatNumber(value)) \(unit)").foregroundStyle(.secondary)
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
    }

    private func formatNumber(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        return String(format: "%.1f", v)
    }

    // MARK: - Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let cal = Calendar.current
        let day = cal.dateComponents([.year, .month, .day], from: logDate)
        let now = cal.dateComponents([.hour, .minute], from: .now)
        var merged = DateComponents()
        merged.year = day.year; merged.month = day.month; merged.day = day.day
        merged.hour = now.hour; merged.minute = now.minute
        let timestamp = cal.date(from: merged) ?? logDate

        // Persiste imagem em disco, se houver.
        var filename: String? = nil
        if let image { filename = FoodImageStore.shared.save(image: image) }

        let entry = FoodEntry(
            name: trimmedName,
            calories: scaledCalories,
            proteinG: Double(scaledProtein),
            carbsG: Double(scaledCarbs),
            fatG: Double(scaledFat),
            mealType: MealType(rawValue: mealTypeRaw) ?? MealType.suggestion(for: timestamp),
            source: image == nil ? .textInput : .snapFood,
            timestamp: timestamp,
            emoji: analysis.emoji,
            servingSizeGrams: parsedServing,
            imageFilename: filename
        )
        // Micros
        entry.sugarG = scaledOpt(analysis.sugarG)
        entry.addedSugarG = scaledOpt(analysis.addedSugarG)
        entry.fiberG = scaledOpt(analysis.fiberG)
        entry.saturatedFatG = scaledOpt(analysis.saturatedFatG)
        entry.monounsaturatedFatG = scaledOpt(analysis.monounsaturatedFatG)
        entry.polyunsaturatedFatG = scaledOpt(analysis.polyunsaturatedFatG)
        entry.cholesterolMg = scaledOpt(analysis.cholesterolMg)
        entry.sodiumMg = scaledOpt(analysis.sodiumMg)
        entry.potassiumMg = scaledOpt(analysis.potassiumMg)

        modelContext.insert(entry)
        try? modelContext.save()
        dismiss()
    }
}
