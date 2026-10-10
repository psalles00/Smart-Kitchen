import Foundation

/// Runtime-only calendar index. No persistence or migration.
struct DayHistoryIndex<Entry, Log> {
    private let calendar: Calendar
    private let entriesByDay: [Date: [Entry]]
    private let caloriesByDay: [Date: Int]
    private let logsByDay: [Date: Log]

    init(entries: [Entry], logs: [Log], calendar: Calendar,
         timestamp: (Entry) -> Date, calories: (Entry) -> Int, logDate: (Log) -> Date) {
        self.calendar = calendar
        var grouped: [Date: [Entry]] = [:]
        var totals: [Date: Int] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: timestamp(entry))
            grouped[day, default: []].append(entry)
            totals[day, default: 0] += calories(entry)
        }
        var firstLogs: [Date: Log] = [:]
        for log in logs {
            let day = calendar.startOfDay(for: logDate(log))
            if firstLogs[day] == nil { firstLogs[day] = log }
        }
        entriesByDay = grouped
        caloriesByDay = totals
        logsByDay = firstLogs
    }

    func entries(on date: Date) -> [Entry] { entriesByDay[calendar.startOfDay(for: date)] ?? [] }
    func calories(on date: Date) -> Int { caloriesByDay[calendar.startOfDay(for: date)] ?? 0 }
    func log(on date: Date) -> Log? { logsByDay[calendar.startOfDay(for: date)] }
}
