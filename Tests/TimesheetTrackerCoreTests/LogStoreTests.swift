import XCTest
@testable import TimesheetTrackerCore

final class LogStoreTests: XCTestCase {
    var tempDir: URL!
    var store: LogStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ts-log-tests-\(UUID().uuidString)")
        store = LogStore(rootDirectory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_readEmptyDayReturnsEmptyDayLog() throws {
        let day = try store.readDay("2026-05-11")
        XCTAssertEqual(day.date, "2026-05-11")
        XCTAssertEqual(day.entries, [])
    }

    func test_appendEntryThenReadReturnsThatEntry() throws {
        let start = Date(timeIntervalSince1970: 1_715_400_000)
        let entry = Entry(task: "Code", start: start, stop: start.addingTimeInterval(60))
        try store.append(entry, toDay: "2026-05-11")
        let day = try store.readDay("2026-05-11")
        XCTAssertEqual(day.entries, [entry])
    }

    func test_appendTwoEntriesReturnsBothInOrder() throws {
        let t0 = Date(timeIntervalSince1970: 1_715_400_000)
        let a = Entry(task: "A", start: t0, stop: t0.addingTimeInterval(60))
        let b = Entry(task: "B", start: t0.addingTimeInterval(60), stop: t0.addingTimeInterval(120))
        try store.append(a, toDay: "2026-05-11")
        try store.append(b, toDay: "2026-05-11")
        let day = try store.readDay("2026-05-11")
        XCTAssertEqual(day.entries, [a, b])
    }

    func test_entriesGoToCorrectDayFile() throws {
        let t0 = Date(timeIntervalSince1970: 1_715_400_000)
        let a = Entry(task: "A", start: t0, stop: t0.addingTimeInterval(60))
        let b = Entry(task: "B", start: t0.addingTimeInterval(86_400), stop: t0.addingTimeInterval(86_460))
        try store.append(a, toDay: "2026-05-11")
        try store.append(b, toDay: "2026-05-12")
        XCTAssertEqual(try store.readDay("2026-05-11").entries, [a])
        XCTAssertEqual(try store.readDay("2026-05-12").entries, [b])
    }

    func test_directoryCreatedLazily() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.path))
        let t0 = Date(timeIntervalSince1970: 1_715_400_000)
        try store.append(Entry(task: "A", start: t0, stop: t0.addingTimeInterval(60)), toDay: "2026-05-11")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("logs").path))
    }

    func test_corruptJSONThrowsReadableError() throws {
        let logsDir = tempDir.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        try "not json".data(using: .utf8)!.write(to: logsDir.appendingPathComponent("2026-05-11.json"))
        XCTAssertThrowsError(try store.readDay("2026-05-11"))
    }
}
