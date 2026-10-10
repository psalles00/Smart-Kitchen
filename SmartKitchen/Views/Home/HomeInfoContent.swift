import SwiftUI
import SwiftData

struct HomeInfoContent: View {
    private let snapshot: HomeInfoSnapshot?

    init(snapshot: HomeInfoSnapshot? = nil) {
        self.snapshot = snapshot
    }

    var body: some View {
        if let snapshot {
            HomeInfoContentStatic(snapshot: snapshot)
        } else {
            HomeInfoContentLive()
        }
    }
}

private enum HomeInfoLayout {
    #if os(iOS)
    static let height = ExpandedPageHeaderMetrics.iosHomeInfoHeight
    static let topInset: CGFloat = 0
    static let bottomInset: CGFloat = 0
    static let lineLimit = 3
    #else
    static let height: CGFloat = 47
    static let topInset: CGFloat = -8
    static let bottomInset: CGFloat = -3
    static let lineLimit = 2
    #endif
}

private struct HomeInfoContentLive: View {
    @Query(filter: #Predicate<UnifiedItem> { $0.isPantry }, sort: \UnifiedItem.name) private var pantryItems: [UnifiedItem]
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var foodEntries: [FoodEntry]
    @Query(sort: \NutritionDayLog.dayStart, order: .reverse) private var dayLogs: [NutritionDayLog]
    @Query(sort: \NutritionProfile.createdAt) private var profiles: [NutritionProfile]
    @Query private var settingsArray: [AppSettings]

    @State private var snapshot = HomeInfoSnapshot()
    @State private var didRunInitialRefresh = false
    @State private var refreshWorkItem: DispatchWorkItem?

    private var calendar: Calendar { .current }
    private let statusTextSize: CGFloat = 14.5

    private var expiringSoonCount: Int {
        snapshot.expiringSoonCount
    }

    private var pendingNutritionDaysCount: Int {
        snapshot.pendingNutritionDaysCount
    }

    private var caloriesConsumedToday: Int {
        snapshot.caloriesConsumedToday
    }

    private var calorieGoal: Int { snapshot.calorieGoal }

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
        case 0...3: 15.2
        case 4: 13.8
        case 5: 12.4
        default: 11
        }
    }

    private var calorieValueFrameWidth: CGFloat {
        switch calorieValueText.count {
        case 0...3: 27
        case 4: 31
        case 5: 34
        default: 36
        }
    }

    var body: some View {
        Group {
            #if os(iOS)
            statusPhrase
            #else
            HStack(alignment: .center, spacing: 12) {
                statusPhrase.layoutPriority(1)
                Spacer()
                calorieRing.padding(.top, -6).padding(.bottom, 6)
            }
            #endif
        }
        .padding(.bottom, HomeInfoLayout.bottomInset)
        .frame(height: HomeInfoLayout.height)
        .onAppear {
            if !didRunInitialRefresh {
                didRunInitialRefresh = true
                refreshSnapshot()
            }
        }
        .onChange(of: pantryItems) { _, _ in
            scheduleRefresh()
        }
        .onChange(of: foodEntries) { _, _ in
            scheduleRefresh()
        }
        .onChange(of: dayLogs) { _, _ in
            scheduleRefresh()
        }
        .onChange(of: profiles) { _, _ in
            scheduleRefresh()
        }
        .onChange(of: settingsArray) { _, _ in
            scheduleRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionDayLogChanged)) { _ in
            scheduleRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeDataShouldRefresh)) { _ in
            scheduleRefresh()
        }
    }

    private var statusPhrase: some View {
        Group {
            if statusFacts.isEmpty {
                readyStatusPhrase
            } else {
                statusPhraseText
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .lineLimit(HomeInfoLayout.lineLimit)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, HomeInfoLayout.topInset)
    }

    private var readyStatusPhrase: some View {
        readyStatusText
            .font(.system(size: statusTextSize, weight: .semibold, design: .rounded))
        .lineLimit(HomeInfoLayout.lineLimit)
        .minimumScaleFactor(0.82)
        .allowsTightening(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var readyStatusText: Text {
        Text(greetingText + " ")
            .foregroundColor(.white.opacity(0.55))
        + Text(Image(systemName: "checkmark.circle"))
            .foregroundColor(.white)
        + Text(" ")
        + Text(String(localized: "Tudo certo"))
            .fontWeight(.bold)
            .foregroundColor(.white)
        + Text(" " + String(localized: "na sua cozinha!"))
            .foregroundColor(.white.opacity(0.55))
    }

    private var statusPhraseText: Text {
        statusFacts.enumerated().reduce(
            Text(greetingText + " " + String(localized: "Você possui") + " ")
                .foregroundColor(.white.opacity(0.55))
        ) { partial, indexedFact in
            let prefix: Text = indexedFact.offset == 0
                ? Text("")
                : Text(" " + String(localized: "e") + " ")
                    .font(.system(size: statusTextSize, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))

            let fact = indexedFact.element
            return partial
                + prefix
                + Text(Image(systemName: fact.icon))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                + Text(" ")
                + Text(fact.text)
                    .font(.system(size: statusTextSize, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
        }
    }

    private func refreshSnapshot() {
        let today = calendar.startOfDay(for: .now)
        let pendingCount: Int = {
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
        }()

        let expiringCount: Int = {
            let leadDays = settingsArray.first?.expiringItemsLeadDays ?? 30
            guard let limit = calendar.date(byAdding: .day, value: leadDays, to: today) else { return 0 }
            return pantryItems.filter { item in
                guard let exp = item.expirationDate else { return false }
                return calendar.startOfDay(for: exp) <= limit
            }.count
        }()

        let caloriesToday = foodEntries
            .filter { calendar.isDate($0.timestamp, inSameDayAs: today) }
            .reduce(0) { $0 + $1.calories }

        snapshot = HomeInfoSnapshot(
            expiringSoonCount: expiringCount,
            pendingNutritionDaysCount: pendingCount,
            caloriesConsumedToday: caloriesToday,
            calorieGoal: profiles.first?.effectiveCalories ?? 0
        )
        refreshWorkItem = nil
    }

    private func scheduleRefresh() {
        refreshWorkItem?.cancel()
        let work = DispatchWorkItem {
            refreshSnapshot()
        }
        refreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private var statusPhraseLines: [KitchenStatusLine] {
        let facts = statusFacts
        let firstLineTokens: [KitchenStatusToken] = facts.isEmpty
            ? [.connector(greetingText)]
            : [
                .connector(greetingText),
                .connector(String(localized: "Você possui"))
            ]
        var secondLineTokens: [KitchenStatusToken] = []

        let visibleFacts = facts.isEmpty ? [kitchenReadyFact] : Array(facts.prefix(3))

        for (index, fact) in visibleFacts.enumerated() {
            if index > 0 {
                secondLineTokens.append(.connector(String(localized: "e")))
            }
            secondLineTokens.append(.fact(fact))
        }

        return [
            KitchenStatusLine(id: 0, tokens: firstLineTokens),
            KitchenStatusLine(id: 1, tokens: secondLineTokens)
        ]
    }

    private var statusFacts: [KitchenStatusFact] {
        var facts: [KitchenStatusFact] = []

        if expiringSoonCount > 0 {
            facts.append(
                KitchenStatusFact(
                    icon: "clock.badge.exclamationmark",
                    text: expiringSoonCount == 1
                        ? String(localized: "1 item expirando")
                        : String(localized: "\(expiringSoonCount) itens expirando")
                )
            )
        }

        if pendingNutritionDaysCount > 0 {
            facts.append(
                KitchenStatusFact(
                    icon: "chart.bar.doc.horizontal",
                    text: pendingNutritionDaysCount == 1
                        ? String(localized: "1 dia incompleto")
                        : String(localized: "\(pendingNutritionDaysCount) dias incompletos")
                )
            )
        }

        #if os(iOS)
        if calorieGoal > 0 {
            facts.append(KitchenStatusFact(
                icon: "flame",
                text: String(localized: "\(caloriesRemaining) kcal restantes hoje")))
        }
        #endif

        return facts
    }

    private var kitchenReadyFact: KitchenStatusFact {
        KitchenStatusFact(
            icon: "checkmark.circle",
            text: String(localized: "Tudo certo na sua cozinha!")
        )
    }

    private var greetingText: String {
        let hour = calendar.component(.hour, from: .now)
        switch hour {
        case 5..<12:
            return String(localized: "Bom dia.")
        case 12..<18:
            return String(localized: "Boa tarde.")
        default:
            return String(localized: "Boa noite.")
        }
    }

    @ViewBuilder
    private func statusPhraseTokenView(_ token: KitchenStatusToken) -> some View {
        switch token {
        case .connector(let text):
            Text(text)
                .font(.system(size: statusTextSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        case .fact(let fact):
            HStack(spacing: 3) {
                Image(systemName: fact.icon)
                    .font(.system(size: 14, weight: .bold))
                Text(fact.text)
                    .font(.system(size: statusTextSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var calorieRing: some View {
        if calorieGoal > 0 {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: calorieProgress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(calorieValueText)
                        .font(.system(size: calorieValueFontSize, weight: .bold, design: .rounded))
                        .tracking(-0.7)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .allowsTightening(true)
                        .frame(maxWidth: calorieValueFrameWidth)
                    Text("kcal")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 46, height: 46)
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

private struct HomeInfoContentStatic: View {
    let snapshot: HomeInfoSnapshot

    private var calendar: Calendar { .current }
    private let statusTextSize: CGFloat = 14.5

    private var expiringSoonCount: Int { snapshot.expiringSoonCount }
    private var pendingNutritionDaysCount: Int { snapshot.pendingNutritionDaysCount }
    private var caloriesConsumedToday: Int { snapshot.caloriesConsumedToday }
    private var calorieGoal: Int { snapshot.calorieGoal }

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
        case 0...3: 15.2
        case 4: 13.8
        case 5: 12.4
        default: 11
        }
    }

    private var calorieValueFrameWidth: CGFloat {
        switch calorieValueText.count {
        case 0...3: 27
        case 4: 31
        case 5: 34
        default: 36
        }
    }

    var body: some View {
        Group {
            #if os(iOS)
            statusPhrase
            #else
            HStack(alignment: .center, spacing: 12) {
                statusPhrase.layoutPriority(1)
                Spacer()
                calorieRing.padding(.top, -6).padding(.bottom, 6)
            }
            #endif
        }
        .padding(.bottom, HomeInfoLayout.bottomInset)
        .frame(height: HomeInfoLayout.height)
    }

    private var statusPhrase: some View {
        Group {
            if statusFacts.isEmpty {
                readyStatusPhrase
            } else {
                statusPhraseText
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .lineLimit(HomeInfoLayout.lineLimit)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, HomeInfoLayout.topInset)
    }

    private var readyStatusPhrase: some View {
        readyStatusText
            .font(.system(size: statusTextSize, weight: .semibold, design: .rounded))
        .lineLimit(HomeInfoLayout.lineLimit)
        .minimumScaleFactor(0.82)
        .allowsTightening(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var readyStatusText: Text {
        Text(greetingText + " ")
            .foregroundColor(.white.opacity(0.55))
        + Text(Image(systemName: "checkmark.circle"))
            .foregroundColor(.white)
        + Text(" ")
        + Text(String(localized: "Tudo certo"))
            .fontWeight(.bold)
            .foregroundColor(.white)
        + Text(" " + String(localized: "na sua cozinha!"))
            .foregroundColor(.white.opacity(0.55))
    }

    private var statusPhraseText: Text {
        statusFacts.enumerated().reduce(
            Text(greetingText + " " + String(localized: "Você possui") + " ")
                .foregroundColor(.white.opacity(0.55))
        ) { partial, indexedFact in
            let prefix: Text = indexedFact.offset == 0
                ? Text("")
                : Text(" " + String(localized: "e") + " ")
                    .font(.system(size: statusTextSize, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))

            let fact = indexedFact.element
            return partial
                + prefix
                + Text(Image(systemName: fact.icon))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                + Text(" ")
                + Text(fact.text)
                    .font(.system(size: statusTextSize, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
        }
    }

    private var statusFacts: [KitchenStatusFact] {
        var facts: [KitchenStatusFact] = []

        if expiringSoonCount > 0 {
            facts.append(
                KitchenStatusFact(
                    icon: "clock.badge.exclamationmark",
                    text: expiringSoonCount == 1
                        ? String(localized: "1 item expirando")
                        : String(localized: "\(expiringSoonCount) itens expirando")
                )
            )
        }

        if pendingNutritionDaysCount > 0 {
            facts.append(
                KitchenStatusFact(
                    icon: "chart.bar.doc.horizontal",
                    text: pendingNutritionDaysCount == 1
                        ? String(localized: "1 dia incompleto")
                        : String(localized: "\(pendingNutritionDaysCount) dias incompletos")
                )
            )
        }

        #if os(iOS)
        if calorieGoal > 0 {
            facts.append(KitchenStatusFact(
                icon: "flame",
                text: String(localized: "\(caloriesRemaining) kcal restantes hoje")))
        }
        #endif

        return facts
    }

    private var greetingText: String {
        let hour = calendar.component(.hour, from: .now)
        switch hour {
        case 5..<12:
            return String(localized: "Bom dia.")
        case 12..<18:
            return String(localized: "Boa tarde.")
        default:
            return String(localized: "Boa noite.")
        }
    }

    @ViewBuilder
    private var calorieRing: some View {
        if calorieGoal > 0 {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: calorieProgress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(calorieValueText)
                        .font(.system(size: calorieValueFontSize, weight: .bold, design: .rounded))
                        .tracking(-0.7)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .allowsTightening(true)
                        .frame(maxWidth: calorieValueFrameWidth)
                    Text("kcal")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 46, height: 46)
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

struct HomeInfoSnapshot: Equatable {
    var expiringSoonCount: Int = 0
    var pendingNutritionDaysCount: Int = 0
    var caloriesConsumedToday: Int = 0
    var calorieGoal: Int = 0
}

private struct KitchenStatusFact {
    let icon: String
    let text: String
}

private struct KitchenStatusLine: Identifiable {
    let id: Int
    let tokens: [KitchenStatusToken]
}

private enum KitchenStatusToken: Identifiable {
    case connector(String)
    case fact(KitchenStatusFact)

    var id: String {
        switch self {
        case .connector(let text):
            return "connector-\(text)"
        case .fact(let fact):
            return "fact-\(fact.icon)-\(fact.text)"
        }
    }
}
