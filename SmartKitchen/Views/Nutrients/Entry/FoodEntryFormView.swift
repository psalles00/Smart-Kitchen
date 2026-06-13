import SwiftUI
import SwiftData

/// Formulário compartilhado entre "Entrada manual" (nova) e "Editar registro".
/// Quando `entry == nil`: cria um novo `FoodEntry` com timestamp no dia selecionado.
/// Quando `entry != nil`: edita o registro existente.
struct FoodEntryFormView: View {
    enum Mode {
        case create(onDate: Date)
        case edit(entry: FoodEntry)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    var prefillName: String? = nil
    var prefillMealType: MealType? = nil

    @State private var name: String = ""
    @State private var emoji: String = ""
    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    @State private var servingSize: String = ""
    @State private var mealTypeRaw: String = MealType.snack.rawValue
    @State private var timestamp: Date = .now

    // MARK: AI state
    @State private var aiAnalysis: FoodAnalysis? = nil
    @State private var isAnalyzing: Bool = false
    @State private var aiError: String? = nil
    @State private var usedVoice: Bool = false
    @State private var voiceTranscriptBaseline: String = ""
    @State private var aiService = NutritionAIService()
    @State private var speech = NutritionSpeechRecognizer()
    /// Drives the in-app paywall sheet when the daily Nutrition AI quota
    /// is reached on free tier.
    @State private var pendingPaywallReason: PaywallSheet.Reason?

    @FocusState private var focused: Field?

    private enum Field { case name, emoji, calories, protein, carbs, fat, serving }

    private var isEdit: Bool {
        if case .edit = mode { return true } else { return false }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && Int(calories) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Alimento") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            TextField("🍎", text: $emoji)
                                .multilineTextAlignment(.center)
                                .frame(width: 44, height: 44)
                                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
                                .focused($focused, equals: .emoji)
                                .onChange(of: emoji) { _, new in
                                    // limita a 1 caractere/glyph
                                    if new.count > 1 { emoji = String(new.prefix(1)) }
                                }
                            TextField("ex.: Salada caseira", text: $name)
                                .focused($focused, equals: .name)
                                .autocorrectionDisabled()
                        }

                        if !isEdit {
                            automaticFoodOptions
                        }
                    }
                }

                Section("Macros") {
                    numberRow(label: "Calorias", unit: "kcal", text: $calories, focus: .calories)
                    numberRow(label: "Proteína", unit: "g", text: $protein, focus: .protein)
                    numberRow(label: "Carbos", unit: "g", text: $carbs, focus: .carbs)
                    numberRow(label: "Gordura", unit: "g", text: $fat, focus: .fat)
                    numberRow(label: "Porção", unit: "g", text: $servingSize, focus: .serving)
                }

                Section("Refeição") {
                    Picker("Tipo", selection: $mealTypeRaw) {
                        ForEach(MealType.allCases.sorted(by: { $0.sortIndex < $1.sortIndex })) { meal in
                            Label(meal.displayName, systemImage: meal.icon).tag(meal.rawValue)
                        }
                    }
                    DatePicker("Horário", selection: $timestamp)
                }
            }
            .macModalFormStyle(minWidth: 680, minHeight: 620)
            .platformScrollDismissesKeyboardInteractively()
            .modalNavigationTitle(isEdit ? String(localized: "Editar registro") : String(localized: "Salvar Alimento"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? "Salvar" : "Adicionar") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .tint(PageTheme.nutrients.accentColor)
            .onAppear(perform: loadInitial)
            .onDisappear { speech.stop() }
            .onChange(of: speech.transcript) { _, newValue in
                guard speech.state == .recording else { return }
                // Append the live transcript to whatever the user already typed
                // before pressing the mic button.
                let combined = (voiceTranscriptBaseline + " " + newValue)
                    .trimmingCharacters(in: .whitespaces)
                name = combined
            }
            .platformPresentationDetentsMediumLarge()
            .platformPresentationDragIndicatorVisible()
        }
        .sheet(item: $pendingPaywallReason) { reason in
            PaywallSheet(reason: reason)
        }
    }

    // MARK: - Automatic food options

    @ViewBuilder
    private var automaticFoodOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    toggleVoice()
                } label: {
                    Label(
                        speech.state == .recording ? "Parar" : "Ditar",
                        systemImage: speech.state == .recording ? "stop.circle.fill" : "mic.fill"
                    )
                    .labelStyle(.iconOnly)
                    .frame(width: 18, height: 18)
                }
                .buttonStyle(.bordered)
                .tint(speech.state == .recording ? .red : PageTheme.nutrients.accentColor)
                .disabled(isAnalyzing)
                .accessibilityLabel(speech.state == .recording ? String(localized: "Parar") : String(localized: "Ditar"))

                Button {
                    Task { await runAI() }
                } label: {
                    HStack(spacing: 6) {
                        if isAnalyzing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isAnalyzing ? "Analisando…" : "Preencher com IA")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(PageTheme.nutrients.accentColor)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isAnalyzing)
            }

            if case .error(let msg) = speech.state {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let aiError {
                Text(aiError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if aiAnalysis != nil && aiError == nil && !isAnalyzing {
                Label("Campos preenchidos. Revise e salve.", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
    }

    private func toggleVoice() {
        if speech.state == .recording {
            speech.stop()
        } else {
            voiceTranscriptBaseline = name
            usedVoice = true
            speech.start()
        }
    }

    private func runAI() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Free-tier daily Nutrition AI gate.
        guard FeatureGate.shared.canUse(.nutritionAI) else {
            pendingPaywallReason = .limitReached(.nutritionAI)
            return
        }
        if speech.state == .recording { speech.stop() }
        isAnalyzing = true
        aiError = nil
        defer { isAnalyzing = false }
        do {
            let analysis = try await aiService.analyzeText(description: trimmed)
            FeatureGate.shared.consume(.nutritionAI)
            apply(analysis)
        } catch {
            aiError = error.localizedDescription
        }
    }

    private func apply(_ analysis: FoodAnalysis) {
        aiAnalysis = analysis
        name = analysis.name
        emoji = analysis.emoji ?? ""
        calories = String(analysis.calories)
        protein = formatMacro(Double(analysis.protein))
        carbs = formatMacro(Double(analysis.carbs))
        fat = formatMacro(Double(analysis.fat))
        if analysis.servingSizeGrams > 0 {
            servingSize = formatMacro(analysis.servingSizeGrams)
        }
        mealTypeRaw = MealType.suggestion(for: timestamp).rawValue
        focused = nil
    }

    // MARK: - Rows

    @ViewBuilder
    private func numberRow(label: String, unit: String, text: Binding<String>, focus: Field) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                #if os(iOS)
                .keyboardType(focus == .fat || focus == .protein || focus == .carbs || focus == .serving ? .decimalPad : .numberPad)
                #endif
                .multilineTextAlignment(.trailing)
                .focused($focused, equals: focus)
                .frame(maxWidth: 120)
            Text(unit)
                .foregroundStyle(.secondary)
                .font(.footnote)
        }
    }

    // MARK: - Load

    private func loadInitial() {
        switch mode {
        case .create(let date):
            timestamp = Self.composedTimestamp(day: date, hour: Date.now)
            mealTypeRaw = (prefillMealType ?? MealType.suggestion(for: timestamp)).rawValue
            if let prefillName, !prefillName.isEmpty {
                name = prefillName
                if focused == nil { focused = .name }
            } else if focused == nil {
                focused = .name
            }
        case .edit(let entry):
            name = entry.name
            emoji = entry.emoji ?? ""
            calories = String(entry.calories)
            protein = formatMacro(entry.proteinG)
            carbs = formatMacro(entry.carbsG)
            fat = formatMacro(entry.fatG)
            if let s = entry.servingSizeGrams { servingSize = formatMacro(s) }
            mealTypeRaw = entry.mealTypeRaw
            timestamp = entry.timestamp
        }
    }

    private static func composedTimestamp(day: Date, hour: Date) -> Date {
        let cal = Calendar.current
        let d = cal.dateComponents([.year, .month, .day], from: day)
        let t = cal.dateComponents([.hour, .minute], from: hour)
        var merged = DateComponents()
        merged.year = d.year; merged.month = d.month; merged.day = d.day
        merged.hour = t.hour; merged.minute = t.minute
        return cal.date(from: merged) ?? day
    }

    // MARK: - Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let parsedCalories = Int(calories) ?? 0
        let parsedProtein = Double(protein.replacingOccurrences(of: ",", with: ".")) ?? 0
        let parsedCarbs = Double(carbs.replacingOccurrences(of: ",", with: ".")) ?? 0
        let parsedFat = Double(fat.replacingOccurrences(of: ",", with: ".")) ?? 0
        let parsedServing = Double(servingSize.replacingOccurrences(of: ",", with: "."))
        let normalizedEmoji = emoji.trimmingCharacters(in: .whitespaces).isEmpty ? nil : emoji

        switch mode {
        case .create:
            let entry = FoodEntry(
                name: trimmedName,
                calories: parsedCalories,
                proteinG: parsedProtein,
                carbsG: parsedCarbs,
                fatG: parsedFat,
                mealType: MealType(rawValue: mealTypeRaw) ?? .snack,
                source: aiAnalysis == nil ? .manual : (usedVoice ? .voiceInput : .textInput),
                timestamp: timestamp,
                emoji: normalizedEmoji,
                servingSizeGrams: parsedServing
            )
            // Carry micros from AI analysis when available (form doesn't expose
            // them directly, but we don't want to discard them).
            if let a = aiAnalysis {
                entry.sugarG = a.sugarG
                entry.addedSugarG = a.addedSugarG
                entry.fiberG = a.fiberG
                entry.saturatedFatG = a.saturatedFatG
                entry.monounsaturatedFatG = a.monounsaturatedFatG
                entry.polyunsaturatedFatG = a.polyunsaturatedFatG
                entry.cholesterolMg = a.cholesterolMg
                entry.sodiumMg = a.sodiumMg
                entry.potassiumMg = a.potassiumMg
            }
            modelContext.insert(entry)
        case .edit(let entry):
            entry.name = trimmedName
            entry.emoji = normalizedEmoji
            entry.calories = parsedCalories
            entry.proteinG = parsedProtein
            entry.carbsG = parsedCarbs
            entry.fatG = parsedFat
            entry.servingSizeGrams = parsedServing
            entry.mealTypeRaw = mealTypeRaw
            entry.timestamp = timestamp
        }

        try? modelContext.save()
        dismiss()
    }

    private func formatMacro(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}
