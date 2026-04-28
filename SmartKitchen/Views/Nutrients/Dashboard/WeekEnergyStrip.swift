import SwiftUI

/// Tira horizontal de 7 dias que permite selecionar a data ativa do dashboard.
/// Pode ser expandida para um calendário mensal através do binding `isMonthExpanded`.
///
/// Cores e estado por dia vêm do `NutritionDayTile` — hoje vazio é cinza
/// (não mais verde), concluído é verde, em andamento é amarelo e pendentes
/// passados são vermelhos discretos.
struct WeekEnergyStrip: View {
    @Binding var selectedDate: Date
    let caloriesForDate: (Date) -> Int
    let calorieGoal: Int
    let weekStartsOnMonday: Bool
    let stateForDate: (Date) -> NutritionDayState
    @Binding var isMonthExpanded: Bool

    private static let totalWeeks = 53
    private static let currentWeekIndex = totalWeeks - 1

    @State private var hasScrolledToInitial = false

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = weekStartsOnMonday ? 2 : 1
        return cal
    }

    var body: some View {
        if isMonthExpanded {
            VStack(spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    calendarToggleButton
                    Spacer()
                    backToTodayButton
                }
                .padding(.horizontal, 4)

                MonthCalendarStrip(
                    selectedDate: $selectedDate,
                    stateForDate: stateForDate,
                    progressForDate: progressForDate,
                    weekStartsOnMonday: weekStartsOnMonday
                )
            }
        } else {
            HStack(alignment: .center, spacing: 0) {
                calendarToggleButton
                weekScrollView
            }
        }
    }

    // MARK: - Toggle button

    /// Botão de calendário com a mesma altura/largura/posicionamento dos
    /// `NutritionDayTile`. Reserva o mesmo espaço do label do dia da semana
    /// para alinhar verticalmente com os tiles vizinhos.
    private var calendarToggleButton: some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.snappy(duration: 0.28)) {
                isMonthExpanded.toggle()
            }
        } label: {
            // Reservamos a mesma altura dos tiles vizinhos e centralizamos o
            // ícone verticalmente dentro do retângulo arredondado.
            ZStack {
                Image(systemName: isMonthExpanded ? "calendar.badge.minus" : "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.31, green: 0.74, blue: 0.46))
            }
            .frame(width: 38, height: 42)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(red: 0.31, green: 0.74, blue: 0.46), lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
            .frame(width: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMonthExpanded ? "Recolher calendário" : "Expandir calendário")
    }

    /// Pill discreto exibido quando o calendário está aberto, para retornar
    /// rapidamente para o dia de hoje.
    private var backToTodayButton: some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.snappy(duration: 0.25)) {
                selectedDate = Calendar.current.startOfDay(for: .now)
            }
        } label: {
            VStack(spacing: 4) {
                Text(" ")
                    .font(.system(.caption2, design: .rounded, weight: .medium))

                Label("Hoje", systemImage: "target")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(PageTheme.nutrients.accentColor.opacity(0.14))
                    )
                    .foregroundStyle(PageTheme.nutrients.accentColor)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voltar para hoje")
    }

    // MARK: - Week scroll view

    private var weekScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<Self.totalWeeks, id: \.self) { weekIndex in
                        weekRow(for: weekIndex)
                            .containerRelativeFrame(.horizontal)
                            .id(weekIndex)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .frame(height: 74)
            .onAppear {
                guard !hasScrolledToInitial else { return }
                hasScrolledToInitial = true
                proxy.scrollTo(weekIndex(for: selectedDate), anchor: .trailing)
            }
            .onChange(of: weekStartsOnMonday) { _, _ in
                proxy.scrollTo(Self.currentWeekIndex, anchor: .trailing)
            }
        }
    }

    @ViewBuilder
    private func weekRow(for weekIndex: Int) -> some View {
        let dates = weekDates(for: weekIndex)
        HStack(spacing: 0) {
            ForEach(dates, id: \.self) { date in
                NutritionDayTile(
                    date: date,
                    state: stateForDate(date),
                    progress: progressForDate(date),
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                    showWeekday: true,
                    onTap: {
                        withAnimation(.snappy(duration: 0.25)) {
                            selectedDate = calendar.startOfDay(for: date)
                        }
                    }
                )
            }
        }
    }

    // MARK: - Date math

    private func weekDates(for weekOffset: Int) -> [Date] {
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)
        let daysBack = (weekday - calendar.firstWeekday + 7) % 7
        guard let startOfCurrent = calendar.date(byAdding: .day, value: -daysBack, to: today),
              let start = calendar.date(byAdding: .weekOfYear, value: weekOffset - Self.currentWeekIndex, to: startOfCurrent)
        else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func weekIndex(for date: Date) -> Int {
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)
        let daysBack = (weekday - calendar.firstWeekday + 7) % 7
        guard let startOfCurrent = calendar.date(byAdding: .day, value: -daysBack, to: today) else {
            return Self.currentWeekIndex
        }
        let diff = calendar.dateComponents([.weekOfYear], from: startOfCurrent, to: calendar.startOfDay(for: date)).weekOfYear ?? 0
        return Self.currentWeekIndex + diff
    }

    private func progressForDate(_ date: Date) -> Double {
        guard calorieGoal > 0 else { return 0 }
        return min(Double(caloriesForDate(date)) / Double(calorieGoal), 1.0)
    }
}
