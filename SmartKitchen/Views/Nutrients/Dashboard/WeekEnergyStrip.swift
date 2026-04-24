import SwiftUI

/// Tira horizontal de 7 dias que permite selecionar a data ativa do dashboard.
/// Rolável de forma paginada para ver semanas passadas.
struct WeekEnergyStrip: View {
    @Binding var selectedDate: Date
    let caloriesForDate: (Date) -> Int
    let calorieGoal: Int
    let weekStartsOnMonday: Bool

    private static let totalWeeks = 53
    private static let currentWeekIndex = totalWeeks - 1

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
                dayTile(for: date)
            }
        }
    }

    private func dayTile(for date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let isFuture = date > .now
        let progress = progressForDate(date)

        return Button {
            guard !isFuture else { return }
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.snappy(duration: 0.25)) {
                selectedDate = calendar.startOfDay(for: date)
            }
        } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(isSelected ? PageTheme.nutrients.accentColor : .secondary)

                ZStack {
                    Circle()
                        .stroke(isSelected ? PageTheme.nutrients.accentColor.opacity(0.2) : .secondary.opacity(0.12), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            PageTheme.nutrients.accentColor,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    Text(date.formatted(.dateTime.day()))
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(isToday ? PageTheme.nutrients.accentColor : .primary)
                }
                .frame(width: 36, height: 36)
                .background {
                    if isSelected {
                        Circle()
                            .fill(PageTheme.nutrients.accentColor.opacity(0.12))
                    }
                }
            }
            .opacity(isFuture ? 0.35 : 1)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
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
