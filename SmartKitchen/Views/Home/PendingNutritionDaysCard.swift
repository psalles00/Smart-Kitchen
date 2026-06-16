import SwiftUI
import SwiftData

/// Card "Registro não concluído" exibido na Home.
///
/// Mostra apenas dias **iniciados mas não concluídos**. Tap na linha abre
/// a aba Nutrição naquela data (equivalente a "Continuar"). Long-press
/// (menu de contexto) e swipe horizontal revelam `Concluir` e `Desistir`,
/// ambos com confirmação explicando o efeito.
///
/// Backend usa o mesmo padrão das telas em `Views/Lists/`: um `List` com
/// `.swipeActions(...)` nativos. A `List` interna fica `scrollDisabled` para
/// que a rolagem vertical seja delegada ao `ScrollView` pai da Home, e o
/// gesto de swipe horizontal é tratado nativamente pelo SwiftUI sem
/// interferir na rolagem.
struct PendingNutritionDaysCard: View {
    private let days: [PendingNutritionDaysCard_RowDay]?
    private let calorieGoal: Int?

    init(
        days: [PendingNutritionDaysCard_RowDay]? = nil,
        calorieGoal: Int? = nil
    ) {
        self.days = days
        self.calorieGoal = calorieGoal
    }

    var body: some View {
        if let days, let calorieGoal {
            PendingNutritionDaysCardContent(days: days, calorieGoal: calorieGoal)
        } else {
            PendingNutritionDaysCardLive()
        }
    }

    /// Mesma cor do `homeShortcutBackgroundColor` em `ContentView` (aquele é
    /// `fileprivate`).
    fileprivate static let cardBackground = neutralSurfaceColor
}

private struct PendingNutritionDaysCardLive: View {
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var allEntries: [FoodEntry]
    @Query(sort: \NutritionDayLog.dayStart, order: .reverse) private var allDayLogs: [NutritionDayLog]
    @Query(sort: \NutritionProfile.createdAt) private var profiles: [NutritionProfile]

    @State private var startedDaysState: [PendingNutritionDaysCard_RowDay] = []
    @State private var calorieGoalState: Int = 0
    @State private var didRunInitialRefresh = false
    @State private var refreshWorkItem: DispatchWorkItem?

    private var calendar: Calendar { .current }

    var body: some View {
        PendingNutritionDaysCardContent(days: startedDaysState, calorieGoal: calorieGoalState)
        .onAppear {
            if !didRunInitialRefresh {
                didRunInitialRefresh = true
                refreshCardState()
            }
        }
        .onChange(of: allEntries) { _, _ in
            scheduleRefresh()
        }
        .onChange(of: allDayLogs) { _, _ in
            scheduleRefresh()
        }
        .onChange(of: profiles) { _, _ in
            scheduleRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionDayLogChanged)) { _ in
            scheduleRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeDataShouldRefresh)) { _ in
            scheduleRefresh()
        }
    }

    private func scheduleRefresh() {
        refreshWorkItem?.cancel()
        let work = DispatchWorkItem {
            refreshCardState()
        }
        refreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func refreshCardState() {
        calorieGoalState = profiles.first?.effectiveCalories ?? 0

        let today = calendar.startOfDay(for: .now)
        guard let cutoff = calendar.date(byAdding: .day, value: -60, to: today) else {
            startedDaysState = []
            return
        }

        var results: [PendingNutritionDaysCard_RowDay] = []
        var cursor = today
        while cursor >= cutoff {
            let state = NutritionDayLogStore.state(
                for: cursor,
                entries: allEntries,
                logs: allDayLogs,
                calendar: calendar
            )
            if state == .todayInProgress || state == .pastInProgress {
                let entriesForDay = allEntries.filter { calendar.isDate($0.timestamp, inSameDayAs: cursor) }
                results.append(
                    PendingNutritionDaysCard_RowDay(
                        id: cursor,
                        date: cursor,
                        entryCount: entriesForDay.count,
                        calorieTotal: entriesForDay.reduce(0) { $0 + $1.calories }
                    )
                )
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        startedDaysState = results
        refreshWorkItem = nil
    }
}

private struct PendingNutritionDaysCardContent: View {
    @Environment(\.modelContext) private var modelContext

    let days: [PendingNutritionDaysCard_RowDay]
    let calorieGoal: Int

    @State private var pendingAction: PendingActionRequest?

    private var calendar: Calendar { .current }
    private static let rowHeight: CGFloat = 60

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 0)

            if !days.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(spacing: 4) {
                            Text("Registro não concluído")
                                .font(.headline.weight(.semibold))
                            SectionInfoButton(
                                title: "Registro não concluído",
                                message: "Dias que você começou a registrar mas ainda não concluiu. Eles não entram na sua média até serem concluídos. Toque na linha para continuar, ou arraste para concluir/desistir."
                            )
                        }

                        Spacer()

                        Text("\(days.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.secondary.opacity(0.14), in: .capsule)
                    }

                    VStack(spacing: 0) {
                        let visibleDays = Array(days.prefix(5))
                        List {
                            ForEach(Array(visibleDays.enumerated()), id: \.element.id) { index, day in
                                Button {
                                    openNutrition(at: day.date)
                                } label: {
                                    PendingDayRow(
                                        day: day,
                                        calorieGoal: calorieGoal,
                                        titleProvider: { titleLabel(for: day.date) },
                                        showsBottomDivider: index < visibleDays.count - 1
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        openNutrition(at: day.date)
                                    } label: {
                                        Label("Continuar", systemImage: "arrow.right.circle")
                                    }
                                    Button {
                                        pendingAction = .init(action: .complete, day: day)
                                    } label: {
                                        Label("Concluir", systemImage: "checkmark.circle")
                                    }
                                    Button(role: .destructive) {
                                        pendingAction = .init(action: .cancel, day: day)
                                    } label: {
                                        Label("Desistir", systemImage: "xmark.circle")
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        pendingAction = .init(action: .cancel, day: day)
                                    } label: {
                                        Label("Desistir", systemImage: "xmark.circle.fill")
                                    }
                                    .tint(.red)

                                    Button {
                                        pendingAction = .init(action: .complete, day: day)
                                    } label: {
                                        Label("Concluir", systemImage: "checkmark.circle.fill")
                                    }
                                    .tint(PageTheme.nutrients.accentColor)
                                }
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                        .scrollDisabled(true)
                        .scrollContentBackground(.hidden)
                        .environment(\.defaultMinListRowHeight, 0)
                        .frame(height: CGFloat(visibleDays.count) * Self.rowHeight)
                    }
                    .background(PendingNutritionDaysCard.cardBackground, in: .rect(cornerRadius: 18))
                    .clipShape(.rect(cornerRadius: 18))
                    .confirmationDialog(
                        confirmationTitle(for: pendingAction),
                        isPresented: confirmationBinding,
                        titleVisibility: .visible,
                        presenting: pendingAction
                    ) { request in
                        Button(
                            request.action == .complete
                                ? String(localized: "Concluir dia")
                                : String(localized: "Desistir do dia"),
                            role: request.action == .cancel ? .destructive : nil
                        ) {
                            switch request.action {
                            case .complete:
                                NutritionDayLogStore.complete(date: request.day.date, in: modelContext)
                            case .cancel:
                                NutritionDayLogStore.cancel(date: request.day.date, in: modelContext)
                            }
                            pendingAction = nil
                        }
                        Button("Cancelar", role: .cancel) {}
                    } message: { request in
                        Text(confirmationMessage(for: request))
                    }
                }
            }
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingAction != nil },
            set: { if !$0 { pendingAction = nil } }
        )
    }

    private func confirmationTitle(for request: PendingActionRequest?) -> String {
        guard let request else { return "" }
        return request.action == .complete
            ? String(localized: "Concluir este dia?")
            : String(localized: "Desistir deste dia?")
    }

    private func confirmationMessage(for request: PendingActionRequest) -> String {
        let label = titleLabel(for: request.day.date).lowercased()
        switch request.action {
        case .complete:
            return String(localized: "Os registros de \(label) entrarão no cálculo da sua média e o dia sairá desta lista.")
        case .cancel:
            return String(localized: "Os registros de \(label) serão descartados do cálculo da média e o dia sairá desta lista. Você poderá reabrir mais tarde, se quiser.")
        }
    }

    private func titleLabel(for date: Date) -> String {
        if calendar.isDateInToday(date) { return String(localized: "Hoje") }
        if calendar.isDateInYesterday(date) { return String(localized: "Ontem") }
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.current().formattingLocale
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: date).localizedCapitalized
    }

    private func openNutrition(at date: Date) {
        NotificationCenter.default.post(
            name: .openNutritionAtDate,
            object: nil,
            userInfo: ["date": calendar.startOfDay(for: date)]
        )
    }

}

// MARK: - Action request

private struct PendingActionRequest: Identifiable {
    enum Kind { case complete, cancel }
    let action: Kind
    let day: PendingNutritionDaysCard_RowDay
    var id: String { "\(action == .complete ? "c" : "x")-\(day.id.timeIntervalSince1970)" }
}

// MARK: - Row content (visual)

private struct PendingDayRow: View {
    let day: PendingNutritionDaysCard_RowDay
    let calorieGoal: Int
    let titleProvider: () -> String
    let showsBottomDivider: Bool

    var body: some View {
        HStack(spacing: 12) {
            miniCalorieRing(consumed: day.calorieTotal, goal: calorieGoal)

            VStack(alignment: .leading, spacing: 3) {
                Text(titleProvider())
                    .font(.subheadline.weight(.semibold))
                Text("\(day.entryCount) registro\(day.entryCount == 1 ? "" : "s") · \(day.calorieTotal) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PendingNutritionDaysCard.cardBackground)
        .overlay(alignment: .bottom) {
            if showsBottomDivider {
                ItemListDivider().padding(.horizontal, 14)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func miniCalorieRing(consumed: Int, goal: Int) -> some View {
        let progress: Double = {
            guard goal > 0 else { return 0 }
            return min(Double(consumed) / Double(goal), 1.0)
        }()
        let valueText = String(consumed)
        let fontSize: CGFloat = {
            switch valueText.count {
            case 0...2: return 11
            case 3: return 10
            case 4: return 8.5
            default: return 7.5
            }
        }()
        let textWidth: CGFloat = valueText.count >= 4 ? 24 : 20
        ZStack {
            Circle()
                .stroke(Color.yellow.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(valueText)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
                .frame(maxWidth: textWidth)
        }
        .frame(width: 40, height: 40)
    }
}

/// Tipo usado pelas linhas do card.
struct PendingNutritionDaysCard_RowDay: Identifiable {
    let id: Date
    let date: Date
    let entryCount: Int
    let calorieTotal: Int
}
