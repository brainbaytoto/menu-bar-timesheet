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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section(title: "Launch") {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, new in setLaunchAtLogin(new) }
                    if let err = launchAtLoginError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                section(title: "Auto-stop") {
                    Toggle("Auto-stop running task at end of day", isOn: $autoStopEnabled)
                        .onChange(of: autoStopEnabled) { _, new in
                            PreferencesStore.shared.autoStopEnabled = new
                        }
                    HStack {
                        Text("End-of-day time (HH:MM, 24h):")
                        TextField("", text: $autoStopTime)
                            .frame(width: 80)
                            .disabled(!autoStopEnabled)
                            .onSubmit { PreferencesStore.shared.autoStopTime = autoStopTime }
                        Spacer()
                    }
                }

                section(title: "Auto-stop warning") {
                    Toggle("Notify me before auto-stop", isOn: $notifyEnabled)
                        .onChange(of: notifyEnabled) { _, new in
                            PreferencesStore.shared.notifyBeforeAutoStopEnabled = new
                            if new { NotificationScheduler.shared.requestAuthorizationIfNeeded() }
                        }
                    HStack {
                        Text("Warn \(Int(notifyMinutes)) minute\(Int(notifyMinutes) == 1 ? "" : "s") before")
                            .frame(width: 180, alignment: .leading)
                        Slider(value: $notifyMinutes, in: 1...30, step: 1)
                            .disabled(!notifyEnabled)
                            .onChange(of: notifyMinutes) { _, new in
                                PreferencesStore.shared.notifyBeforeAutoStopMinutes = Int(new)
                            }
                    }
                }

                section(title: "Default workday times") {
                    Text("Used as the default Start/Stop when adding a past entry.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Text("Start")
                        TextField("", text: $workdayStart)
                            .frame(width: 80)
                            .onSubmit { PreferencesStore.shared.defaultWorkdayStart = workdayStart }
                        Text("Stop")
                        TextField("", text: $workdayStop)
                            .frame(width: 80)
                            .onSubmit { PreferencesStore.shared.defaultWorkdayStop = workdayStop }
                        Spacer()
                    }
                }

                section(title: "Menu bar") {
                    HStack {
                        Text("Truncate task name at \(Int(maxLen)) chars")
                            .frame(width: 220, alignment: .leading)
                        Slider(value: $maxLen, in: 8...40, step: 1)
                            .onChange(of: maxLen) { _, new in
                                PreferencesStore.shared.menuBarTaskNameMaxLength = Int(new)
                            }
                    }
                }

                section(title: "Data") {
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, height: 600)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox(label: Text(title).font(.headline)) {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}
