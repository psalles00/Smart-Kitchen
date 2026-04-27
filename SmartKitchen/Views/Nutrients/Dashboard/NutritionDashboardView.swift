import SwiftUI
import SwiftData

/// Conteúdo principal do dashboard (strip + ring + macros + refeições do dia).
struct NutritionDashboardView: View {
    let profile: NutritionProfile
    let allEntries: [FoodEntry]
    @Binding var selectedDate: Date
    var onTapEntry: (FoodEntry) -> Void = { _ in }
    var onDeleteEntry: (FoodEntry) -> Void = { _ in }
    var onPickEntry: (NutritionEntrySheet) -> Void = { _ in }

    private var calendar: Calendar { .current }

    private var entriesForSelectedDate: [FoodEntry] {
        allEntries.filter { calendar.isDate($0.timestamp, inSameDayAs: selectedDate) }
    }

    private var caloriesConsumed: Int {
        entriesForSelectedDate.reduce(0) { $0 + $1.calories }
    }

    private var proteinConsumed: Int {
        Int(entriesForSelectedDate.reduce(0) { $0 + $1.proteinG }.rounded())
    }

    private var carbsConsumed: Int {
        Int(entriesForSelectedDate.reduce(0) { $0 + $1.carbsG }.rounded())
    }

    private var fatConsumed: Int {
        Int(entriesForSelectedDate.reduce(0) { $0 + $1.fatG }.rounded())
    }

    private func caloriesFor(_ date: Date) -> Int {
        allEntries
            .filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
            .reduce(0) { $0 + $1.calories }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    WeekEnergyStrip(
                        selectedDate: $selectedDate,
                        caloriesForDate: caloriesFor,
                        calorieGoal: profile.effectiveCalories,
                        weekStartsOnMonday: profile.weekStartsOnMonday
                    )
                    .padding(.horizontal, 12)

                    CalorieRingView(consumed: caloriesConsumed, goal: profile.effectiveCalories)
                        .padding(.top, 4)

                    HStack(spacing: 10) {
                        MacroCard(
                            label: "Proteína",
                            current: proteinConsumed,
                            goal: profile.effectiveProteinG,
                            tint: Color(red: 0.20, green: 0.50, blue: 0.93)
                        )
                        MacroCard(
                            label: "Carbos",
                            current: carbsConsumed,
                            goal: profile.effectiveCarbsG,
                            tint: Color(red: 0.85, green: 0.58, blue: 0.12)
                        )
                        MacroCard(
                            label: "Gordura",
                            current: fatConsumed,
                            goal: profile.effectiveFatG,
                            tint: Color(red: 0.90, green: 0.75, blue: 0.15)
                        )
                    }
                    .padding(.horizontal, 16)

                    mealSections
                        .padding(.horizontal, 16)

                    Color.clear.frame(height: 40)
                }
                .padding(.top, 6)
            }
        }
    }

    private var mealSections: some View {
        VStack(spacing: 16) {
            ForEach(MealType.allCases.sorted { $0.sortIndex < $1.sortIndex }) { meal in
                mealSection(for: meal)
            }
        }
    }

    @ViewBuilder
    private func mealSection(for meal: MealType) -> some View {
        let rows = entriesForSelectedDate
            .filter { $0.mealType == meal }
            .sorted { $0.timestamp < $1.timestamp }

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: meal.icon)
                    .foregroundStyle(PageTheme.nutrients.accentColor)
                Text(meal.displayName)
                    .font(.cardTitle)
                    .foregroundStyle(.primary)
                Spacer()
                if !rows.isEmpty {
                    let total = rows.reduce(0) { $0 + $1.calories }
                    Text("\(total) kcal")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if rows.isEmpty {
                Text("Nenhum registro")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 10)
                    .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 12))
            } else {
                VStack(spacing: 6) {
                    ForEach(rows) { entry in
                        Button {
                            onTapEntry(entry)
                        } label: {
                            FoodEntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                onDeleteEntry(entry)
                            } label: {
                                Label("Excluir", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            categoryAddButton(for: meal)
        }
    }

    /// Discreet capsule button placed at the foot of each meal category, mirroring the
    /// "Adicionar todos em Mercado" affordance on the recipe detail page. Opens the same
    /// nutrition menu as the assistant bar, dispatching the chosen sheet up to `NutrientsView`.
    @ViewBuilder
    private func categoryAddButton(for meal: MealType) -> some View {
        HStack {
            Spacer()
            Menu {
                Section("Registros Salvos") {
                    Button {
                        onPickEntry(.manual(prefillName: nil, prefillMealType: meal))
                    } label: {
                        Label("Salvar alimento", systemImage: "fork.knife")
                    }
                    Button {
                        onPickEntry(.recents)
                    } label: {
                        Label("Alimentos salvos", systemImage: "clock.arrow.circlepath")
                    }
                }
                Section("Registrar por…") {
                    Button {
                        onPickEntry(.captureLabel)
                    } label: {
                        Label("Rótulo", systemImage: "doc.text.viewfinder")
                    }
                    Button {
                        onPickEntry(.capturePhotoGallery)
                    } label: {
                        Label("Galeria", systemImage: "photo")
                    }
                    #if os(iOS)
                    Button {
                        onPickEntry(.capturePhotoCamera)
                    } label: {
                        Label("Câmera", systemImage: "camera")
                    }
                    #endif
                    Button {
                        onPickEntry(.captureVoice)
                    } label: {
                        Label("Voz", systemImage: "waveform")
                    }
                    Button {
                        onPickEntry(.captureText(prefillText: nil, autoAnalyze: false))
                    } label: {
                        Label("Texto", systemImage: "character.cursor.ibeam")
                    }
                }
            } label: {
                Label("Adicionar em \(localizedDisplayName(meal))", systemImage: "plus")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill).opacity(0.85), in: .capsule)
            }
            .menuOrder(.fixed)
            .buttonStyle(.plain)
        }
    }

    private func localizedDisplayName(_ meal: MealType) -> String {
        switch meal {
        case .breakfast: "Café da manhã"
        case .lunch:     "Almoço"
        case .dinner:    "Jantar"
        case .snack:     "Lanche"
        case .other:     "Outras"
        }
    }
}
