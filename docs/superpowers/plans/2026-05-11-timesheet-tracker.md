# Timesheet Time Tracker — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app (`Timesheet Tracker`) that records start/stop timestamps per task to per-day JSON files and shows a 7-day summary for daily-total transcription into Xero Me.

**Architecture:** Swift Package with two library/exec targets (`TimesheetTrackerCore` library — pure model + storage + tracking logic, `TimesheetTracker` executable — SwiftUI `MenuBarExtra` UI). All business logic is tested under `swift test` with a fake clock and a temp-directory store. The executable is bundled into a `.app` via a shell script that copies the binary and `Info.plist` (with `LSUIElement = true`) into the bundle layout.

**Tech Stack:** Swift 5.9, SwiftUI `MenuBarExtra` (macOS 13+), `Foundation` JSON / `UserDefaults`, XCTest, Swift Package Manager.

---

## File structure

```
TimesheetTracker/
├── Package.swift
├── Sources/
│   ├── TimesheetTrackerCore/                — testable, no SwiftUI
│   │   ├── Models.swift                     — Entry, DayLog, CurrentSession, Preferences
│   │   ├── Clock.swift                      — protocol + system + fake impl
│   │   ├── LogStore.swift                   — per-day JSON read/write
│   │   ├── SessionSidecar.swift             — current-session.json read/write
│   │   ├── PreferencesStore.swift           — UserDefaults wrapper
│   │   ├── WeekAggregation.swift            — pure weekly summary functions
│   │   └── Tracker.swift                    — @Observable state machine + auto-stop + midnight split
│   └── TimesheetTracker/                    — SwiftUI app
│       ├── TimesheetTrackerApp.swift        — @main, MenuBarExtra scene, AppDelegate
│       ├── PopoverView.swift                — main popover
│       ├── WeekView.swift                   — 7-day expansion
│       └── PreferencesView.swift            — settings window
├── Tests/
│   └── TimesheetTrackerCoreTests/
│       ├── ModelsTests.swift
│       ├── LogStoreTests.swift
│       ├── SessionSidecarTests.swift
│       ├── WeekAggregationTests.swift
│       └── TrackerTests.swift
├── scripts/
│   ├── build-app.sh                         — assembles .app bundle from swift build output
│   └── Info.plist                           — template with LSUIElement=true
├── docs/superpowers/{specs,plans}/...       — already exists
└── .gitignore                               — already exists
```

---

## Task 1: Bootstrap Swift package

**Files:**
- Create: `Package.swift`
- Create: `Sources/TimesheetTrackerCore/.gitkeep`
- Create: `Sources/TimesheetTracker/.gitkeep`
- Create: `Tests/TimesheetTrackerCoreTests/.gitkeep`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TimesheetTracker",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "TimesheetTrackerCore",
            path: "Sources/TimesheetTrackerCore"
        ),
        .executableTarget(
            name: "TimesheetTracker",
            dependencies: ["TimesheetTrackerCore"],
            path: "Sources/TimesheetTracker"
        ),
        .testTarget(
            name: "TimesheetTrackerCoreTests",
            dependencies: ["TimesheetTrackerCore"],
            path: "Tests/TimesheetTrackerCoreTests"
        ),
    ]
)
```

- [ ] **Step 2: Verify package resolves**

Run: `swift package resolve`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: scaffold Swift package with core/app/test targets"
```

---

## Task 2: Models — Entry, DayLog, CurrentSession

**Files:**
- Create: `Sources/TimesheetTrackerCore/Models.swift`
- Create: `Tests/TimesheetTrackerCoreTests/ModelsTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/TimesheetTrackerCoreTests/ModelsTests.swift
import XCTest
@testable import TimesheetTrackerCore

final class ModelsTests: XCTestCase {
    func test_entryRoundTripsThroughJSON() throws {
        let start = Date(timeIntervalSince1970: 1_715_400_000) // arbitrary
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
        // Must contain a timezone designator: 'Z' or '+HH:MM' or '-HH:MM'
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
```

- [ ] **Step 2: Run tests — expect FAIL (no types defined)**

Run: `swift test --filter ModelsTests`
Expected: build failure — types `Entry`, `DayLog`, `CurrentSession`, `JSONEncoder.timesheet`, `JSONDecoder.timesheet` undefined.

- [ ] **Step 3: Implement `Models.swift`**

```swift
// Sources/TimesheetTrackerCore/Models.swift
import Foundation

public struct Entry: Codable, Equatable, Hashable, Identifiable {
    public let task: String
    public let start: Date
    public let stop: Date
    public var id: String { "\(task)|\(start.timeIntervalSince1970)|\(stop.timeIntervalSince1970)" }

    public init(task: String, start: Date, stop: Date) {
        self.task = task
        self.start = start
        self.stop = stop
    }

    public var duration: TimeInterval { stop.timeIntervalSince(start) }
}

public struct DayLog: Codable, Equatable {
    /// Local-date string of the entries, format `YYYY-MM-DD`.
    public let date: String
    public var entries: [Entry]

    public init(date: String, entries: [Entry]) {
        self.date = date
        self.entries = entries
    }
}

public struct CurrentSession: Codable, Equatable {
    public let task: String
    public let startedAt: Date

    public init(task: String, startedAt: Date) {
        self.task = task
        self.startedAt = startedAt
    }
}

public extension JSONEncoder {
    static let timesheet: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601WithFractionalAndOffset
        return e
    }()
}

public extension JSONDecoder {
    static let timesheet: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601WithFractionalAndOffset
        return d
    }()
}

// Custom ISO 8601 formatter that includes the local timezone offset (or Z for UTC)
// and fractional seconds. Round-trips losslessly.
private let timesheetISOFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private extension JSONEncoder.DateEncodingStrategy {
    static var iso8601WithFractionalAndOffset: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timesheetISOFormatter.string(from: date))
        }
    }
}

private extension JSONDecoder.DateDecodingStrategy {
    static var iso8601WithFractionalAndOffset: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let d = timesheetISOFormatter.date(from: str) { return d }
            // Fallback: no fractional seconds.
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let d = fallback.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(str)")
        }
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `swift test --filter ModelsTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TimesheetTrackerCore/Models.swift Tests/TimesheetTrackerCoreTests/ModelsTests.swift
git commit -m "feat(core): Entry, DayLog, CurrentSession with ISO 8601 codable"
```

---

## Task 3: Clock abstraction

**Files:**
- Create: `Sources/TimesheetTrackerCore/Clock.swift`

- [ ] **Step 1: Implement (trivial — tests only via Tracker)**

```swift
// Sources/TimesheetTrackerCore/Clock.swift
import Foundation

public protocol Clock: AnyObject {
    func now() -> Date
}

public final class SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

/// Test clock. Set `currentTime` to whatever you want; `now()` returns it.
public final class FakeClock: Clock {
    public var currentTime: Date
    public init(_ start: Date = Date(timeIntervalSince1970: 0)) { self.currentTime = start }
    public func now() -> Date { currentTime }
    public func advance(by interval: TimeInterval) { currentTime = currentTime.addingTimeInterval(interval) }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/TimesheetTrackerCore/Clock.swift
git commit -m "feat(core): Clock protocol with system + fake implementations"
```

---

## Task 4: LogStore

**Files:**
- Create: `Sources/TimesheetTrackerCore/LogStore.swift`
- Create: `Tests/TimesheetTrackerCoreTests/LogStoreTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/TimesheetTrackerCoreTests/LogStoreTests.swift
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
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `swift test --filter LogStoreTests`
Expected: `LogStore` undefined.

- [ ] **Step 3: Implement `LogStore.swift`**

```swift
// Sources/TimesheetTrackerCore/LogStore.swift
import Foundation

public final class LogStore {
    public let rootDirectory: URL
    private let fm: FileManager

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fm = fileManager
    }

    private var logsDirectory: URL { rootDirectory.appendingPathComponent("logs") }

    private func fileURL(forDay day: String) -> URL {
        logsDirectory.appendingPathComponent("\(day).json")
    }

    private func ensureLogsDirectory() throws {
        if !fm.fileExists(atPath: logsDirectory.path) {
            try fm.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        }
    }

    public func readDay(_ day: String) throws -> DayLog {
        let url = fileURL(forDay: day)
        guard fm.fileExists(atPath: url.path) else {
            return DayLog(date: day, entries: [])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.timesheet.decode(DayLog.self, from: data)
    }

    public func append(_ entry: Entry, toDay day: String) throws {
        try ensureLogsDirectory()
        var dayLog = try readDay(day)
        dayLog.entries.append(entry)
        let data = try JSONEncoder.timesheet.encode(dayLog)
        try data.write(to: fileURL(forDay: day), options: .atomic)
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `swift test --filter LogStoreTests`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TimesheetTrackerCore/LogStore.swift Tests/TimesheetTrackerCoreTests/LogStoreTests.swift
git commit -m "feat(core): LogStore — per-day JSON read/append"
```

---

## Task 5: SessionSidecar

**Files:**
- Create: `Sources/TimesheetTrackerCore/SessionSidecar.swift`
- Create: `Tests/TimesheetTrackerCoreTests/SessionSidecarTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/TimesheetTrackerCoreTests/SessionSidecarTests.swift
import XCTest
@testable import TimesheetTrackerCore

final class SessionSidecarTests: XCTestCase {
    var tempDir: URL!
    var sidecar: SessionSidecar!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ts-sidecar-\(UUID().uuidString)")
        sidecar = SessionSidecar(rootDirectory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_readReturnsNilWhenAbsent() throws {
        XCTAssertNil(try sidecar.read())
    }

    func test_writeThenReadRoundTrips() throws {
        let session = CurrentSession(task: "Hello", startedAt: Date(timeIntervalSince1970: 1_715_400_000))
        try sidecar.write(session)
        XCTAssertEqual(try sidecar.read(), session)
    }

    func test_clearRemovesSidecar() throws {
        try sidecar.write(CurrentSession(task: "X", startedAt: Date()))
        try sidecar.clear()
        XCTAssertNil(try sidecar.read())
    }

    func test_clearWhenAbsentIsNoOp() throws {
        XCTAssertNoThrow(try sidecar.clear())
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `swift test --filter SessionSidecarTests`

- [ ] **Step 3: Implement**

```swift
// Sources/TimesheetTrackerCore/SessionSidecar.swift
import Foundation

public final class SessionSidecar {
    public let rootDirectory: URL
    private let fm: FileManager

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fm = fileManager
    }

    private var url: URL { rootDirectory.appendingPathComponent("current-session.json") }

    public func read() throws -> CurrentSession? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.timesheet.decode(CurrentSession.self, from: data)
    }

    public func write(_ session: CurrentSession) throws {
        if !fm.fileExists(atPath: rootDirectory.path) {
            try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder.timesheet.encode(session)
        try data.write(to: url, options: .atomic)
    }

    public func clear() throws {
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `swift test --filter SessionSidecarTests`

- [ ] **Step 5: Commit**

```bash
git add Sources/TimesheetTrackerCore/SessionSidecar.swift Tests/TimesheetTrackerCoreTests/SessionSidecarTests.swift
git commit -m "feat(core): SessionSidecar for crash-resume"
```

---

## Task 6: WeekAggregation

**Files:**
- Create: `Sources/TimesheetTrackerCore/WeekAggregation.swift`
- Create: `Tests/TimesheetTrackerCoreTests/WeekAggregationTests.swift`

`WeekAggregation` is a pure namespace of functions that takes a list of `DayLog` and produces summary structures for the UI. The Xero cadence is Friday-to-Thursday — given a "report date" (the Thursday the user is filling in), the function returns the 7 days ending on that Thursday.

- [ ] **Step 1: Write failing tests**

```swift
// Tests/TimesheetTrackerCoreTests/WeekAggregationTests.swift
import XCTest
@testable import TimesheetTrackerCore

final class WeekAggregationTests: XCTestCase {
    func test_weekRangeForThursdayReturnsPriorFridayThroughThursday() {
        // Thursday 2026-05-14
        let thursday = ymd("2026-05-14")
        let range = WeekAggregation.fridayToThursdayWindow(endingOn: thursday)
        XCTAssertEqual(range, [
            "2026-05-08", "2026-05-09", "2026-05-10", "2026-05-11",
            "2026-05-12", "2026-05-13", "2026-05-14",
        ])
    }

    func test_weekRangeWhenGivenMidWeekReportsRollsForwardToNextThursday() {
        // Tuesday 2026-05-12 → return week ending the next Thursday 2026-05-14
        let tuesday = ymd("2026-05-12")
        let range = WeekAggregation.fridayToThursdayWindow(endingOn: tuesday)
        XCTAssertEqual(range.last, "2026-05-14")
        XCTAssertEqual(range.count, 7)
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
            Entry(task: "A", start: t, stop: t.addingTimeInterval(3600)),       // 1h
            Entry(task: "B", start: t.addingTimeInterval(3600), stop: t.addingTimeInterval(5400)), // 30m
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
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `swift test --filter WeekAggregationTests`

- [ ] **Step 3: Implement**

```swift
// Sources/TimesheetTrackerCore/WeekAggregation.swift
import Foundation

public enum WeekAggregation {
    public struct TaskTotal: Equatable {
        public let task: String
        public let totalSeconds: TimeInterval
    }

    public struct DaySummary: Equatable {
        public let date: String
        public let totalSeconds: TimeInterval
        public let tasks: [TaskTotal]
    }

    public struct WeekSummary: Equatable {
        public let days: [DaySummary]
        public var totalSeconds: TimeInterval { days.reduce(0) { $0 + $1.totalSeconds } }
    }

    /// Given any date, return the 7-day window Friday→Thursday ending on the Thursday
    /// of (or following) `date`. Date strings are local-time `yyyy-MM-dd`.
    public static func fridayToThursdayWindow(endingOn date: Date, calendar: Calendar = .current) -> [String] {
        var cal = calendar
        cal.timeZone = TimeZone.current
        // Thursday = weekday 5 (Sun=1).
        let weekday = cal.component(.weekday, from: date)
        let daysUntilThursday = (5 - weekday + 7) % 7  // 0 if already Thursday
        let thursday = cal.date(byAdding: .day, value: daysUntilThursday, to: date)!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current
        return (0..<7).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: thursday)!
            return fmt.string(from: d)
        }
    }

    public static func summarize(days: [DayLog], window: [String]) -> WeekSummary {
        let byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
        let summaries = window.map { date -> DaySummary in
            let entries = byDate[date]?.entries ?? []
            let total = entries.reduce(0.0) { $0 + $1.duration }
            var perTask: [String: TimeInterval] = [:]
            for e in entries { perTask[e.task, default: 0] += e.duration }
            let tasks = perTask
                .map { TaskTotal(task: $0.key, totalSeconds: $0.value) }
                .sorted { $0.totalSeconds > $1.totalSeconds }
            return DaySummary(date: date, totalSeconds: total, tasks: tasks)
        }
        return WeekSummary(days: summaries)
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `swift test --filter WeekAggregationTests`

- [ ] **Step 5: Commit**

```bash
git add Sources/TimesheetTrackerCore/WeekAggregation.swift Tests/TimesheetTrackerCoreTests/WeekAggregationTests.swift
git commit -m "feat(core): WeekAggregation — Friday→Thursday window, per-day + per-task totals"
```

---

## Task 7: PreferencesStore

**Files:**
- Create: `Sources/TimesheetTrackerCore/PreferencesStore.swift`

This is a thin `UserDefaults` wrapper. Untested in unit tests (it's a pass-through to UserDefaults). Real defaults are read in the UI.

- [ ] **Step 1: Implement**

```swift
// Sources/TimesheetTrackerCore/PreferencesStore.swift
import Foundation

public final class PreferencesStore {
    public static let shared = PreferencesStore(defaults: .standard)

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.autoStopEnabled: true,
            Keys.autoStopTime: "18:00",
            Keys.menuBarTaskNameMaxLength: 20,
        ])
    }

    private enum Keys {
        static let autoStopEnabled = "autoStopEnabled"
        static let autoStopTime = "autoStopTime"
        static let menuBarTaskNameMaxLength = "menuBarTaskNameMaxLength"
    }

    public var autoStopEnabled: Bool {
        get { defaults.bool(forKey: Keys.autoStopEnabled) }
        set { defaults.set(newValue, forKey: Keys.autoStopEnabled) }
    }

    public var autoStopTime: String {
        get { defaults.string(forKey: Keys.autoStopTime) ?? "18:00" }
        set { defaults.set(newValue, forKey: Keys.autoStopTime) }
    }

    public var menuBarTaskNameMaxLength: Int {
        get { defaults.integer(forKey: Keys.menuBarTaskNameMaxLength) }
        set { defaults.set(newValue, forKey: Keys.menuBarTaskNameMaxLength) }
    }

    /// Returns `autoStopTime` parsed as (hour, minute), or nil if malformed.
    public var autoStopHourMinute: (hour: Int, minute: Int)? {
        let parts = autoStopTime.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return (h, m)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`

- [ ] **Step 3: Commit**

```bash
git add Sources/TimesheetTrackerCore/PreferencesStore.swift
git commit -m "feat(core): PreferencesStore wraps UserDefaults"
```

---

## Task 8: Tracker — core start/stop

**Files:**
- Create: `Sources/TimesheetTrackerCore/Tracker.swift`
- Create: `Tests/TimesheetTrackerCoreTests/TrackerTests.swift`

The Tracker is the heart of the app. Build it incrementally: core start/stop first (Task 8), then sidecar resume (Task 9), then midnight split (Task 10), then auto-stop (Task 11).

- [ ] **Step 1: Write failing core tests**

```swift
// Tests/TimesheetTrackerCoreTests/TrackerTests.swift
import XCTest
@testable import TimesheetTrackerCore

final class TrackerTests: XCTestCase {
    var tempDir: URL!
    var store: LogStore!
    var sidecar: SessionSidecar!
    var clock: FakeClock!
    var prefs: PreferencesStore!
    var tracker: Tracker!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ts-tracker-\(UUID().uuidString)")
        store = LogStore(rootDirectory: tempDir)
        sidecar = SessionSidecar(rootDirectory: tempDir)
        clock = FakeClock(Date(timeIntervalSince1970: 1_715_400_000)) // 2024-05-11 ~ish; arbitrary
        let defaults = UserDefaults(suiteName: "ts-tracker-\(UUID().uuidString)")!
        prefs = PreferencesStore(defaults: defaults)
        tracker = Tracker(store: store, sidecar: sidecar, clock: clock, preferences: prefs)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: Core start/stop

    func test_initiallyStopped() {
        XCTAssertNil(tracker.runningTask)
    }

    func test_startWithEmptyTaskIsRejected() {
        tracker.start(task: "   ")
        XCTAssertNil(tracker.runningTask)
    }

    func test_startSetsRunningTaskAndStartTime() {
        tracker.start(task: "Code review")
        XCTAssertEqual(tracker.runningTask, "Code review")
        XCTAssertEqual(tracker.runningSince, clock.currentTime)
    }

    func test_stopWritesEntryAndClearsRunning() throws {
        tracker.start(task: "Code review")
        clock.advance(by: 60)
        tracker.stop()
        XCTAssertNil(tracker.runningTask)
        let day = try store.readDay(tracker.localDateString(for: clock.currentTime.addingTimeInterval(-60)))
        XCTAssertEqual(day.entries.count, 1)
        XCTAssertEqual(day.entries.first?.task, "Code review")
        XCTAssertEqual(day.entries.first?.duration, 60)
    }

    func test_stopWhenNotRunningIsNoOp() {
        XCTAssertNoThrow(tracker.stop())
        XCTAssertNil(tracker.runningTask)
    }

    func test_startWhileRunningWithDifferentTaskStopsPreviousAndStartsNew() throws {
        tracker.start(task: "A")
        clock.advance(by: 60)
        tracker.start(task: "B")
        XCTAssertEqual(tracker.runningTask, "B")
        let date = tracker.localDateString(for: clock.currentTime)
        let day = try store.readDay(date)
        XCTAssertEqual(day.entries.count, 1)
        XCTAssertEqual(day.entries.first?.task, "A")
        XCTAssertEqual(day.entries.first?.duration, 60)
    }

    func test_startWhileRunningWithSameTaskIsNoOp() throws {
        tracker.start(task: "A")
        let originalStart = tracker.runningSince
        clock.advance(by: 60)
        tracker.start(task: "A")
        XCTAssertEqual(tracker.runningTask, "A")
        XCTAssertEqual(tracker.runningSince, originalStart)
        let date = tracker.localDateString(for: clock.currentTime)
        let day = try store.readDay(date)
        XCTAssertEqual(day.entries.count, 0, "Same-task start should not write an entry")
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `swift test --filter TrackerTests`
Expected: `Tracker` undefined.

- [ ] **Step 3: Implement core Tracker**

```swift
// Sources/TimesheetTrackerCore/Tracker.swift
import Foundation
import Combine

@MainActor
public final class Tracker: ObservableObject {
    private let store: LogStore
    private let sidecar: SessionSidecar
    private let clock: Clock
    private let preferences: PreferencesStore

    @Published public private(set) var runningTask: String?
    @Published public private(set) var runningSince: Date?

    public init(store: LogStore, sidecar: SessionSidecar, clock: Clock, preferences: PreferencesStore) {
        self.store = store
        self.sidecar = sidecar
        self.clock = clock
        self.preferences = preferences
        // Resume in-flight session if sidecar exists (covered by Task 9).
        if let session = try? sidecar.read() {
            self.runningTask = session.task
            self.runningSince = session.startedAt
        }
    }

    public func start(task rawTask: String) {
        let task = rawTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }
        if let currentTask = runningTask {
            if currentTask == task { return }  // same-task no-op
            stop()
        }
        let now = clock.now()
        runningTask = task
        runningSince = now
        try? sidecar.write(CurrentSession(task: task, startedAt: now))
    }

    public func stop() {
        guard let task = runningTask, let start = runningSince else { return }
        let stop = clock.now()
        let entry = Entry(task: task, start: start, stop: stop)
        try? store.append(entry, toDay: localDateString(for: start))
        try? sidecar.clear()
        runningTask = nil
        runningSince = nil
    }

    public func localDateString(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current
        return fmt.string(from: date)
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `swift test --filter TrackerTests`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TimesheetTrackerCore/Tracker.swift Tests/TimesheetTrackerCoreTests/TrackerTests.swift
git commit -m "feat(core): Tracker — start/stop/switch with same-task no-op"
```

---

## Task 9: Tracker — sidecar resume verification

**Files:**
- Modify: `Tests/TimesheetTrackerCoreTests/TrackerTests.swift` (add tests)

Already implemented in Task 8 (constructor reads sidecar); just verifying.

- [ ] **Step 1: Add tests**

Append to `TrackerTests`:

```swift
    func test_startWritesSidecar() throws {
        tracker.start(task: "Hello")
        let session = try sidecar.read()
        XCTAssertEqual(session?.task, "Hello")
        XCTAssertEqual(session?.startedAt, tracker.runningSince)
    }

    func test_stopClearsSidecar() throws {
        tracker.start(task: "Hello")
        clock.advance(by: 10)
        tracker.stop()
        XCTAssertNil(try sidecar.read())
    }

    func test_initWithSidecarPresentResumesSession() throws {
        let pretendStart = Date(timeIntervalSince1970: 1_715_000_000)
        try sidecar.write(CurrentSession(task: "Resumed", startedAt: pretendStart))
        let resumed = Tracker(store: store, sidecar: sidecar, clock: clock, preferences: prefs)
        XCTAssertEqual(resumed.runningTask, "Resumed")
        XCTAssertEqual(resumed.runningSince, pretendStart)
    }
```

- [ ] **Step 2: Run tests — expect PASS**

Run: `swift test --filter TrackerTests`
Expected: 10 tests pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/TimesheetTrackerCoreTests/TrackerTests.swift
git commit -m "test(core): verify Tracker sidecar write/clear/resume"
```

---

## Task 10: Tracker — midnight split

**Files:**
- Modify: `Sources/TimesheetTrackerCore/Tracker.swift`
- Modify: `Tests/TimesheetTrackerCoreTests/TrackerTests.swift`

A session that crosses local midnight should be silently closed at `23:59:59.999` of the old day and reopened at `00:00:00.000` of the new day, preserving the running task. To make this testable, expose a `tickIfMidnightCrossed()` method that the UI/timer will invoke periodically (e.g. every minute). With a fake clock, tests advance time and call this directly.

- [ ] **Step 1: Add test**

Append to `TrackerTests`:

```swift
    func test_midnightCrossSplitsSessionIntoTwoEntries() throws {
        // Compute a date that is "today at 23:30" local time.
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(bySettingHour: 23, minute: 30, second: 0, of: now)!
        clock.currentTime = start
        tracker.start(task: "Late night")

        // Advance to next day 00:15.
        let nextMorning = cal.date(byAdding: .minute, value: 45, to: start)!
        clock.currentTime = nextMorning
        tracker.tickIfMidnightCrossed()

        // The old day's file should contain a single entry ending at 23:59:59.999.
        let oldDay = tracker.localDateString(for: start)
        let newDay = tracker.localDateString(for: nextMorning)
        let oldLog = try store.readDay(oldDay)
        XCTAssertEqual(oldLog.entries.count, 1)
        XCTAssertEqual(oldLog.entries.first?.task, "Late night")
        let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: start)!
            .addingTimeInterval(0.999)
        XCTAssertEqual(oldLog.entries.first?.stop.timeIntervalSinceReferenceDate,
                       endOfDay.timeIntervalSinceReferenceDate, accuracy: 0.01)

        // Tracker is still running with same task; its runningSince is now 00:00 of the new day.
        XCTAssertEqual(tracker.runningTask, "Late night")
        let startOfNewDay = cal.startOfDay(for: nextMorning)
        XCTAssertEqual(tracker.runningSince?.timeIntervalSinceReferenceDate,
                       startOfNewDay.timeIntervalSinceReferenceDate, accuracy: 0.01)

        // Stop now; the new day's file should have one entry from 00:00 → 00:15.
        tracker.stop()
        let newLog = try store.readDay(newDay)
        XCTAssertEqual(newLog.entries.count, 1)
        XCTAssertEqual(newLog.entries.first?.task, "Late night")
    }
```

- [ ] **Step 2: Add `tickIfMidnightCrossed()` to Tracker**

In `Sources/TimesheetTrackerCore/Tracker.swift`, append inside the class:

```swift
    /// Called periodically by the UI/timer (e.g. every 60s). If the running session's
    /// start date is on a different local day than `now`, close it at the previous
    /// day's `23:59:59.999` and reopen at the new day's `00:00:00.000`.
    public func tickIfMidnightCrossed() {
        guard let task = runningTask, let start = runningSince else { return }
        let cal = Calendar.current
        let now = clock.now()
        let startDay = cal.startOfDay(for: start)
        let nowDay = cal.startOfDay(for: now)
        guard startDay != nowDay else { return }

        // Close the old day's entry at 23:59:59.999 of `startDay`.
        let endOfStartDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: startDay)!
            .addingTimeInterval(0.999)
        let oldEntry = Entry(task: task, start: start, stop: endOfStartDay)
        try? store.append(oldEntry, toDay: localDateString(for: start))

        // Reopen at midnight of the *next* day after start. If the cross spanned
        // multiple midnights (e.g. left running over a weekend), we only handle
        // the nearest one here; subsequent ticks will close further days.
        let nextDayStart = cal.date(byAdding: .day, value: 1, to: startDay)!
        runningSince = nextDayStart
        try? sidecar.write(CurrentSession(task: task, startedAt: nextDayStart))

        // If we crossed multiple midnights at once, recurse.
        if cal.startOfDay(for: nextDayStart) != cal.startOfDay(for: now) {
            tickIfMidnightCrossed()
        }
    }
```

- [ ] **Step 3: Run tests — expect PASS**

Run: `swift test --filter TrackerTests`
Expected: 11 tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/TimesheetTrackerCore/Tracker.swift Tests/TimesheetTrackerCoreTests/TrackerTests.swift
git commit -m "feat(core): Tracker — split running session at local midnight"
```

---

## Task 11: Tracker — auto-stop at configurable time

**Files:**
- Modify: `Sources/TimesheetTrackerCore/Tracker.swift`
- Modify: `Tests/TimesheetTrackerCoreTests/TrackerTests.swift`

Auto-stop is exposed via two methods the UI will call:
- `applyAutoStopIfDue()` — invoked when the user wakes the Mac, or by a per-minute timer. If a session is running, the configured auto-stop time has passed today, and the session was started before that time, stop the session retroactively at that auto-stop time.
- `hasAutoStoppedToday(_:)` — internal flag (kept in `UserDefaults` keyed by date) so it only fires once per day.

- [ ] **Step 1: Add tests**

Append to `TrackerTests`:

```swift
    func test_autoStopRetroactivelyStopsAtConfiguredTime() throws {
        prefs.autoStopEnabled = true
        prefs.autoStopTime = "18:00"

        let cal = Calendar.current
        let today = Date()
        let nineAM = cal.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let sevenPM = cal.date(bySettingHour: 19, minute: 0, second: 0, of: today)!

        clock.currentTime = nineAM
        tracker.start(task: "Day job")

        clock.currentTime = sevenPM   // 7 PM; auto-stop should have been 6 PM
        tracker.applyAutoStopIfDue()

        XCTAssertNil(tracker.runningTask, "Auto-stop should have ended the session")
        let day = try store.readDay(tracker.localDateString(for: nineAM))
        XCTAssertEqual(day.entries.count, 1)
        let sixPM = cal.date(bySettingHour: 18, minute: 0, second: 0, of: today)!
        XCTAssertEqual(day.entries[0].stop.timeIntervalSinceReferenceDate,
                       sixPM.timeIntervalSinceReferenceDate, accuracy: 1.0)
    }

    func test_autoStopDoesNothingIfDisabled() {
        prefs.autoStopEnabled = false
        prefs.autoStopTime = "18:00"
        let cal = Calendar.current
        let today = Date()
        clock.currentTime = cal.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        tracker.start(task: "X")
        clock.currentTime = cal.date(bySettingHour: 19, minute: 0, second: 0, of: today)!
        tracker.applyAutoStopIfDue()
        XCTAssertEqual(tracker.runningTask, "X")
    }

    func test_autoStopFiresAtMostOncePerDay() throws {
        prefs.autoStopEnabled = true
        prefs.autoStopTime = "18:00"
        let cal = Calendar.current
        let today = Date()
        let nineAM = cal.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let sevenPM = cal.date(bySettingHour: 19, minute: 0, second: 0, of: today)!
        let eightPM = cal.date(bySettingHour: 20, minute: 0, second: 0, of: today)!

        clock.currentTime = nineAM
        tracker.start(task: "A")
        clock.currentTime = sevenPM
        tracker.applyAutoStopIfDue()
        XCTAssertNil(tracker.runningTask)

        // Start a new task after auto-stop time; auto-stop must NOT fire again today.
        clock.currentTime = eightPM
        tracker.start(task: "Evening work")
        clock.currentTime = eightPM.addingTimeInterval(3600)  // 9 PM
        tracker.applyAutoStopIfDue()
        XCTAssertEqual(tracker.runningTask, "Evening work",
                       "Auto-stop should fire only once per day")
    }
```

- [ ] **Step 2: Add `applyAutoStopIfDue()` to Tracker**

In `Sources/TimesheetTrackerCore/Tracker.swift`, append inside the class:

```swift
    private var lastAutoStopDayKey: String { "lastAutoStopDay" }

    public func applyAutoStopIfDue() {
        guard preferences.autoStopEnabled,
              let (h, m) = preferences.autoStopHourMinute,
              let task = runningTask,
              let start = runningSince else { return }

        let cal = Calendar.current
        let now = clock.now()
        let today = cal.startOfDay(for: now)
        let autoStopMoment = cal.date(bySettingHour: h, minute: m, second: 0, of: today)!

        // Only fire if: now >= autoStopMoment AND session started before autoStopMoment
        // AND we haven't already auto-stopped today.
        guard now >= autoStopMoment, start <= autoStopMoment else { return }
        let todayKey = localDateString(for: now)
        if UserDefaults.standard.string(forKey: lastAutoStopDayKey) == todayKey { return }

        let entry = Entry(task: task, start: start, stop: autoStopMoment)
        try? store.append(entry, toDay: localDateString(for: start))
        try? sidecar.clear()
        runningTask = nil
        runningSince = nil
        UserDefaults.standard.set(todayKey, forKey: lastAutoStopDayKey)
    }
```

- [ ] **Step 3: Run tests — expect PASS**

Run: `swift test --filter TrackerTests`
Expected: 14 tests pass.

> Note: the auto-stop "fires only once per day" guard uses `UserDefaults.standard`. In tests that share a process, prior test state can leak. The setUp resets the per-test sidecar but not this key. Add a `tearDown` block that clears it:

In `setUpWithError`, after creating the tracker, add:
```swift
UserDefaults.standard.removeObject(forKey: "lastAutoStopDay")
```

- [ ] **Step 4: Commit**

```bash
git add Sources/TimesheetTrackerCore/Tracker.swift Tests/TimesheetTrackerCoreTests/TrackerTests.swift
git commit -m "feat(core): Tracker — auto-stop at configurable end-of-day time"
```

---

## Task 12: AppPaths helper

**Files:**
- Create: `Sources/TimesheetTrackerCore/AppPaths.swift`

Centralises the Application Support directory lookup so the app target and any debug tools point at the same place.

- [ ] **Step 1: Implement**

```swift
// Sources/TimesheetTrackerCore/AppPaths.swift
import Foundation

public enum AppPaths {
    public static var applicationSupportDirectory: URL {
        let fm = FileManager.default
        let base = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                               appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("TimesheetTracker", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`

- [ ] **Step 3: Commit**

```bash
git add Sources/TimesheetTrackerCore/AppPaths.swift
git commit -m "feat(core): AppPaths — locates ~/Library/Application Support/TimesheetTracker"
```

---

## Task 13: SwiftUI app entry — `TimesheetTrackerApp`

**Files:**
- Create: `Sources/TimesheetTracker/TimesheetTrackerApp.swift`

- [ ] **Step 1: Implement**

```swift
// Sources/TimesheetTracker/TimesheetTrackerApp.swift
import SwiftUI
import TimesheetTrackerCore
import Combine

@main
struct TimesheetTrackerApp: App {
    @StateObject private var tracker = TrackerHost.shared.tracker
    @State private var showPreferences = false

    var body: some Scene {
        MenuBarExtra {
            PopoverView(showPreferences: $showPreferences)
                .environmentObject(tracker)
                .frame(width: 360)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tracker.runningTask == nil ? "timer" : "timer.circle.fill")
                if let task = tracker.runningTask {
                    Text(truncate(task, to: PreferencesStore.shared.menuBarTaskNameMaxLength))
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
        }
    }

    private func truncate(_ s: String, to n: Int) -> String {
        s.count <= n ? s : String(s.prefix(max(0, n - 1))) + "…"
    }
}

/// Shared host that owns the Tracker singleton plus a periodic tick
/// that drives midnight-split and auto-stop checks once per minute.
@MainActor
final class TrackerHost {
    static let shared = TrackerHost()

    let tracker: Tracker
    private var tickTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private init() {
        let root = AppPaths.applicationSupportDirectory
        let store = LogStore(rootDirectory: root)
        let sidecar = SessionSidecar(rootDirectory: root)
        tracker = Tracker(store: store, sidecar: sidecar, clock: SystemClock(),
                          preferences: PreferencesStore.shared)

        // Tick every 60s to handle midnight + auto-stop.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tracker.tickIfMidnightCrossed()
                self?.tracker.applyAutoStopIfDue()
            }
        }

        // Also run on wake-from-sleep to handle the "Mac was asleep at auto-stop time" case.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tracker.tickIfMidnightCrossed()
                self?.tracker.applyAutoStopIfDue()
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: warning-free build of the `TimesheetTracker` executable.

- [ ] **Step 3: Commit**

```bash
git add Sources/TimesheetTracker/TimesheetTrackerApp.swift
git commit -m "feat(app): @main App with MenuBarExtra + 60s tick + wake observer"
```

---

## Task 14: PopoverView

**Files:**
- Create: `Sources/TimesheetTracker/PopoverView.swift`

The popover is the only UI most days. Composition:
- Task text field (focused on open, Return = start)
- Start / Stop buttons
- "Running: <task> · 1h 23m" row (visible only when running, live-updates every second)
- Divider
- Today's entries list with daily total
- "This week ▾" disclosure (uses WeekView from Task 15)
- Gear button → opens Settings scene

- [ ] **Step 1: Implement**

```swift
// Sources/TimesheetTracker/PopoverView.swift
import SwiftUI
import TimesheetTrackerCore

struct PopoverView: View {
    @EnvironmentObject var tracker: Tracker
    @Binding var showPreferences: Bool
    @State private var taskInput = ""
    @FocusState private var inputFocused: Bool
    @State private var tickNow = Date()
    @State private var weekExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What are you working on?")
                .font(.headline)

            TextField("Task name", text: $taskInput)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .onSubmit { onStart() }

            HStack(spacing: 8) {
                Button(action: onStart) { Text("Start").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .disabled(taskInput.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(action: { tracker.stop() }) { Text("Stop").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                    .disabled(tracker.runningTask == nil)
            }

            if let task = tracker.runningTask, let since = tracker.runningSince {
                HStack {
                    Image(systemName: "circle.fill").foregroundStyle(.red).font(.caption)
                    Text("Running: \(task)").bold()
                    Spacer()
                    Text(formatDuration(tickNow.timeIntervalSince(since)))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            Divider()
            TodayList(now: tickNow)
            Divider()

            DisclosureGroup(isExpanded: $weekExpanded) {
                WeekView()
            } label: {
                Text("This week").font(.callout)
            }

            HStack {
                Spacer()
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .onAppear { inputFocused = true }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            tickNow = now
        }
    }

    private func onStart() {
        let trimmed = taskInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        tracker.start(task: trimmed)
        taskInput = ""
    }
}

/// Today's entries plus current running session as a "preview" final row.
struct TodayList: View {
    @EnvironmentObject var tracker: Tracker
    let now: Date
    @State private var entries: [Entry] = []
    @State private var dailyTotal: TimeInterval = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today").font(.subheadline).bold()
                Spacer()
                Text(formatDuration(dailyTotal)).monospacedDigit().foregroundStyle(.secondary)
            }
            if entries.isEmpty && tracker.runningTask == nil {
                Text("No entries yet today").foregroundStyle(.secondary).font(.callout)
            } else {
                ForEach(entries.indices, id: \.self) { i in
                    EntryRow(entry: entries[i])
                }
                if let task = tracker.runningTask, let since = tracker.runningSince {
                    HStack {
                        Text(time(since)).monospacedDigit().foregroundStyle(.secondary)
                        Text("–").foregroundStyle(.secondary)
                        Text("now").monospacedDigit().foregroundStyle(.secondary)
                        Text(task).lineLimit(1)
                        Spacer()
                        Text(formatDuration(now.timeIntervalSince(since)))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
        .onAppear { refresh() }
        .onChange(of: tracker.runningTask) { _, _ in refresh() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    private func refresh() {
        let store = LogStore(rootDirectory: AppPaths.applicationSupportDirectory)
        let today = tracker.localDateString(for: Date())
        let day = (try? store.readDay(today)) ?? DayLog(date: today, entries: [])
        entries = day.entries
        var total = day.entries.reduce(0.0) { $0 + $1.duration }
        if let since = tracker.runningSince {
            total += Date().timeIntervalSince(since)
        }
        dailyTotal = total
    }

    private func time(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }
}

struct EntryRow: View {
    let entry: Entry
    var body: some View {
        HStack {
            Text(timeOnly(entry.start)).monospacedDigit().foregroundStyle(.secondary)
            Text("–").foregroundStyle(.secondary)
            Text(timeOnly(entry.stop)).monospacedDigit().foregroundStyle(.secondary)
            Text(entry.task).lineLimit(1)
            Spacer()
            Text(formatDuration(entry.duration)).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.callout)
    }
    private func timeOnly(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    let h = s / 3600
    let m = (s % 3600) / 60
    return String(format: "%dh %02dm", h, m)
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`

- [ ] **Step 3: Commit**

```bash
git add Sources/TimesheetTracker/PopoverView.swift
git commit -m "feat(app): PopoverView — task input, start/stop, live today list"
```

---

## Task 15: WeekView

**Files:**
- Create: `Sources/TimesheetTracker/WeekView.swift`

- [ ] **Step 1: Implement**

```swift
// Sources/TimesheetTracker/WeekView.swift
import SwiftUI
import TimesheetTrackerCore

struct WeekView: View {
    @EnvironmentObject var tracker: Tracker
    @State private var summary: WeekAggregation.WeekSummary = .init(days: [])

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if summary.days.isEmpty {
                Text("Loading…").foregroundStyle(.secondary)
            } else {
                ForEach(summary.days, id: \.date) { day in
                    DayRow(day: day)
                }
                Divider()
                HStack {
                    Text("Week total").bold()
                    Spacer()
                    Text(formatDuration(summary.totalSeconds)).monospacedDigit()
                }
                .font(.callout)
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        let store = LogStore(rootDirectory: AppPaths.applicationSupportDirectory)
        let window = WeekAggregation.fridayToThursdayWindow(endingOn: Date())
        let days = window.compactMap { try? store.readDay($0) }
        summary = WeekAggregation.summarize(days: days, window: window)
    }
}

private struct DayRow: View {
    let day: WeekAggregation.DaySummary
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text(formatDate(day.date))
                    }
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(formatDuration(day.totalSeconds)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)

            if expanded {
                ForEach(day.tasks, id: \.task) { t in
                    HStack {
                        Text("  • \(t.task)").foregroundStyle(.secondary)
                        Spacer()
                        Text(formatDuration(t.totalSeconds))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func formatDate(_ ymd: String) -> String {
        let inFmt = DateFormatter(); inFmt.dateFormat = "yyyy-MM-dd"
        guard let date = inFmt.date(from: ymd) else { return ymd }
        let outFmt = DateFormatter(); outFmt.dateFormat = "EEE d MMM"
        return outFmt.string(from: date)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`

- [ ] **Step 3: Commit**

```bash
git add Sources/TimesheetTracker/WeekView.swift
git commit -m "feat(app): WeekView — Fri→Thu summary with per-task expand"
```

---

## Task 16: PreferencesView

**Files:**
- Create: `Sources/TimesheetTracker/PreferencesView.swift`

- [ ] **Step 1: Implement**

```swift
// Sources/TimesheetTracker/PreferencesView.swift
import SwiftUI
import TimesheetTrackerCore

struct PreferencesView: View {
    @State private var autoStopEnabled = PreferencesStore.shared.autoStopEnabled
    @State private var autoStopTime = PreferencesStore.shared.autoStopTime
    @State private var maxLen: Double = Double(PreferencesStore.shared.menuBarTaskNameMaxLength)

    var body: some View {
        Form {
            Section("Auto-stop") {
                Toggle("Auto-stop running task at:", isOn: $autoStopEnabled)
                    .onChange(of: autoStopEnabled) { _, new in
                        PreferencesStore.shared.autoStopEnabled = new
                    }
                TextField("End-of-day time (HH:MM)", text: $autoStopTime)
                    .disabled(!autoStopEnabled)
                    .onSubmit {
                        PreferencesStore.shared.autoStopTime = autoStopTime
                    }
            }
            Section("Menu bar") {
                HStack {
                    Text("Truncate task name at: \(Int(maxLen)) chars")
                    Slider(value: $maxLen, in: 8...40, step: 1)
                        .onChange(of: maxLen) { _, new in
                            PreferencesStore.shared.menuBarTaskNameMaxLength = Int(new)
                        }
                }
            }
        }
        .padding(20)
        .frame(width: 380, height: 220)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`

- [ ] **Step 3: Commit**

```bash
git add Sources/TimesheetTracker/PreferencesView.swift
git commit -m "feat(app): PreferencesView"
```

---

## Task 17: Info.plist template + build script

**Files:**
- Create: `scripts/Info.plist`
- Create: `scripts/build-app.sh` (executable)

`swift build` produces a bare executable. To get a proper menu-bar agent app (no Dock, no Cmd+Tab) we wrap it in a `.app` bundle with `LSUIElement=true`.

- [ ] **Step 1: Write `Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Timesheet Tracker</string>
    <key>CFBundleDisplayName</key>
    <string>Timesheet Tracker</string>
    <key>CFBundleIdentifier</key>
    <string>com.anthonytoci.TimesheetTracker</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>TimesheetTracker</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Write `build-app.sh`**

```bash
#!/usr/bin/env bash
# scripts/build-app.sh — build the executable in release mode and assemble
# a TimesheetTracker.app bundle in ./build/.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="TimesheetTracker"
BUNDLE_NAME="Timesheet Tracker.app"
BUILD_DIR="build"

echo "→ swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/${APP_NAME}"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "Build failed: $BIN_PATH not found" >&2
    exit 1
fi

APP_DIR="${BUILD_DIR}/${BUNDLE_NAME}"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/${APP_NAME}"
cp scripts/Info.plist "$APP_DIR/Contents/Info.plist"

# Ad-hoc sign so the OS will run the bundle.
codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "✓ Built $APP_DIR"
echo "  Run it:   open \"$APP_DIR\""
echo "  Install:  cp -R \"$APP_DIR\" /Applications/"
```

- [ ] **Step 3: Make executable**

```bash
chmod +x scripts/build-app.sh
```

- [ ] **Step 4: Commit**

```bash
git add scripts/
git commit -m "build: scripts/build-app.sh + Info.plist for .app bundling"
```

---

## Task 18: First end-to-end build + smoke

**Files:** none (manual)

- [ ] **Step 1: Build the app bundle**

Run: `./scripts/build-app.sh release`
Expected: `build/Timesheet Tracker.app` exists; no errors.

- [ ] **Step 2: Run it**

Run: `open "build/Timesheet Tracker.app"`
Expected: menu bar shows a `timer` icon; no Dock icon; no app window.

- [ ] **Step 3: Smoke checks**

Walk through:
- Click icon → popover opens, text field focused.
- Type "Smoke test", press Return → menu bar shows `⏱ Smoke test`, popover shows running row.
- Wait 30 seconds → "Running" elapsed counter advances.
- Type "Another task", press Return → previous stops, new starts; today list shows the first entry.
- Press Stop → menu bar returns to outlined timer.
- Open `~/Library/Application Support/TimesheetTracker/logs/<today>.json` → contains both entries.

- [ ] **Step 4: Stop test instance**

Use `pkill -f TimesheetTracker` to fully quit (no Dock means no easy Quit menu in v1; we can add a "Quit" item to the popover later if needed).

- [ ] **Step 5: Commit smoke notes** (none — just confirm)

---

## Task 19: Add a "Quit" action

**Files:**
- Modify: `Sources/TimesheetTracker/PopoverView.swift`

The popover's gear row should also have a `Quit` button so the user isn't stuck on `pkill`.

- [ ] **Step 1: Modify gear row**

In `PopoverView.swift`, replace the existing `HStack { Spacer(); ... Image(systemName: "gear") ... }` with:

```swift
            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.borderless)
            }
```

- [ ] **Step 2: Rebuild and verify**

Run: `./scripts/build-app.sh release && open "build/Timesheet Tracker.app"`
Click the popover's `Quit` button → app exits.

- [ ] **Step 3: Commit**

```bash
git add Sources/TimesheetTracker/PopoverView.swift
git commit -m "feat(app): Quit button in popover footer"
```

---

## Task 20: Final pass

- [ ] **Step 1: All tests pass**

Run: `swift test`
Expected: 28+ tests pass.

- [ ] **Step 2: Release build clean**

Run: `./scripts/build-app.sh release`
Expected: no warnings beyond benign ones.

- [ ] **Step 3: Manual checklist from the spec's testing section**

- Start, wait 30s, Stop → entry in today's JSON ✓
- Start A, type B + Return → two entries, no gap ✓
- Force-quit while running, relaunch → still running with original start time ✓
- Set auto-stop to 1 minute in the future, leave running → stops at that minute ✓
- Restart Mac while running → resumes on next launch (skip if you don't want to actually restart — covered by sidecar tests)

- [ ] **Step 4: Tag v0.1.0**

```bash
git tag -a v0.1.0 -m "v0.1.0: initial release"
```

---

## Self-review

- **Spec coverage:** every spec section maps to a task or set of tasks. App bundle (LSUIElement) → Task 17. ✓
- **Placeholders:** none.
- **Type consistency:** `Tracker.runningTask: String?` / `Tracker.runningSince: Date?` consistent across tasks 8–11. `tickIfMidnightCrossed()` and `applyAutoStopIfDue()` are the two periodic methods called from the host. `LogStore.append(_:toDay:)` consistent.
- **Scope:** focused on v1; out-of-scope items (global hotkey, CSV) explicitly deferred.
