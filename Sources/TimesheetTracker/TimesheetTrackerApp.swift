import SwiftUI
import TimesheetTrackerCore
import Combine
import AppKit

@main
struct TimesheetTrackerApp: App {
    @StateObject private var tracker = TrackerHost.shared.tracker
    @ObservedObject private var prefsObserver = PreferencesObserver.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(tracker)
                .frame(width: 360)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tracker.runningTask == nil ? "timer" : "timer.circle.fill")
                if let task = tracker.runningTask {
                    Text(truncate(task, to: prefsObserver.maxLen))
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

/// Singleton owning the Tracker plus a 60-second tick and wake-from-sleep observer
/// that drive midnight-split and auto-stop checks.
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

        tickTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tracker.tickIfMidnightCrossed()
                NotificationScheduler.shared.checkAndFire(runningTask: self.tracker.runningTask)
                self.tracker.applyAutoStopIfDue()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tracker.tickIfMidnightCrossed()
                NotificationScheduler.shared.checkAndFire(runningTask: self.tracker.runningTask)
                self.tracker.applyAutoStopIfDue()
            }
        }
    }
}

/// Tiny ObservableObject that publishes preference changes the views care about.
/// Currently only the menu-bar truncation length needs to drive a redraw.
@MainActor
final class PreferencesObserver: ObservableObject {
    static let shared = PreferencesObserver()
    @Published var maxLen: Int = PreferencesStore.shared.menuBarTaskNameMaxLength

    private init() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.maxLen = PreferencesStore.shared.menuBarTaskNameMaxLength
            }
        }
    }
}
