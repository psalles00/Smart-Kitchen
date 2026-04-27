import SwiftUI
import SwiftData

/// Card "Registro não concluído" exibido na Home.
///
/// Mostra apenas dias **iniciados mas não concluídos**. Tap na linha abre
/// a aba Nutrição naquela data (equivalente a "Continuar"). Long-press
/// (menu de contexto) e swipe horizontal revelam `Concluir` e `Desistir`,
/// ambos com confirmação explicando o efeito.
///
/// O swipe é implementado manualmente porque `.swipeActions` da SwiftUI
/// só funciona dentro de `List`, e este card vive em um `VStack` da Home.
struct PendingNutritionDaysCard: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var allEntries: [FoodEntry]
    @Query(sort: \NutritionDayLog.dayStart, order: .reverse) private var allDayLogs: [NutritionDayLog]
    @Query(sort: \NutritionProfile.createdAt) private var profiles: [NutritionProfile]

    @State private var pendingConfirmation: PendingConfirmation?
    @State private var revealedDayID: Date?

    private var calendar: Calendar { .current }
    private var profile: NutritionProfile? { profiles.first }
    private var calorieGoal: Int { profile?.effectiveCalories ?? 0 }

    private struct PendingConfirmation: Identifiable {
        enum Kind { case complete, cancel }
        let id = UUID()
        let kind: Kind
        let date: Date
    }

    private var startedDays: [PendingNutritionDaysCard_RowDay] {
        let today = calendar.startOfDay(for: .now)
        guard let cutoff = calendar.date(byAdding: .day, value: -60, to: today) else { return [] }

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
        return results
    }

    var body: some View {
        let days = startedDays
        if days.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Registro não concluído")
                            .font(.headline.weight(.semibold))
                        Text("Você começou estes dias e ainda não concluiu — eles não entram na sua média até serem concluídos.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(days.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.yellow.opacity(0.16), in: .capsule)
                }

                VStack(spacing: 0) {
                    ForEach(Array(days.prefix(5).enumerated()), id: \.element.id) { index, day in
                        SwipeablePendingRow(
                            day: day,
                            calorieGoal: calorieGoal,
                            isRevealed: revealedDayID == day.id,
                            onTap: {
                                if revealedDayID != nil {
                                    revealedDayID = nil
                                } else {
                                    openNutrition(at: day.date)
                                }
                            },
                            onRevealChange: { shouldReveal in
                                revealedDayID = shouldReveal ? day.id : nil
                            },
                            onComplete: {
                                revealedDayID = nil
                                pendingConfirmation = PendingConfirmation(kind: .complete, date: day.date)
                            },
                            onCancel: {
                                revealedDayID = nil
                                pendingConfirmation = PendingConfirmation(kind: .cancel, date: day.date)
                            },
                            titleProvider: { titleLabel(for: day.date) }
                        )
                        if index < min(days.count, 5) - 1 {
                            ItemListDivider().padding(.horizontal, 14)
                        }
                    }
                }
                .background(Self.cardBackground, in: .rect(cornerRadius: 18))
                .clipShape(.rect(cornerRadius: 18))
            }
            .confirmationDialog(
                confirmationTitle,
                isPresented: confirmationBinding,
                titleVisibility: .visible,
                presenting: pendingConfirmation
            ) { confirmation in
                Button(
                    confirmation.kind == .complete ? "Concluir dia" : "Desistir do dia",
                    role: confirmation.kind == .cancel ? .destructive : nil
                ) {
                    perform(confirmation)
                }
                Button("Cancelar", role: .cancel) {}
            } message: { confirmation in
                Text(confirmationMessage(for: confirmation))
            }
        }
    }

    // MARK: - Confirmation handling

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingConfirmation != nil },
            set: { if !$0 { pendingConfirmation = nil } }
        )
    }

    private var confirmationTitle: String {
        guard let kind = pendingConfirmation?.kind else { return "" }
        return kind == .complete ? "Concluir este dia?" : "Desistir deste dia?"
    }

    private func confirmationMessage(for confirmation: PendingConfirmation) -> String {
        let label = titleLabel(for: confirmation.date).lowercased()
        switch confirmation.kind {
        case .complete:
            return "Os registros de \(label) entrarão no cálculo da sua média e o dia sairá desta lista."
        case .cancel:
            return "Os registros de \(label) serão descartados do cálculo da média e o dia sairá desta lista. Você poderá reabrir mais tarde, se quiser."
        }
    }

    private func perform(_ confirmation: PendingConfirmation) {
        switch confirmation.kind {
        case .complete:
            NutritionDayLogStore.complete(date: confirmation.date, in: modelContext)
        case .cancel:
            NutritionDayLogStore.cancel(date: confirmation.date, in: modelContext)
        }
    }

    // MARK: - Helpers

    private func titleLabel(for date: Date) -> String {
        if calendar.isDateInToday(date) { return "Hoje" }
        if calendar.isDateInYesterday(date) { return "Ontem" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt-BR")
        formatter.dateFormat = "EEEE, d 'de' MMMM"
        return formatter.string(from: date).localizedCapitalized
    }

    private func openNutrition(at date: Date) {
        NotificationCenter.default.post(
            name: .openNutritionAtDate,
            object: nil,
            userInfo: ["date": calendar.startOfDay(for: date)]
        )
    }

    /// Mesma cor do `homeShortcutBackgroundColor` em `ContentView` (aquele é
    /// `fileprivate`).
    fileprivate static let cardBackground = Color(red: 248 / 255, green: 248 / 255, blue: 250 / 255)
}

// MARK: - Swipeable row

private struct SwipeablePendingRow: View {
    let day: PendingNutritionDaysCard_RowDay
    let calorieGoal: Int
    let isRevealed: Bool
    let onTap: () -> Void
    let onRevealChange: (Bool) -> Void
    let onComplete: () -> Void
    let onCancel: () -> Void
    let titleProvider: () -> String

    @State private var dragOffset: CGFloat = 0

    private let actionWidth: CGFloat = 76
    private let revealThreshold: CGFloat = 50

    private var totalRevealedWidth: CGFloat { actionWidth * 2 }

    private var effectiveOffset: CGFloat {
        let base: CGFloat = isRevealed ? -totalRevealedWidth : 0
        let combined = base + dragOffset
        return min(0, max(combined, -totalRevealedWidth - 30))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                actionButton(
                    title: "Concluir",
                    icon: "checkmark.circle.fill",
                    background: PageTheme.nutrients.accentColor,
                    action: onComplete
                )
                actionButton(
                    title: "Desistir",
                    icon: "xmark.circle.fill",
                    background: .red,
                    action: onCancel
                )
            }
            .frame(width: totalRevealedWidth)
            .opacity(min(1.0, Double(abs(effectiveOffset)) / 20.0))

            rowContent
                .background(PendingNutritionDaysCard.cardBackground)
                .offset(x: effectiveOffset)
                .gesture(swipeGesture)
                .onTapGesture { onTap() }
                .contextMenu {
                    Button {
                        onTap() // openNutrition path when not revealed
                    } label: {
                        Label("Continuar", systemImage: "arrow.right.circle")
                    }
                    Button(action: onComplete) {
                        Label("Concluir", systemImage: "checkmark.circle")
                    }
                    Button(role: .destructive, action: onCancel) {
                        Label("Desistir", systemImage: "xmark.circle")
                    }
                }
        }
        .clipped()
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.85), value: effectiveOffset)
    }

    private var rowContent: some View {
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
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                dragOffset = horizontal
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let combined = (isRevealed ? -totalRevealedWidth : 0) + horizontal
                let predictedCombined = (isRevealed ? -totalRevealedWidth : 0) + predicted

                let shouldReveal: Bool
                if predictedCombined < -revealThreshold {
                    shouldReveal = true
                } else if combined > -revealThreshold {
                    shouldReveal = false
                } else {
                    shouldReveal = isRevealed
                }
                dragOffset = 0
                if shouldReveal != isRevealed {
                    onRevealChange(shouldReveal)
                }
            }
    }

    @ViewBuilder
    private func actionButton(title: String, icon: String, background: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
        }
        .buttonStyle(.plain)
        .frame(width: actionWidth)
    }

    @ViewBuilder
    private func miniCalorieRing(consumed: Int, goal: Int) -> some View {
        let progress: Double = {
            guard goal > 0 else { return 0 }
            return min(Double(consumed) / Double(goal), 1.0)
        }()
        ZStack {
            Circle()
                .stroke(Color.yellow.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(consumed)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 2)
        }
        .frame(width: 36, height: 36)
    }
}

/// Tipo usado pelas linhas do card. Mantido em escopo de módulo (não privado)
/// porque `SwipeablePendingRow` precisa referenciá-lo no seu init.
struct PendingNutritionDaysCard_RowDay: Identifiable {
    let id: Date
    let date: Date
    let entryCount: Int
    let calorieTotal: Int
}

private extension PendingNutritionDaysCard {
    /// Bridge entre o tipo interno e o tipo consumido pela linha.
    static func bridge(_ day: PendingNutritionDaysCard) {}
}
