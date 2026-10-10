import Foundation
import XCTest
@testable import Savoria

@MainActor
final class DayHistoryIndexTests: XCTestCase {
    private struct Entry { let date: Date; let calories: Int }
    private struct Log { let date: Date; let state: String }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }
    private func index(_ entries: [Entry], _ logs: [Log] = []) -> DayHistoryIndex<Entry, Log> {
        DayHistoryIndex(entries: entries, logs: logs, calendar: calendar,
                        timestamp: { $0.date }, calories: { $0.calories }, logDate: { $0.date })
    }

    func testEmptyHistoryAndFutureDayRemainEmpty() {
        let value = index([])
        XCTAssertEqual(value.calories(on: .distantFuture), 0)
        XCTAssertTrue(value.entries(on: .distantFuture).isEmpty)
        XCTAssertNil(value.log(on: .distantFuture))
    }

    func testCivilDayAcrossDSTPreservesOrderAndExcludesNextDay() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let next = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        XCTAssertEqual(next.timeIntervalSince(day), 90_000)
        let entries = [Entry(date: next.addingTimeInterval(-1), calories: 200),
                       Entry(date: day, calories: 100),
                       Entry(date: next, calories: 500)]
        let value = index(entries)
        XCTAssertEqual(value.entries(on: day).map(\.calories), [200, 100])
        XCTAssertEqual(value.calories(on: day), 300)
        XCTAssertEqual(value.calories(on: next), 500)
    }

    func testFirstDuplicateLogWinsAsInExistingStoreLookup() {
        let day = calendar.startOfDay(for: .now)
        let value = index([], [Log(date: day.addingTimeInterval(60), state: "canceled"),
                              Log(date: day, state: "completed")])
        XCTAssertEqual(value.log(on: day)?.state, "canceled")
    }

    func testRebuildingAfterEditOrDeletionDoesNotRetainStaleTotals() {
        let day = calendar.startOfDay(for: .now)
        XCTAssertEqual(index([Entry(date: day, calories: 100)]).calories(on: day), 100)
        XCTAssertEqual(index([Entry(date: day, calories: 250)]).calories(on: day), 250)
        XCTAssertEqual(index([]).calories(on: day), 0)
    }

    func testDisabledDiagnosticsDoNotEvaluateMetadataButExecuteMeasuredWorkOnce() throws {
        guard !PerformanceLogger.isEnabled else { throw XCTSkip("Diagnostic flags explicitly enabled.") }
        var metadataEvaluations = 0
        func metadata() -> String { metadataEvaluations += 1; return "synthetic" }
        PerformanceLogger.event(.recipes, "test", metadata: metadata())
        var executions = 0
        let result = PerformanceLogger.measure(.recipes, "test", metadata: metadata()) {
            executions += 1
            return 42
        }
        XCTAssertEqual(result, 42)
        XCTAssertEqual(executions, 1)
        XCTAssertEqual(metadataEvaluations, 0)
    }
}
