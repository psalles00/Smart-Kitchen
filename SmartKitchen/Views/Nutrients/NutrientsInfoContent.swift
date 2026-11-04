import SwiftUI

/// Same inline facts and typography as the Home description; tapping opens progress.
struct NutrientsInfoContent: View {
    var profile: NutritionProfile? = nil
    var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    var selectedDayState: NutritionDayState = .todayEmpty
    var caloriesConsumed: Int = 0
    var entryCount: Int = 0
    var onTapScore: () -> Void = {}

    private var calendar: Calendar { .current }
    private var goal: Int { profile?.effectiveCalories ?? 0 }
    var body: some View {
        Button(action: onTapScore) {
            descriptionText
                .modifier(PageHeaderDescriptionStyle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(profile?.hasCompletedOnboarding != true)
        .accessibilityIdentifier("savoria.nutrition.summary")
    }

    private var descriptionText: Text {
        let date = Text(dateLine + " · ").foregroundColor(.white.opacity(0.55))
        guard profile?.hasCompletedOnboarding == true else {
            return date + Text(String(localized: "Configure seu perfil para ver suas metas.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale))
                .foregroundColor(.white)
        }
        let count = entryCount == 1 ? String(localized: "1 registro", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale) : String(localized: "\(entryCount) registros", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
        return date
            + Text(Image(systemName: "chart.bar.doc.horizontal")).foregroundColor(.white)
            + Text(" " + count).fontWeight(.bold).foregroundColor(.white)
            + Text(" · " + statusLine + " · ").foregroundColor(.white.opacity(0.55))
            + Text(Image(systemName: "flame")).foregroundColor(.white)
            + Text(" " + String(localized: "\(caloriesConsumed) de \(goal) kcal", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale))
                .fontWeight(.bold).foregroundColor(.white)
    }

    // MARK: - Composição de texto

    private var dateLine: String {
        let relative = relativeLabel(for: selectedDate)
        let full = fullDateString(for: selectedDate)
        return String(localized: "\(relative) · \(full)", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
    }

    private var statusLine: String {
        switch selectedDayState {
        case .future:           return String(localized: "Dia futuro", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
        case .todayEmpty:       return String(localized: "Sem registros ainda", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
        case .todayInProgress:  return String(localized: "Registro em andamento", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
        case .completed:        return String(localized: "Dia concluído", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
        case .pastInProgress:   return String(localized: "Dia iniciado e não concluído", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
        case .pastEmpty:        return String(localized: "Sem registros neste dia", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
        case .canceled:         return String(localized: "Dia marcado como vazio", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
        }
    }

    private func relativeLabel(for date: Date) -> String {
        if calendar.isDateInToday(date) { return String(localized: "Hoje", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale) }
        if calendar.isDateInYesterday(date) { return String(localized: "Ontem", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale) }
        if calendar.isDateInTomorrow(date) { return String(localized: "Amanhã", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale) }
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.current().formattingLocale
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).localizedCapitalized
    }

    private func fullDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.current().formattingLocale
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return formatter.string(from: date)
    }
}
