import SwiftUI
import TimesheetTrackerCore

struct PreferencesView: View {
    @State private var autoStopEnabled = PreferencesStore.shared.autoStopEnabled
    @State private var autoStopTime = PreferencesStore.shared.autoStopTime
    @State private var maxLen: Double = Double(PreferencesStore.shared.menuBarTaskNameMaxLength)

    var body: some View {
        Form {
            Section("Auto-stop") {
                Toggle("Auto-stop running task at end of day", isOn: $autoStopEnabled)
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
                VStack(alignment: .leading) {
                    Text("Truncate task name at: \(Int(maxLen)) chars")
                    Slider(value: $maxLen, in: 8...40, step: 1)
                        .onChange(of: maxLen) { _, new in
                            PreferencesStore.shared.menuBarTaskNameMaxLength = Int(new)
                        }
                }
            }
        }
        .padding(20)
        .frame(width: 380, height: 240)
    }
}
