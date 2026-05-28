import SwiftUI
import TimesheetTrackerCore

/// Modal editor for the currently running activity. Edits the task name and the
/// start time-of-day (anchored to the start's existing day); there is no stop time
/// while the session is running. Reports the new values via `onSave`.
struct RunningEditorSheet: View {
    let originalStart: Date
    let onSave: (String, Date) -> Void
    let onCancel: () -> Void

    @State private var taskName: String
    @State private var startTime: Date
    @State private var errorMessage: String?
    @State private var now = Date()

    init(task: String, start: Date,
         onSave: @escaping (String, Date) -> Void,
         onCancel: @escaping () -> Void) {
        self.originalStart = start
        self.onSave = onSave
        self.onCancel = onCancel
        _taskName = State(initialValue: task)
        _startTime = State(initialValue: start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit running activity").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Task").font(.caption).foregroundStyle(.secondary)
                TextField("Task name", text: $taskName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Start").font(.caption).foregroundStyle(.secondary)
                DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }

            HStack {
                Text("Elapsed:").foregroundStyle(.secondary)
                Text(formatDuration(max(0, now.timeIntervalSince(anchoredStart))))
                    .monospacedDigit()
            }
            .font(.callout)

            if let err = errorMessage {
                Text(err).foregroundStyle(.red).font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    /// The picked hour/minute re-anchored to the start's original day, so editing the
    /// time-of-day never silently shifts the session to a different calendar day.
    private var anchoredStart: Date {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: originalStart)
        let comps = cal.dateComponents([.hour, .minute], from: startTime)
        return cal.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0,
                        second: 0, of: dayStart) ?? originalStart
    }

    private func save() {
        errorMessage = nil
        let trimmed = taskName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Task name cannot be empty."
            return
        }
        let start = anchoredStart
        guard start <= Date() else {
            errorMessage = "Start time can't be in the future."
            return
        }
        onSave(trimmed, start)
    }
}
