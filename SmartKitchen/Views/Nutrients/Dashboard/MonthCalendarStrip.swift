import SwiftUI

/// Calendário mensal rolável horizontalmente (paginação por mês).
/// Cada dia usa `NutritionDayTile`, com cores derivadas do estado.
struct MonthCalendarStrip: View {
    @Binding var selectedDate: Date
    let stateForDate: (Date) -> NutritionDayState
    let progressForDate: (Date) -> Double
    let weekStartsOnMonday: Bool

    private static let totalMonths = 25
    private static let currentMonthIndex = totalMonths - 1

    @State private var hasScrolledToInitial = false

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = weekStartsOnMonday ? 2 : 1
        return cal
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<Self.totalMonths, id: \.self) { monthIndex in
                        monthGrid(for: monthIndex)
                            .containerRelativeFrame(.horizontal)
                            .id(monthIndex)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .frame(height: 280)
            .onAppear {
                guard !hasScrolledToInitial else { return }
                hasScrolledToInitial = true
                proxy.scrollTo(monthIndex(for: selectedDate), anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func monthGrid(for monthIndex: Int) -> some View {
        let monthStart = monthStartDate(for: monthIndex)
        VStack(spacing: 6) {
            // Cabeçalho do mês
            HStack {
                Text(monthHeader(monthStart))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 8)

            // Cabeçalho dos dias da semana
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Grade 6 linhas × 7 colunas
            VStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { col in
                            cellView(monthStart: monthStart, row: row, col: col)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func cellView(monthStart: Date, row: Int, col: Int) -> some View {
        if let date = dateForCell(monthStart: monthStart, row: row, col: col) {
            let inMonth = calendar.isDate(date, equalTo: monthStart, toGranularity: .month)
            NutritionDayTile(
                date: date,
                state: stateForDate(date),
                progress: progressForDate(date),
                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                showWeekday: false,
                onTap: {
                    withAnimation(.snappy(duration: 0.25)) {
                        selectedDate = calendar.startOfDay(for: date)
                    }
                }
            )
            .opacity(inMonth ? 1 : 0.25)
        } else {
            Color.clear.frame(height: 36)
        }
    }

    // MARK: - Date math

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        // Reordena conforme firstWeekday.
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func monthStartDate(for monthIndex: Int) -> Date {
        let today = calendar.startOfDay(for: .now)
        let comps = calendar.dateComponents([.year, .month], from: today)
        let currentMonthStart = calendar.date(from: comps) ?? today
        return calendar.date(byAdding: .month, value: monthIndex - Self.currentMonthIndex, to: currentMonthStart) ?? currentMonthStart
    }

    private func monthIndex(for date: Date) -> Int {
        let today = calendar.startOfDay(for: .now)
        let currentComps = calendar.dateComponents([.year, .month], from: today)
        let dateComps = calendar.dateComponents([.year, .month], from: date)
        let diff = (dateComps.year! - currentComps.year!) * 12 + (dateComps.month! - currentComps.month!)
        return Self.currentMonthIndex + diff
    }

    private func dateForCell(monthStart: Date, row: Int, col: Int) -> Date? {
        // Encontra o início da semana que contém o dia 1 do mês.
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingOffset = (firstWeekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingOffset, to: monthStart) else { return nil }
        let dayOffset = row * 7 + col
        return calendar.date(byAdding: .day, value: dayOffset, to: gridStart)
    }

    private func monthHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt-BR")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).localizedCapitalized
    }
}
