import SwiftUI
import SwiftData

struct HomeInfoContent: View {
    @Query(filter: #Predicate<UnifiedItem> { $0.isPantry }, sort: \UnifiedItem.name) private var pantryItems: [UnifiedItem]
    @Query(filter: #Predicate<UnifiedItem> { $0.isGrocery }, sort: \UnifiedItem.name) private var groceryItems: [UnifiedItem]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var foodEntries: [FoodEntry]
    @Query(sort: \NutritionDayLog.dayStart, order: .reverse) private var dayLogs: [NutritionDayLog]
    @Query(sort: \NutritionProfile.createdAt) private var profiles: [NutritionProfile]

    private var calendar: Calendar { .current }
    private var profile: NutritionProfile? { profiles.first }

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

    private var statusLine: String {
        let fragments = [expiringStatusText, pendingStatusText].compactMap { $0 }
        return fragments.isEmpty
            ? String(localized: "Tudo certo na sua cozinha!")
            : fragments.joined(separator: " · ")
    }

    private var expiringStatusText: String? {
        guard expiringSoonCount > 0 else { return nil }
        return expiringSoonCount == 1
            ? String(localized: "1 item vencendo")
            : String(localized: "\(expiringSoonCount) itens vencendo")
    }

    private var pendingStatusText: String? {
        guard pendingNutritionDaysCount > 0 else { return nil }
        return pendingNutritionDaysCount == 1
            ? String(localized: "1 dia não concluído")
            : String(localized: "\(pendingNutritionDaysCount) dias não concluídos")
    }

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

    private var calorieValueText: String {
        String(caloriesRemaining)
    }

    private var calorieValueFontSize: CGFloat {
        switch calorieValueText.count {
        case 0...3: 17
        case 4: 15
        case 5: 13.5
        default: 12
        }
    }

    private var calorieValueFrameWidth: CGFloat {
        switch calorieValueText.count {
        case 0...3: 29
        case 4: 33
        case 5: 36
        default: 37
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(statusLine)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .layoutPriority(1)

                compactCountersLine
            }
            .layoutPriority(1)

            Spacer()

            calorieRing
        }
    }

    private var compactCountersLine: some View {
        HStack(spacing: 10) {
            compactCounter(String(localized: "\(pantryItems.count) desp."))
            compactCounter(String(localized: "\(groceryItems.count) merc."))
            compactCounter(String(localized: "\(recipes.count) rec."))
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(.white.opacity(0.84))
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .allowsTightening(true)
    }

    private func compactCounter(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .monospacedDigit()
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
                    Text(calorieValueText)
                        .font(.system(size: calorieValueFontSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .allowsTightening(true)
                        .frame(maxWidth: calorieValueFrameWidth)
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
