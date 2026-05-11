import Foundation

public enum WeekAggregation {
    public struct TaskTotal: Equatable {
        public let task: String
        public let totalSeconds: TimeInterval
        public init(task: String, totalSeconds: TimeInterval) {
            self.task = task
            self.totalSeconds = totalSeconds
        }
    }

    public struct DaySummary: Equatable {
        public let date: String
        public let totalSeconds: TimeInterval
        public let tasks: [TaskTotal]
        public init(date: String, totalSeconds: TimeInterval, tasks: [TaskTotal]) {
            self.date = date
            self.totalSeconds = totalSeconds
            self.tasks = tasks
        }
    }

    public struct WeekSummary: Equatable {
        public let days: [DaySummary]
        public var totalSeconds: TimeInterval { days.reduce(0) { $0 + $1.totalSeconds } }
        public init(days: [DaySummary]) { self.days = days }
    }

    /// 7-day window ending on the Thursday of (or following) `date`,
    /// returned as `yyyy-MM-dd` local-date strings.
    public static func fridayToThursdayWindow(endingOn date: Date, calendar: Calendar = .current) -> [String] {
        var cal = calendar
        cal.timeZone = TimeZone.current
        let weekday = cal.component(.weekday, from: date)
        let daysUntilThursday = (5 - weekday + 7) % 7
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
