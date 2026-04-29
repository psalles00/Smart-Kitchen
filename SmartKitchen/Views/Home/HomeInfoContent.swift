import SwiftUI
import SwiftData

struct HomeInfoContent: View {
    @Query(filter: #Predicate<UnifiedItem> { $0.isPantry }, sort: \UnifiedItem.name) private var pantryItems: [UnifiedItem]
    @Query(filter: #Predicate<UnifiedItem> { $0.isGrocery }, sort: \UnifiedItem.name) private var groceryItems: [UnifiedItem]
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var foodEntries: [FoodEntry]
    @Query(sort: \NutritionDayLog.dayStart, order: .reverse) private var dayLogs: [NutritionDayLog]
    @Query(sort: \NutritionProfile.createdAt) private var profiles: [NutritionProfile]

    private var calendar: Calendar { .current }
    private var profile: NutritionProfile? { profiles.first }

    // MARK: - Greeting

    private var greeting: String {
        let hour = calendar.component(.hour, from: .now)
        switch hour {
        case 5..<12: return String(localized: "Bom dia")
        case 12..<18: return String(localized: "Boa tarde")
        default: return String(localized: "Boa noite")
        }
    }

    // MARK: - Streak (dias concluídos consecutivos terminando hoje ou ontem)

    private var streak: Int {
        let completedDays = Set(
            dayLogs
                .filter { $0.isCompleted }
                .map { calendar.startOfDay(for: $0.dayStart) }
        )
        guard !completedDays.isEmpty else { return 0 }
        var count = 0
        var cursor = calendar.startOfDay(for: .now)
        if !completedDays.contains(cursor) {
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = prev
        }
        while completedDays.contains(cursor) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    // MARK: - Dynamic middle line

    private var expiringSoonCount: Int {
        guard let limit = calendar.date(byAdding: .day, value: 3, to: .now) else { return 0 }
        return pantryItems.filter { item in
            guard let exp = item.expirationDate else { return false }
            return exp <= limit
        }.count
    }

    private var pendingNutritionDaysCount: Int {
        let today = calendar.startOfDay(for: .now)
        guard let cutoff = calendar.date(byAdding: .day, value: -60, to: today) else { return 0 }
        var count = 0
        var cursor = today
        while cursor >= cutoff {
            let state = NutritionDayLogStore.state(
                for: cursor,
                entries: foodEntries,
                logs: dayLogs,
                calendar: calendar
            )
            if state == .todayInProgress || state == .pastInProgress {
                count += 1
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    private enum MiddleStat {
        case expiring(Int)
        case pending(Int)
        case lists(pantry: Int, grocery: Int)
    }

    private var middleStat: MiddleStat {
        if expiringSoonCount > 0 {
            return .expiring(expiringSoonCount)
        }
        if pendingNutritionDaysCount > 0 {
            return .pending(pendingNutritionDaysCount)
        }
        return .lists(pantry: pantryItems.count, grocery: groceryItems.count)
    }

    // MARK: - Calorie ring

    private var caloriesConsumedToday: Int {
        let today = calendar.startOfDay(for: .now)
        return foodEntries
            .filter { calendar.isDate($0.timestamp, inSameDayAs: today) }
            .reduce(0) { $0 + $1.calories }
    }

    private var calorieGoal: Int { profile?.effectiveCalories ?? 0 }

    private var caloriesRemaining: Int {
        max(0, calorieGoal - caloriesConsumedToday)
    }

    private var calorieProgress: Double {
        guard calorieGoal > 0 else { return 0 }
        return min(1.0, Double(caloriesConsumedToday) / Double(calorieGoal))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(greeting)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if streak > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.orange)
                            Text("\(streak)")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.18), in: .capsule)
                    }
                }

                middleLine
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Spacer()

            calorieRing
        }
    }

    @ViewBuilder
    private var middleLine: some View {
        switch middleStat {
        case .expiring(let n):
            Label(
                n == 1
                    ? String(localized: "1 item vencendo")
                    : String(localized: "\(n) itens vencendo"),
                systemImage: "clock.badge.exclamationmark"
            )
        case .pending(let n):
            Label(
                n == 1
                    ? String(localized: "1 dia não concluído")
                    : String(localized: "\(n) dias não concluídos"),
                systemImage: "exclamationmark.circle"
            )
        case .lists(let pantry, let grocery):
            HStack(spacing: 8) {
                Label("\(pantry) na despensa", systemImage: "refrigerator")
                Label("\(grocery) no mercado", systemImage: "cart")
            }
        }
    }

    @ViewBuilder
    private var calorieRing: some View {
        if calorieGoal > 0 {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: calorieProgress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(caloriesRemaining)")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("kcal")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 56, height: 56)
            .accessibilityLabel(Text(String(localized: "\(caloriesRemaining) kcal restantes hoje")))
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Configurar")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }
}
