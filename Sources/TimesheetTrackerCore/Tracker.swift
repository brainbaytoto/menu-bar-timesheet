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
        if let session = try? sidecar.read() {
            self.runningTask = session.task
            self.runningSince = session.startedAt
        }
    }

    public func start(task rawTask: String) {
        let task = rawTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }
        if let currentTask = runningTask {
            if currentTask == task { return }
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

    /// Periodic tick (call every ~60s and on wake-from-sleep).
    /// If the running session's start is on a different local day than `now`,
    /// close it at the previous day's 23:59:59.999 and reopen at the new day's 00:00:00.000.
    public func tickIfMidnightCrossed() {
        guard let task = runningTask, let start = runningSince else { return }
        let cal = Calendar.current
        let now = clock.now()
        let startDay = cal.startOfDay(for: start)
        let nowDay = cal.startOfDay(for: now)
        guard startDay != nowDay else { return }

        let endOfStartDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: startDay)!
            .addingTimeInterval(0.999)
        let oldEntry = Entry(task: task, start: start, stop: endOfStartDay)
        try? store.append(oldEntry, toDay: localDateString(for: start))

        let nextDayStart = cal.date(byAdding: .day, value: 1, to: startDay)!
        runningSince = nextDayStart
        try? sidecar.write(CurrentSession(task: task, startedAt: nextDayStart))

        if cal.startOfDay(for: nextDayStart) != cal.startOfDay(for: now) {
            tickIfMidnightCrossed()
        }
    }

    /// If a session is running, the configured auto-stop time has passed today,
    /// and the session started before that time, stop the session retroactively
    /// at the auto-stop moment. Fires at most once per local day.
    public func applyAutoStopIfDue() {
        guard preferences.autoStopEnabled,
              let (h, m) = preferences.autoStopHourMinute,
              let task = runningTask,
              let start = runningSince else { return }

        let cal = Calendar.current
        let now = clock.now()
        let today = cal.startOfDay(for: now)
        let autoStopMoment = cal.date(bySettingHour: h, minute: m, second: 0, of: today)!

        guard now >= autoStopMoment, start <= autoStopMoment else { return }
        let todayKey = localDateString(for: now)
        if preferences.lastAutoStopDay == todayKey { return }

        let entry = Entry(task: task, start: start, stop: autoStopMoment)
        try? store.append(entry, toDay: localDateString(for: start))
        try? sidecar.clear()
        runningTask = nil
        runningSince = nil
        preferences.lastAutoStopDay = todayKey
    }
}
