import SwiftUI
import SwiftData

/// Conteúdo principal do dashboard (strip + ring + macros + refeições do dia).
struct NutritionDashboardView: View {
    @Environment(\.modelContext) private var modelContext

    let profile: NutritionProfile
    let allEntries: [FoodEntry]
    let allDayLogs: [NutritionDayLog]
    @Binding var selectedDate: Date
    var onTapEntry: (FoodEntry) -> Void = { _ in }
    var onDeleteEntry: (FoodEntry) -> Void = { _ in }
    var onPickEntry: (NutritionEntrySheet) -> Void = { _ in }

    @State private var isMonthExpanded = false
    @State private var isPrimaryActionHighlighted = false

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

    private func stateFor(_ date: Date) -> NutritionDayState {
        NutritionDayLogStore.state(
            for: date,
            entries: allEntries,
            logs: allDayLogs,
            calendar: calendar
        )
    }

    private var selectedDayState: NutritionDayState {
        stateFor(selectedDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    WeekEnergyStrip(
                        selectedDate: $selectedDate,
                        caloriesForDate: caloriesFor,
                        calorieGoal: profile.effectiveCalories,
                        weekStartsOnMonday: profile.weekStartsOnMonday,
                        stateForDate: stateFor,
                        isMonthExpanded: $isMonthExpanded
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

                    Color.clear.frame(height: 88)
                }
                .padding(.top, 6)
            }
        }
        .overlay(alignment: .bottomLeading) {
            floatingDayActionButton
                .padding(.leading, 16)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Registros (entradas do dia)

    /// Card unificado “Registros”, com subseções por `MealType`. Cada subseção
    /// usa `ItemListDivider` pontilhado entre as linhas, mesmo padrão de
    /// Listas/Receitas. O botão "Adicionar registro" aparece no header do card,
    /// enquanto cada subseção tem um botão discreto (apenas ícone +) ao lado do
    /// título.
    private var mealSections: some View {
        let allMeals = MealType.allCases.sorted { $0.sortIndex < $1.sortIndex }
        let sections = allMeals.map { meal -> (MealType, [FoodEntry]) in
            let rows = entriesForSelectedDate
                .filter { $0.mealType == meal }
                .sorted { $0.timestamp < $1.timestamp }
            return (meal, rows)
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Registros")
                        .font(.headline.weight(.semibold))
                    Text("Tudo o que você registrou neste dia")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                addRegistroMenu
            }

            VStack(spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.element.0) { index, entry in
                    mealSubsection(meal: entry.0, rows: entry.1, isFirst: index == 0)
                }
            }
            .background(NutritionDashboardView.cardBackground, in: .rect(cornerRadius: 18))
            .clipShape(.rect(cornerRadius: 18))
        }
    }

    @ViewBuilder
    private func mealSubsection(meal: MealType, rows: [FoodEntry], isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: meal.icon)
                    .font(.footnote)
                    .foregroundStyle(PageTheme.nutrients.accentColor)
                Text(meal.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !rows.isEmpty {
                    let total = rows.reduce(0) { $0 + $1.calories }
                    Text("\(total) kcal")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                subsectionAddButton(for: meal)
            }
            .padding(.horizontal, 14)
            .padding(.top, isFirst ? 12 : 14)
            .padding(.bottom, 2)

            if rows.isEmpty {
                Text("Nenhum registro")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            ItemListDivider()
                                .padding(.horizontal, 14)
                                .padding(.vertical, 4)
                        }
                        Button {
                            onTapEntry(entry)
                        } label: {
                            FoodEntryRow(entry: entry)
                                .padding(.horizontal, 6)
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
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
    }

    /// Botão do header do card “Registros”. Reutiliza o mesmo menu da assistant
    /// bar via `onPickEntry`. Sem preferência de refeição (deixa o usuário decidir).
    @ViewBuilder
    private var addRegistroMenu: some View {
        Menu {
            entryPickerMenuContent(prefilledMeal: nil)
        } label: {
            Label("Adicionar", systemImage: "plus")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(PageTheme.nutrients.accentColor.opacity(0.16))
                )
                .foregroundStyle(PageTheme.nutrients.accentColor)
        }
        .menuOrder(.fixed)
    }

    /// Botão discreto (só ícone) usado ao lado do título de cada subseção.
    @ViewBuilder
    private func subsectionAddButton(for meal: MealType) -> some View {
        Menu {
            entryPickerMenuContent(prefilledMeal: meal)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.secondary.opacity(0.10), in: .circle)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Adicionar em \(localizedDisplayName(meal))")
    }

    /// Conteúdo compartilhado dos menus de adicionar registro.
    @ViewBuilder
    private func entryPickerMenuContent(prefilledMeal: MealType?) -> some View {
        Section("Registros Salvos") {
            Button {
                onPickEntry(.manual(prefillName: nil, prefillMealType: prefilledMeal))
            } label: {
                Label("Salvar alimento", systemImage: "fork.knife")
            }
            Button {
                onPickEntry(.recents)
            } label: {
                Label("Alimentos salvos", systemImage: "clock.arrow.circlepath")
            }
        }
        Section("Registros Manuais") {
            Button {
                onPickEntry(.manual(prefillName: nil, prefillMealType: prefilledMeal))
            } label: {
                Label("Registrar manualmente", systemImage: "square.and.pencil")
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

    fileprivate static let cardBackground = Color(red: 248 / 255, green: 248 / 255, blue: 250 / 255)

    // MARK: - Day actions bar

    /// Barra de botões de ação do dia (concluir / reabrir). O texto descritivo
    /// agora vive no header da página (`NutrientsInfoContent`), então aqui
    /// só expomos as ações propriamente ditas, alinhadas à direita.
    @ViewBuilder
    private var dayActionsBar: some View {
        let state = selectedDayState
        switch state {
        case .completed, .canceled:
            actionPill("Reabrir dia", style: .secondary, icon: "arrow.uturn.backward.circle") { reopenSelectedDay() }
        case .todayInProgress, .pastInProgress:
            actionPill("Concluir dia", style: .primary, icon: "checkmark.circle.fill") { completeSelectedDay() }
        case .future, .todayEmpty, .pastEmpty:
            EmptyView()
        }
    }

    /// Botão flutuante de ação do dia, ancorado acima da barra do assistente.
    /// Usa Liquid Glass (iOS 26) com tint discreto coerente com a ação:
    /// verde para "Concluir dia" e laranja para "Reabrir dia".
    @ViewBuilder
    private var floatingDayActionButton: some View {
        switch selectedDayState {
        case .completed, .canceled:
            floatingActionButton(
                title: "Reabrir dia",
                icon: "arrow.uturn.backward",
                tint: Color.orange,
                action: reopenSelectedDay
            )
        case .todayInProgress, .pastInProgress:
            floatingActionButton(
                title: "Concluir dia",
                icon: "checkmark.circle.fill",
                tint: Color(red: 0.15, green: 0.45, blue: 0.25),
                action: completeSelectedDay
            )
        case .future, .todayEmpty, .pastEmpty:
            EmptyView()
        }
    }

    @ViewBuilder
    private func floatingActionButton(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(.capsule)
                .background(floatingActionBackground(tint: tint))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func floatingActionBackground(tint: Color) -> some View {
        if #available(iOS 26, macOS 26, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.tint(tint.opacity(0.18)).interactive(), in: .capsule)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().fill(tint.opacity(0.14))
                )
        }
    }

    @ViewBuilder
    private func actionPill(_ title: String, style: ActionPillStyle, icon: String, action: @escaping () -> Void) -> some View {
        let isPrimary = style == .primary
        Button(action: action) {
            HStack {
                Spacer(minLength: 0)
                Label(title, systemImage: icon)
                Spacer(minLength: 0)
            }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule().fill(
                        isPrimary
                            ? PageTheme.nutrients.accentColor
                            : Color.secondary.opacity(0.15)
                    )
                )
                .overlay {
                    if isPrimary {
                        Capsule()
                            .strokeBorder(Color.white.opacity(isPrimaryActionHighlighted ? 0.28 : 0.14), lineWidth: 1)
                    }
                }
                .scaleEffect(isPrimary && isPrimaryActionHighlighted ? 1.015 : 1.0)
                .shadow(
                    color: isPrimary
                        ? PageTheme.nutrients.accentColor.opacity(isPrimaryActionHighlighted ? 0.34 : 0.18)
                        : .clear,
                    radius: isPrimary ? (isPrimaryActionHighlighted ? 20 : 10) : 0,
                    y: isPrimary ? 8 : 0
                )
                .foregroundStyle(isPrimary ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .onAppear {
            guard isPrimary else { return }

            isPrimaryActionHighlighted = false
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                isPrimaryActionHighlighted = true
            }
        }
        .onDisappear {
            guard isPrimary else { return }
            isPrimaryActionHighlighted = false
        }
    }

    private enum ActionPillStyle { case primary, secondary }

    // MARK: - Actions

    private func completeSelectedDay() {
        NutritionDayLogStore.complete(date: selectedDate, in: modelContext, calendar: calendar)
    }

    private func reopenSelectedDay() {
        NutritionDayLogStore.reopen(date: selectedDate, in: modelContext, calendar: calendar)
    }
}
