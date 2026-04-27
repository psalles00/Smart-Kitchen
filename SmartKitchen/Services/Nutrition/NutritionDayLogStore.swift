import Foundation
import SwiftData

/// Repositório fino para `NutritionDayLog`. Centraliza concluir/cancelar/reabrir
/// e cálculo do estado de cada dia, evitando lógica duplicada entre views.
enum NutritionDayLogStore {

    // MARK: - Lookup

    /// Busca o `NutritionDayLog` correspondente a um dia (procura no array já carregado).
    static func log(
        for date: Date,
        in logs: [NutritionDayLog],
        calendar: Calendar = .current
    ) -> NutritionDayLog? {
        let key = NutritionDayLog.key(for: date, calendar: calendar)
        return logs.first { calendar.isDate($0.dayStart, inSameDayAs: key) }
    }

    static func hasEntries(
        on date: Date,
        in entries: [FoodEntry],
        calendar: Calendar = .current
    ) -> Bool {
        entries.contains { calendar.isDate($0.timestamp, inSameDayAs: date) }
    }

    // MARK: - State derivation

    static func state(
        for date: Date,
        entries: [FoodEntry],
        logs: [NutritionDayLog],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> NutritionDayState {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let log = log(for: day, in: logs, calendar: calendar)
        let hasEntries = hasEntries(on: day, in: entries, calendar: calendar)

        if let log {
            if log.isCanceled { return .canceled }
            if log.isCompleted { return .completed }
        }

        if day > today { return .future }

        if calendar.isDate(day, inSameDayAs: today) {
            return hasEntries ? .todayInProgress : .todayEmpty
        }

        // Passado, sem log de conclusão/cancelamento.
        return hasEntries ? .pastInProgress : .pastEmpty
    }

    // MARK: - Mutations

    /// Marca um dia como concluído (idempotente). Cria o `NutritionDayLog` se necessário.
    @MainActor
    static func complete(
        date: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) {
        let day = calendar.startOfDay(for: date)
        let existing = fetchLog(for: day, in: context, calendar: calendar)
        let now = Date()
        if let existing {
            existing.completedAt = now
            existing.canceledAt = nil
        } else {
            let log = NutritionDayLog(dayStart: day, completedAt: now)
            context.insert(log)
        }
        try? context.save()
    }

    /// Marca um dia como cancelado/vazio (idempotente).
    @MainActor
    static func cancel(
        date: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) {
        let day = calendar.startOfDay(for: date)
        let existing = fetchLog(for: day, in: context, calendar: calendar)
        let now = Date()
        if let existing {
            existing.canceledAt = now
            existing.completedAt = nil
        } else {
            let log = NutritionDayLog(dayStart: day, canceledAt: now)
            context.insert(log)
        }
        try? context.save()
    }

    /// Reabre um dia previamente concluído ou cancelado (limpa as datas).
    @MainActor
    static func reopen(
        date: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) {
        let day = calendar.startOfDay(for: date)
        guard let existing = fetchLog(for: day, in: context, calendar: calendar) else { return }
        existing.completedAt = nil
        existing.canceledAt = nil
        try? context.save()
    }

    // MARK: - Helpers

    @MainActor
    private static func fetchLog(
        for day: Date,
        in context: ModelContext,
        calendar: Calendar
    ) -> NutritionDayLog? {
        // Janela [dayStart, dayStart+1d) — comparação por timestamps é robusta para CloudKit.
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let predicate = #Predicate<NutritionDayLog> { log in
            log.dayStart >= day && log.dayStart < nextDay
        }
        let descriptor = FetchDescriptor<NutritionDayLog>(predicate: predicate)
        return (try? context.fetch(descriptor))?.first
    }
}
