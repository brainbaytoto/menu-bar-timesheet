import XCTest
@testable import TimesheetTrackerCore

final class ModelsTests: XCTestCase {
    func test_entryRoundTripsThroughJSON() throws {
        let start = Date(timeIntervalSince1970: 1_715_400_000)
        let stop = start.addingTimeInterval(3600)
        let entry = Entry(task: "Code review", start: start, stop: stop)
        let data = try JSONEncoder.timesheet.encode(entry)
        let decoded = try JSONDecoder.timesheet.decode(Entry.self, from: data)
        XCTAssertEqual(decoded, entry)
    }

    func test_dayLogRoundTripsWithMultipleEntries() throws {
        let day = DayLog(date: "2026-05-11", entries: [
            Entry(task: "A", start: Date(timeIntervalSince1970: 1), stop: Date(timeIntervalSince1970: 60)),
            Entry(task: "B", start: Date(timeIntervalSince1970: 60), stop: Date(timeIntervalSince1970: 120)),
        ])
        let data = try JSONEncoder.timesheet.encode(day)
        let decoded = try JSONDecoder.timesheet.decode(DayLog.self, from: data)
        XCTAssertEqual(decoded, day)
    }

    func test_jsonUsesISO8601WithTimezoneOffsets() throws {
        let entry = Entry(task: "X", start: Date(timeIntervalSince1970: 1_715_400_000),
                          stop: Date(timeIntervalSince1970: 1_715_403_600))
        let data = try JSONEncoder.timesheet.encode(entry)
        let json = String(data: data, encoding: .utf8) ?? ""
        let hasZ = json.contains("Z\"")
        let hasOffset = json.range(of: #"[+\-]\d{2}:\d{2}\""#, options: .regularExpression) != nil
        XCTAssertTrue(hasZ || hasOffset, "Expected ISO 8601 timezone designator in: \(json)")
    }

    func test_currentSessionRoundTrips() throws {
        let session = CurrentSession(task: "Code review", startedAt: Date(timeIntervalSince1970: 1_715_400_000))
        let data = try JSONEncoder.timesheet.encode(session)
        let decoded = try JSONDecoder.timesheet.decode(CurrentSession.self, from: data)
        XCTAssertEqual(decoded, session)
    }
}
