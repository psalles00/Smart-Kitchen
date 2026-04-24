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

    @State private var name: String = ""
    @State private var emoji: String = ""
    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    @State private var servingSize: String = ""
    @State private var mealTypeRaw: String = MealType.snack.rawValue
    @State private var timestamp: Date = .now

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
            .scrollDismissesKeyboard(.interactively)
            .modalNavigationTitle(isEdit ? "Editar registro" : "Registrar Alimento")
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
        }
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
            mealTypeRaw = MealType.suggestion(for: timestamp).rawValue
            if focused == nil { focused = .name }
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
                source: .manual,
                timestamp: timestamp,
                emoji: normalizedEmoji,
                servingSizeGrams: parsedServing
            )
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
