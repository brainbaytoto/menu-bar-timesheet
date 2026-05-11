import XCTest
@testable import TimesheetTrackerCore

@MainActor
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
        clock = FakeClock(Date(timeIntervalSince1970: 1_715_400_000))
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
        let startTime = clock.currentTime
        clock.advance(by: 60)
        tracker.stop()
        XCTAssertNil(tracker.runningTask)
        let day = try store.readDay(tracker.localDateString(for: startTime))
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

    // MARK: Sidecar resume

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

    // MARK: Midnight crossing

    func test_midnightCrossSplitsSessionIntoTwoEntries() throws {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(bySettingHour: 23, minute: 30, second: 0, of: now)!
        clock.currentTime = start
        tracker.start(task: "Late night")

        let nextMorning = cal.date(byAdding: .minute, value: 45, to: start)!
        clock.currentTime = nextMorning
        tracker.tickIfMidnightCrossed()

        let oldDay = tracker.localDateString(for: start)
        let newDay = tracker.localDateString(for: nextMorning)
        let oldLog = try store.readDay(oldDay)
        XCTAssertEqual(oldLog.entries.count, 1)
        XCTAssertEqual(oldLog.entries.first?.task, "Late night")
        let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: start)!
            .addingTimeInterval(0.999)
        XCTAssertEqual(oldLog.entries.first!.stop.timeIntervalSinceReferenceDate,
                       endOfDay.timeIntervalSinceReferenceDate, accuracy: 0.01)

        XCTAssertEqual(tracker.runningTask, "Late night")
        let startOfNewDay = cal.startOfDay(for: nextMorning)
        XCTAssertEqual(tracker.runningSince!.timeIntervalSinceReferenceDate,
                       startOfNewDay.timeIntervalSinceReferenceDate, accuracy: 0.01)

        tracker.stop()
        let newLog = try store.readDay(newDay)
        XCTAssertEqual(newLog.entries.count, 1)
        XCTAssertEqual(newLog.entries.first?.task, "Late night")
    }

    // MARK: Auto-stop

    func test_autoStopRetroactivelyStopsAtConfiguredTime() throws {
        prefs.autoStopEnabled = true
        prefs.autoStopTime = "18:00"

        let cal = Calendar.current
        let today = Date()
        let nineAM = cal.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let sevenPM = cal.date(bySettingHour: 19, minute: 0, second: 0, of: today)!

        clock.currentTime = nineAM
        tracker.start(task: "Day job")

        clock.currentTime = sevenPM
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

        clock.currentTime = eightPM
        tracker.start(task: "Evening work")
        clock.currentTime = eightPM.addingTimeInterval(3600)
        tracker.applyAutoStopIfDue()
        XCTAssertEqual(tracker.runningTask, "Evening work",
                       "Auto-stop should fire only once per day")
    }
}
