import SwiftUI
import TimesheetTrackerCore

/// Modal sheet for creating or editing an entry on a specific day.
/// The entry's date is fixed (`day`); only hour-and-minute are editable.
struct EntryEditorSheet: View {
    enum Mode {
        case edit(original: Entry)
        case create
    }

    let day: String              // yyyy-MM-dd
    let mode: Mode
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var taskName: String
    @State private var startTime: Date
    @State private var stopTime: Date
    @State private var errorMessage: String?

    init(day: String, mode: Mode, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.day = day
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
        let dayStart = Self.parseDay(day)
        switch mode {
        case .edit(let original):
            _taskName = State(initialValue: original.task)
            _startTime = State(initialValue: original.start)
            _stopTime = State(initialValue: original.stop)
        case .create:
            let cal = Calendar.current
            let now = Date()
            let nowDay = cal.startOfDay(for: now)
            let isToday = cal.isDate(dayStart, inSameDayAs: nowDay)
            let prefs = PreferencesStore.shared
            let workStart = prefs.defaultWorkdayStartHourMinute
            let workStop = prefs.defaultWorkdayStopHourMinute
            let defaultStart: Date
            let defaultStop: Date
            if isToday {
                // For today, default to 1h ago → now (likely a "just forgot to hit Start" case).
                defaultStop = now
                defaultStart = cal.date(byAdding: .hour, value: -1, to: now) ?? now
            } else {
                // Past day: default to the user's configured workday window.
                defaultStart = cal.date(bySettingHour: workStart.hour, minute: workStart.minute,
                                         second: 0, of: dayStart) ?? dayStart
                defaultStop = cal.date(bySettingHour: workStop.hour, minute: workStop.minute,
                                        second: 0, of: dayStart) ?? dayStart
            }
            _taskName = State(initialValue: "")
            _startTime = State(initialValue: defaultStart)
            _stopTime = State(initialValue: defaultStop)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(headerTitle).font(.headline)
                Spacer()
                Text(dayHeader).foregroundStyle(.secondary).font(.callout)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Task").font(.caption).foregroundStyle(.secondary)
                TextField("Task name", text: $taskName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Stop").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: $stopTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }

            HStack {
                Text("Duration:").foregroundStyle(.secondary)
                Text(formatDuration(displayedDuration))
                    .monospacedDigit()
            }
            .font(.callout)

            if let err = errorMessage {
                Text(err).foregroundStyle(.red).font(.callout)
            }

            HStack {
                if case .edit = mode {
                    Button("Delete", role: .destructive, action: deleteEntry)
                }
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: saveEntry)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    /// Duration computed from the pickers with seconds stripped, so the preview
    /// matches the value that will actually be saved (saveEntry forces second = 0).
    private var displayedDuration: TimeInterval {
        let cal = Calendar.current
        let startMin = cal.date(bySettingHour: cal.component(.hour, from: startTime),
                                 minute: cal.component(.minute, from: startTime),
                                 second: 0, of: startTime) ?? startTime
        let stopMin = cal.date(bySettingHour: cal.component(.hour, from: stopTime),
                                minute: cal.component(.minute, from: stopTime),
                                second: 0, of: stopTime) ?? stopTime
        return stopMin.timeIntervalSince(startMin)
    }

    private var headerTitle: String {
        switch mode {
        case .edit: return "Edit entry"
        case .create: return "Add entry"
        }
    }

    private var dayHeader: String {
        let inFmt = DateFormatter(); inFmt.dateFormat = "yyyy-MM-dd"
        guard let d = inFmt.date(from: day) else { return day }
        let outFmt = DateFormatter(); outFmt.dateFormat = "EEE d MMM"
        return outFmt.string(from: d)
    }

    private func saveEntry() {
        errorMessage = nil
        let trimmed = taskName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Task name cannot be empty."
            return
        }

        let dayStart = Self.parseDay(day)
        // Re-anchor the date pickers to the entry's day (DatePicker may have shifted them).
        let cal = Calendar.current
        let startComponents = cal.dateComponents([.hour, .minute], from: startTime)
        let stopComponents = cal.dateComponents([.hour, .minute], from: stopTime)
        guard
            let anchoredStart = cal.date(bySettingHour: startComponents.hour ?? 0,
                                          minute: startComponents.minute ?? 0,
                                          second: 0, of: dayStart),
            let anchoredStop = cal.date(bySettingHour: stopComponents.hour ?? 0,
                                         minute: stopComponents.minute ?? 0,
                                         second: 0, of: dayStart)
        else {
            errorMessage = "Couldn't compute times."
            return
        }
        guard anchoredStop > anchoredStart else {
            errorMessage = "Stop time must be after start time."
            return
        }

        let newEntry = Entry(task: trimmed, start: anchoredStart, stop: anchoredStop)
        do {
            let store = LogStore(rootDirectory: AppPaths.applicationSupportDirectory)
            var dayLog = try store.readDay(day)
            switch mode {
            case .edit(let original):
                dayLog.entries.removeAll { $0 == original }
                dayLog.entries.append(newEntry)
            case .create:
                dayLog.entries.append(newEntry)
            }
            try store.writeDay(dayLog)
            onSave()
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private func deleteEntry() {
        guard case .edit(let original) = mode else { return }
        do {
            let store = LogStore(rootDirectory: AppPaths.applicationSupportDirectory)
            var dayLog = try store.readDay(day)
            dayLog.entries.removeAll { $0 == original }
            try store.writeDay(dayLog)
            onSave()
        } catch {
            errorMessage = "Couldn't delete: \(error.localizedDescription)"
        }
    }

    private static func parseDay(_ ymd: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone.current
        return f.date(from: ymd) ?? Date()
    }
}
