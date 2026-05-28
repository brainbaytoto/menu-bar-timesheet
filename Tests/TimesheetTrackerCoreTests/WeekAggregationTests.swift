import XCTest
@testable import TimesheetTrackerCore

final class WeekAggregationTests: XCTestCase {
    func test_weekRangeForThursdayReturnsPriorFridayThroughThursday() {
        let thursday = ymd("2026-05-14")
        let range = WeekAggregation.fridayToThursdayWindow(endingOn: thursday)
        XCTAssertEqual(range, [
            "2026-05-08", "2026-05-09", "2026-05-10", "2026-05-11",
            "2026-05-12", "2026-05-13", "2026-05-14",
        ])
    }

    func test_weekRangeWhenGivenMidWeekReportsRollsForwardToNextThursday() {
        let tuesday = ymd("2026-05-12")
        let range = WeekAggregation.fridayToThursdayWindow(endingOn: tuesday)
        XCTAssertEqual(range.last, "2026-05-14")
        XCTAssertEqual(range.count, 7)
    }

    func test_lastWeekWindowFromFridayReturnsPriorFridayToThursday() {
        let friday = ymd("2026-05-29")
        let window = WeekAggregation.lastWeekWindow(relativeTo: friday)
        XCTAssertEqual(window, [
            "2026-05-22", "2026-05-23", "2026-05-24", "2026-05-25",
            "2026-05-26", "2026-05-27", "2026-05-28",
        ])
    }

    func test_lastWeekWindowFromThursdayReturnsPriorWeekNotCurrent() {
        let thursday = ymd("2026-06-04")
        let window = WeekAggregation.lastWeekWindow(relativeTo: thursday)
        XCTAssertEqual(window.count, 7)
        XCTAssertEqual(window, [
            "2026-05-22", "2026-05-23", "2026-05-24", "2026-05-25",
            "2026-05-26", "2026-05-27", "2026-05-28",
        ])
    }

    func test_emptyWeekHasZeroTotals() {
        let summary = WeekAggregation.summarize(
            days: [],
            window: ["2026-05-08", "2026-05-09"]
        )
        XCTAssertEqual(summary.days.map { $0.totalSeconds }, [0, 0])
    }

    func test_dailyTotalSumsAllEntries() {
        let t = Date(timeIntervalSince1970: 1_715_400_000)
        let entries = [
            Entry(task: "A", start: t, stop: t.addingTimeInterval(3600)),
            Entry(task: "B", start: t.addingTimeInterval(3600), stop: t.addingTimeInterval(5400)),
        ]
        let day = DayLog(date: "2026-05-11", entries: entries)
        let summary = WeekAggregation.summarize(days: [day], window: ["2026-05-11"])
        XCTAssertEqual(summary.days[0].totalSeconds, 5400)
    }

    func test_perTaskBreakdownGroupsBySameTaskName() {
        let t = Date(timeIntervalSince1970: 1_715_400_000)
        let entries = [
            Entry(task: "A", start: t, stop: t.addingTimeInterval(600)),
            Entry(task: "B", start: t.addingTimeInterval(600), stop: t.addingTimeInterval(900)),
            Entry(task: "A", start: t.addingTimeInterval(900), stop: t.addingTimeInterval(1500)),
        ]
        let day = DayLog(date: "2026-05-11", entries: entries)
        let summary = WeekAggregation.summarize(days: [day], window: ["2026-05-11"])
        let tasks = Dictionary(uniqueKeysWithValues: summary.days[0].tasks.map { ($0.task, $0.totalSeconds) })
        XCTAssertEqual(tasks["A"], 1200)
        XCTAssertEqual(tasks["B"], 300)
    }

    private func ymd(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.date(from: s)!
    }
}
