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
    @State private var caloriesText: String = ""
    @State private var proteinText: String = ""
    @State private var carbsText: String = ""
    @State private var fatText: String = ""
    @State private var sugarText: String = ""
    @State private var addedSugarText: String = ""
    @State private var fiberText: String = ""
    @State private var saturatedFatText: String = ""
    @State private var monounsaturatedFatText: String = ""
    @State private var polyunsaturatedFatText: String = ""
    @State private var cholesterolText: String = ""
    @State private var sodiumText: String = ""
    @State private var potassiumText: String = ""

    private enum ServingUnit: String, CaseIterable, Identifiable {
        case grams = "g"
        case milliliters = "ml"

        var id: String { rawValue }
    }

    private var parsedServing: Double {
        Double(servingText.replacingOccurrences(of: ",", with: ".")) ?? analysis.servingSizeGrams
    }
    private var allowsServingAdjustment: Bool { analysis.componentCount <= 1 }
    private var scaleFactor: Double {
        guard allowsServingAdjustment else { return 1 }
        guard analysis.servingSizeGrams > 0 else { return 1 }
        return parsedServing / analysis.servingSizeGrams
    }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedInt(caloriesText) != nil
            && parsedDouble(proteinText) != nil
            && parsedDouble(carbsText) != nil
            && parsedDouble(fatText) != nil
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

                if !analysis.reviewNotes.isEmpty {
                    Section {
                        ForEach(analysis.reviewNotes, id: \.self) { note in
                            Label(note, systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Alimento") {
                    TextField("Nome", text: $name)
                        .autocorrectionDisabled()
                }

                if allowsServingAdjustment {
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
                }

                Section("Nutrição") {
                    nutritionNumberRow("Calorias", unit: "kcal", text: $caloriesText, integerOnly: true)
                    nutritionNumberRow("Proteína", unit: "g", text: $proteinText)
                    nutritionNumberRow("Carbos", unit: "g", text: $carbsText)
                    nutritionNumberRow("Gordura", unit: "g", text: $fatText)
                }

                Section {
                    DisclosureGroup("Mais nutrientes", isExpanded: $showMore) {
                        optionalNumberRow("Açúcar", unit: "g", text: $sugarText)
                        optionalNumberRow("Açúcar adicionado", unit: "g", text: $addedSugarText)
                        optionalNumberRow("Fibra", unit: "g", text: $fiberText)
                        optionalNumberRow("Gordura saturada", unit: "g", text: $saturatedFatText)
                        optionalNumberRow("Gordura mono", unit: "g", text: $monounsaturatedFatText)
                        optionalNumberRow("Gordura poli", unit: "g", text: $polyunsaturatedFatText)
                        optionalNumberRow("Colesterol", unit: "mg", text: $cholesterolText)
                        optionalNumberRow("Sódio", unit: "mg", text: $sodiumText)
                        optionalNumberRow("Potássio", unit: "mg", text: $potassiumText)
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
            .savoriaModalBorder(theme: .nutrients)
            .platformScrollDismissesKeyboardInteractively()
            .modalNavigationTitle(String(localized: "Revisar refeição"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Registrar") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .tint(PageTheme.nutrients.accentColor)
        .onAppear {
            if name.isEmpty { name = analysis.name }
            if allowsServingAdjustment, servingText.isEmpty {
                servingText = formatNumber(analysis.servingSizeGrams)
            }
            loadEditableNutritionValues()
            mealTypeRaw = MealType.suggestion(for: logDate).rawValue
        }
        .onChange(of: servingText) { _, _ in
            loadEditableNutritionValues()
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
                } else if let iconName = resolvedFoodIconName {
                    IconImage(
                        name: name,
                        iconFileName: iconName,
                        fallbackSymbol: "fork.knife",
                        size: 88,
                        showBalloon: true,
                        balloonColor: PageTheme.nutrients.accentColor.opacity(0.14)
                    )
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

    private var resolvedFoodIconName: String? {
        Self.firstResolvedFoodIconName(from: name.isEmpty ? analysis.name : name)
    }

    private func nutritionNumberRow(_ label: String, unit: String, text: Binding<String>, integerOnly: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                #if os(iOS)
                .keyboardType(integerOnly ? .numberPad : .decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 96)
            Text(unit)
                .foregroundStyle(.secondary)
                .font(.footnote)
        }
    }

    @ViewBuilder
    private func optionalNumberRow(_ label: String, unit: String, text: Binding<String>) -> some View {
        nutritionNumberRow(label, unit: unit, text: text)
    }

    private func formatNumber(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        return String(format: "%.1f", v)
    }

    private func parsedInt(_ value: String) -> Int? {
        parsedDouble(value).map { Int($0.rounded()) }
    }

    private func parsedDouble(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func parsedOptionalDouble(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return parsedDouble(trimmed)
    }

    private func loadEditableNutritionValues() {
        caloriesText = String(scaledCalories)
        proteinText = formatNumber(Double(scaledProtein))
        carbsText = formatNumber(Double(scaledCarbs))
        fatText = formatNumber(Double(scaledFat))
        sugarText = formatOptional(scaledOpt(analysis.sugarG))
        addedSugarText = formatOptional(scaledOpt(analysis.addedSugarG))
        fiberText = formatOptional(scaledOpt(analysis.fiberG))
        saturatedFatText = formatOptional(scaledOpt(analysis.saturatedFatG))
        monounsaturatedFatText = formatOptional(scaledOpt(analysis.monounsaturatedFatG))
        polyunsaturatedFatText = formatOptional(scaledOpt(analysis.polyunsaturatedFatG))
        cholesterolText = formatOptional(scaledOpt(analysis.cholesterolMg))
        sodiumText = formatOptional(scaledOpt(analysis.sodiumMg))
        potassiumText = formatOptional(scaledOpt(analysis.potassiumMg))
    }

    private func formatOptional(_ value: Double?) -> String {
        value.map(formatNumber) ?? ""
    }

    private static func firstResolvedFoodIconName(from rawName: String) -> String? {
        let candidates = iconCandidateNames(from: rawName)
        for candidate in candidates where !candidate.isEmpty {
            if let file = ItemDatabase.shared.exactMatch(for: candidate)?.nomeDoArquivo {
                return file
            }
            if let file = ItemDatabase.shared.preferredMatch(for: candidate)?.nomeDoArquivo {
                return file
            }
            if let file = IconResolver.resolve(candidate) {
                return file
            }
        }
        return nil
    }

    private static func iconCandidateNames(from rawName: String) -> [String] {
        let protected = rawName
            .replacingOccurrences(of: #"(?i)\bpão\s+de\s+forma\b"#, with: "pao_de_forma", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bpao\s+de\s+forma\b"#, with: "pao_de_forma", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bpão\s+de\s+queijo\b"#, with: "pao_de_queijo", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bpao\s+de\s+queijo\b"#, with: "pao_de_queijo", options: .regularExpression)

        var pieces = protected
            .replacingOccurrences(of: #"(?i)\s*(?:;|,|\+|\bcom\b|\be\b)\s*"#, with: "\u{1F}", options: .regularExpression)
            .components(separatedBy: "\u{1F}")
            .map {
                $0
                    .replacingOccurrences(of: "pao_de_forma", with: "pao de forma")
                    .replacingOccurrences(of: "pao_de_queijo", with: "pao de queijo")
            }
            .map(cleanIconCandidateName)
            .filter { !$0.isEmpty }

        let whole = cleanIconCandidateName(rawName)
        if !whole.isEmpty {
            pieces.append(whole)
        }
        return pieces
    }

    private static func cleanIconCandidateName(_ raw: String) -> String {
        raw
            .replacingOccurrences(
                of: #"(?i)^\s*(?:\d+(?:[\.,]\d+)?|meia?|meio|uma?|um|duas?|dois|tr[eê]s|quatro|cinco)?\s*(?:kg|g|gramas?|ml|l|litros?|un|unidades?|und|x[ií]caras?|colheres?\s+de\s+sopa|colheres?\s+de\s+ch[aá]|fatias?|por(?:ç|c)(?:a|o|oes|ões)|copos?)?\s*(?:de|da|do|das|dos)?\s*"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
            calories: parsedInt(caloriesText) ?? 0,
            proteinG: parsedDouble(proteinText) ?? 0,
            carbsG: parsedDouble(carbsText) ?? 0,
            fatG: parsedDouble(fatText) ?? 0,
            mealType: MealType(rawValue: mealTypeRaw) ?? MealType.suggestion(for: timestamp),
            source: image == nil ? .textInput : .snapFood,
            timestamp: timestamp,
            emoji: analysis.emoji,
            servingSizeGrams: allowsServingAdjustment ? parsedServing : analysis.servingSizeGrams,
            imageFilename: filename
        )
        // Micros
        entry.sugarG = parsedOptionalDouble(sugarText)
        entry.addedSugarG = parsedOptionalDouble(addedSugarText)
        entry.fiberG = parsedOptionalDouble(fiberText)
        entry.saturatedFatG = parsedOptionalDouble(saturatedFatText)
        entry.monounsaturatedFatG = parsedOptionalDouble(monounsaturatedFatText)
        entry.polyunsaturatedFatG = parsedOptionalDouble(polyunsaturatedFatText)
        entry.cholesterolMg = parsedOptionalDouble(cholesterolText)
        entry.sodiumMg = parsedOptionalDouble(sodiumText)
        entry.potassiumMg = parsedOptionalDouble(potassiumText)

        modelContext.insert(entry)
        try? modelContext.save()
        dismiss()
    }
}
