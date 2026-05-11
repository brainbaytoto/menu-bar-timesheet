import SwiftUI
import TimesheetTrackerCore
import AppKit
import ServiceManagement

struct PreferencesView: View {
    @State private var autoStopEnabled = PreferencesStore.shared.autoStopEnabled
    @State private var autoStopTime = PreferencesStore.shared.autoStopTime
    @State private var maxLen: Double = Double(PreferencesStore.shared.menuBarTaskNameMaxLength)
    @State private var workdayStart = PreferencesStore.shared.defaultWorkdayStart
    @State private var workdayStop = PreferencesStore.shared.defaultWorkdayStop
    @State private var notifyEnabled = PreferencesStore.shared.notifyBeforeAutoStopEnabled
    @State private var notifyMinutes: Double = Double(PreferencesStore.shared.notifyBeforeAutoStopMinutes)
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("Launch") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, new in
                        setLaunchAtLogin(new)
                    }
                if let err = launchAtLoginError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Auto-stop") {
                Toggle("Auto-stop running task at end of day", isOn: $autoStopEnabled)
                    .onChange(of: autoStopEnabled) { _, new in
                        PreferencesStore.shared.autoStopEnabled = new
                    }
                TextField("End-of-day time (HH:MM, 24h)", text: $autoStopTime)
                    .disabled(!autoStopEnabled)
                    .onSubmit { PreferencesStore.shared.autoStopTime = autoStopTime }
            }

            Section("Auto-stop warning") {
                Toggle("Notify me before auto-stop", isOn: $notifyEnabled)
                    .onChange(of: notifyEnabled) { _, new in
                        PreferencesStore.shared.notifyBeforeAutoStopEnabled = new
                        if new { NotificationScheduler.shared.requestAuthorizationIfNeeded() }
                    }
                VStack(alignment: .leading) {
                    Text("Warn \(Int(notifyMinutes)) minute(s) before").font(.callout)
                    Slider(value: $notifyMinutes, in: 1...30, step: 1)
                        .disabled(!notifyEnabled)
                        .onChange(of: notifyMinutes) { _, new in
                            PreferencesStore.shared.notifyBeforeAutoStopMinutes = Int(new)
                        }
                }
            }

            Section("Default workday times") {
                Text("Used as the default Start/Stop when adding a past entry.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Start")
                    TextField("HH:MM", text: $workdayStart)
                        .frame(width: 80)
                        .onSubmit { PreferencesStore.shared.defaultWorkdayStart = workdayStart }
                    Spacer()
                    Text("Stop")
                    TextField("HH:MM", text: $workdayStop)
                        .frame(width: 80)
                        .onSubmit { PreferencesStore.shared.defaultWorkdayStop = workdayStop }
                }
            }

            Section("Menu bar") {
                VStack(alignment: .leading) {
                    Text("Truncate task name at: \(Int(maxLen)) chars")
                    Slider(value: $maxLen, in: 8...40, step: 1)
                        .onChange(of: maxLen) { _, new in
                            PreferencesStore.shared.menuBarTaskNameMaxLength = Int(new)
                        }
                }
            }

            Section("Data") {
                HStack {
                    Text("Logs are stored as JSON, one file per day.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Data Folder") {
                        NSWorkspace.shared.open(AppPaths.applicationSupportDirectory)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 440, height: 540)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = "Couldn't \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
            // Revert toggle so it reflects reality.
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}
