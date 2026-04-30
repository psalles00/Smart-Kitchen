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
    var onOpenProgress: () -> Void = {}

    @State private var isMonthExpanded = false
    @State private var isPrimaryActionHighlighted = false
    @State private var macroPageIndex: Int = 0

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

    private var fiberConsumed: Double {
        entriesForSelectedDate.reduce(0) { $0 + ($1.fiberG ?? 0) }
    }

    private var sugarConsumed: Double {
        entriesForSelectedDate.reduce(0) { $0 + ($1.sugarG ?? 0) }
    }

    private var sodiumConsumed: Double {
        entriesForSelectedDate.reduce(0) { $0 + ($1.sodiumMg ?? 0) }
    }

    private var saturatedFatConsumed: Double {
        entriesForSelectedDate.reduce(0) { $0 + ($1.saturatedFatG ?? 0) }
    }

    private var cholesterolConsumed: Double {
        entriesForSelectedDate.reduce(0) { $0 + ($1.cholesterolMg ?? 0) }
    }

    private var potassiumConsumed: Double {
        entriesForSelectedDate.reduce(0) { $0 + ($1.potassiumMg ?? 0) }
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
                VStack(spacing: 18) {
                    VStack(spacing: 18) {
                        WeekEnergyStrip(
                            selectedDate: $selectedDate,
                            caloriesForDate: caloriesFor,
                            calorieGoal: profile.effectiveCalories,
                            weekStartsOnMonday: profile.weekStartsOnMonday,
                            stateForDate: stateFor,
                            isMonthExpanded: $isMonthExpanded
                        )
                        .padding(.horizontal, 12)

                        Button(action: onOpenProgress) {
                            VStack(spacing: 34) {
                                CalorieRingView(consumed: caloriesConsumed, goal: profile.effectiveCalories)
                                    .padding(.top, 0)

                                macrosPager
                                    .padding(.horizontal, 4)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)

                        mealSections
                            .padding(.top, 12)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                    }
                    .padding(.top, -5)
                    .overlay(alignment: .top) {
                        wavyStateBorder
                            .padding(.top, -5)
                            .allowsHitTesting(false)
                    }

                    Color.clear.frame(height: 88)
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            floatingDayActionButton
                .padding(.leading, 16)
                .padding(.bottom, 8)
        }
    }

    /// Borda ondulada que aparece como overlay sobre o bloco principal do
    /// conteúdo da Nutrição. Como fica dentro do scroll, acompanha o fundo
    /// branco ao rolar, mas termina logo abaixo de "Refeições do dia" — sem
    /// incluir o spacer final da página.
    @ViewBuilder
    private var wavyStateBorder: some View {
        switch selectedDayState {
        case .todayInProgress, .pastInProgress:
            WavyPanelBorder()
                .stroke(Color(red: 0.96, green: 0.78, blue: 0.26), lineWidth: 1.4)
        case .completed:
            WavyPanelBorder()
                .stroke(Color(red: 0.31, green: 0.74, blue: 0.46), lineWidth: 1.4)
        default:
            EmptyView()
        }
    }

    // MARK: - Registros (entradas do dia)

    /// Carrossel paginado de macros / micros. Página 1 = macros principais
    /// (Proteína / Carbos / Gordura). Páginas 2 e 3 mostram micronutrientes
    /// adicionais (fibra, açúcar, sódio, gordura saturada, colesterol, potássio).
    /// Indicador de pontos abaixo, padrão de paging do iOS.
    @ViewBuilder
    private var macrosPager: some View {
        VStack(spacing: 10) {
            TabView(selection: $macroPageIndex) {
                macroPageMain
                    .padding(.horizontal, 0)
                    .tag(0)

                macroPageMicros1
                    .padding(.horizontal, 0)
                    .tag(1)

                macroPageMicros2
                    .padding(.horizontal, 0)
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 86)

            // Indicador customizado para garantir aparência neutra.
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { idx in
                    Circle()
                        .fill(idx == macroPageIndex
                              ? Color.primary.opacity(0.55)
                              : Color.primary.opacity(0.18))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Página \(macroPageIndex + 1) de 3")
        }
    }

    @ViewBuilder
    private var macroPageMain: some View {
        HStack(spacing: 10) {
            MacroCard(label: String(localized: "Proteína"), current: proteinConsumed, goal: profile.effectiveProteinG)
            MacroCard(label: String(localized: "Carbos"), current: carbsConsumed, goal: profile.effectiveCarbsG)
            MacroCard(label: String(localized: "Gordura"), current: fatConsumed, goal: profile.effectiveFatG)
        }
    }

    /// Página 2 — micronutrientes comuns. Metas baseadas em referências
    /// de DRI gerais (placeholder enquanto não há configuração de meta para
    /// micros no perfil).
    @ViewBuilder
    private var macroPageMicros1: some View {
        HStack(spacing: 10) {
            MacroCard(label: String(localized: "Fibra"), current: fiberConsumed, goal: 25)
            MacroCard(label: String(localized: "Açúcar"), current: sugarConsumed, goal: 50)
            MacroCard(label: String(localized: "Sódio"), current: sodiumConsumed, goal: 2300)
        }
    }

    @ViewBuilder
    private var macroPageMicros2: some View {
        HStack(spacing: 10) {
            MacroCard(label: String(localized: "Saturada"), current: saturatedFatConsumed, goal: 20)
            MacroCard(label: String(localized: "Colesterol"), current: cholesterolConsumed, goal: 300)
            MacroCard(label: String(localized: "Potássio"), current: potassiumConsumed, goal: 3500)
        }
    }

    /// Card unificado “Refeições do dia”, com subseções por `MealType`. Cada subseção
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
                HStack(spacing: 4) {
                    Text(String(localized: "Refeições do dia"))
                        .font(.headline.weight(.semibold))
                    SectionInfoButton(
                        title: "Refeições do dia",
                        message: "Lista os alimentos registrados neste dia, agrupados por refeição (café, almoço, lanche e jantar). Use o + para registrar um novo alimento."
                    )
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
                    .foregroundStyle(.secondary)
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
                Text(String(localized: "Nenhum registro"))
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

    /// Botão do header do card “Refeições do dia”. Outline-only com verde
    /// discreto aplicado tanto no texto quanto na borda.
    @ViewBuilder
    private var addRegistroMenu: some View {
        Menu {
            entryPickerMenuContent(prefilledMeal: nil)
        } label: {
            Label(String(localized: "Adicionar"), systemImage: "plus")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(Color(red: 0.31, green: 0.74, blue: 0.46))
                .overlay(
                    Capsule().stroke(Color(red: 0.31, green: 0.74, blue: 0.46), lineWidth: 1)
                )
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
                Label(String(localized: "Salvar alimento"), systemImage: "fork.knife")
            }
            Button {
                onPickEntry(.recents)
            } label: {
                Label(String(localized: "Alimentos salvos"), systemImage: "clock.arrow.circlepath")
            }
        }
        Section("Registros Manuais") {
            Button {
                onPickEntry(.manual(prefillName: nil, prefillMealType: prefilledMeal))
            } label: {
                Label(String(localized: "Registrar manualmente"), systemImage: "square.and.pencil")
            }
        }
        Section("Registrar por…") {
            Button {
                onPickEntry(.captureLabel)
            } label: {
                Label(String(localized: "Rótulo"), systemImage: "doc.text.viewfinder")
            }
            Button {
                onPickEntry(.capturePhotoGallery)
            } label: {
                Label(String(localized: "Galeria"), systemImage: "photo")
            }
            #if os(iOS)
            Button {
                onPickEntry(.capturePhotoCamera)
            } label: {
                Label(String(localized: "Câmera"), systemImage: "camera")
            }
            #endif
            Button {
                onPickEntry(.captureVoice)
            } label: {
                Label(String(localized: "Voz"), systemImage: "waveform")
            }
            Button {
                onPickEntry(.captureText(prefillText: nil, autoAnalyze: false))
            } label: {
                Label(String(localized: "Texto"), systemImage: "character.cursor.ibeam")
            }
        }
    }

    private func localizedDisplayName(_ meal: MealType) -> String {
        switch meal {
        case .breakfast: String(localized: "Café da manhã")
        case .lunch:     String(localized: "Almoço")
        case .dinner:    String(localized: "Jantar")
        case .snack:     String(localized: "Lanche")
        case .other:     String(localized: "Outras")
        }
    }

    fileprivate static let cardBackground = neutralSurfaceColor

    // MARK: - Day actions bar

    /// Barra de botões de ação do dia (concluir / reabrir). O texto descritivo
    /// agora vive no header da página (`NutrientsInfoContent`), então aqui
    /// só expomos as ações propriamente ditas, alinhadas à direita.
    @ViewBuilder
    private var dayActionsBar: some View {
        let state = selectedDayState
        switch state {
        case .completed, .canceled:
            actionPill(String(localized: "Reabrir dia"), style: .secondary, icon: "arrow.uturn.backward.circle") { reopenSelectedDay() }
        case .todayInProgress, .pastInProgress:
            actionPill(String(localized: "Concluir dia"), style: .primary, icon: "checkmark.circle.fill") { completeSelectedDay() }
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
                title: String(localized: "Reabrir dia"),
                icon: "arrow.uturn.backward",
                tint: Color.orange,
                action: reopenSelectedDay
            )
        case .todayInProgress, .pastInProgress:
            floatingActionButton(
                title: String(localized: "Concluir dia"),
                icon: "checkmark.circle.fill",
                tint: Color(red: 0.15, green: 0.45, blue: 0.25),
                action: completeSelectedDay
            )
        case .todayEmpty, .pastEmpty:
            floatingEntryMenuButton(title: String(localized: "Iniciar dia"), icon: "plus")
        case .future:
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
    private func floatingEntryMenuButton(title: String, icon: String) -> some View {
        Menu {
            entryPickerMenuContent(prefilledMeal: nil)
        } label: {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(.capsule)
                .background(floatingNeutralActionBackground())
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
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
    private func floatingNeutralActionBackground() -> some View {
        if #available(iOS 26, macOS 26, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1)
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
