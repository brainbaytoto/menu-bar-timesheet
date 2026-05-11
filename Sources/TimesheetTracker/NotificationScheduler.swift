import Foundation
import UserNotifications
import TimesheetTrackerCore

/// Pushes a macOS notification N minutes before the configured auto-stop time
/// fires, but only if a task is currently running. Fires at most once per day.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private let prefs = PreferencesStore.shared
    private var authorizationRequested = false

    /// Call when the notification setting is turned on. Asks the user once for
    /// notification permission.
    func requestAuthorizationIfNeeded() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Call from the host's 60-second tick. If a session is running, the
    /// configured warning moment is in the past minute, and we haven't warned
    /// today, post a notification.
    func checkAndFire(runningTask: String?, now: Date = Date()) {
        guard prefs.notifyBeforeAutoStopEnabled,
              prefs.autoStopEnabled,
              let task = runningTask,
              let (h, m) = prefs.autoStopHourMinute else { return }

        let warningOffset = -prefs.notifyBeforeAutoStopMinutes * 60
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let autoStopMoment = cal.date(bySettingHour: h, minute: m, second: 0, of: today)
        else { return }
        let warningMoment = autoStopMoment.addingTimeInterval(TimeInterval(warningOffset))

        // Window: warningMoment <= now < autoStopMoment, and we haven't warned today.
        guard now >= warningMoment, now < autoStopMoment else { return }
        let todayKey = localDateString(for: now)
        if prefs.lastAutoStopWarningDay == todayKey { return }

        let content = UNMutableNotificationContent()
        content.title = "Timesheet Tracker"
        content.body = "Auto-stop fires in \(prefs.notifyBeforeAutoStopMinutes) minute(s). Currently tracking: \(task)."
        content.sound = .default
        let req = UNNotificationRequest(identifier: "ts-warning-\(todayKey)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)

        prefs.lastAutoStopWarningDay = todayKey
    }

    private func localDateString(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }
}
