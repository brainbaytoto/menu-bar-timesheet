import SwiftUI
import TimesheetTrackerCore
import AppKit

struct PopoverView: View {
    @EnvironmentObject var tracker: Tracker
    @State private var taskInput = ""
    @FocusState private var inputFocused: Bool
    @State private var tickNow = Date()
    @State private var weekExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What are you working on?")
                .font(.headline)

            TextField("Task name", text: $taskInput)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .onSubmit { onStart() }

            HStack(spacing: 8) {
                Button(action: onStart) { Text("Start").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .disabled(taskInput.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(action: { tracker.stop() }) { Text("Stop").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                    .disabled(tracker.runningTask == nil)
            }

            if let task = tracker.runningTask, let since = tracker.runningSince {
                HStack {
                    Image(systemName: "circle.fill").foregroundStyle(.red).font(.caption)
                    Text("Running: \(task)").bold().lineLimit(1)
                    Spacer()
                    Text(formatDuration(tickNow.timeIntervalSince(since)))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            Divider()
            TodayList(now: tickNow)
            Divider()

            DisclosureGroup(isExpanded: $weekExpanded) {
                WeekView()
            } label: {
                Text("This week").font(.callout)
            }

            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                Button {
                    PreferencesCoordinator.shared.open()
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.borderless)
                .help("Preferences")
            }
        }
        .padding(14)
        .onAppear { inputFocused = true }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            tickNow = now
        }
    }

    private func onStart() {
        let trimmed = taskInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        tracker.start(task: trimmed)
        taskInput = ""
    }
}

struct TodayList: View {
    @EnvironmentObject var tracker: Tracker
    let now: Date
    @State private var entries: [Entry] = []
    @State private var dailyTotal: TimeInterval = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today").font(.subheadline).bold()
                Spacer()
                Text(formatDuration(dailyTotal)).monospacedDigit().foregroundStyle(.secondary)
                Button {
                    EditorCoordinator.shared.open(
                        day: tracker.localDateString(for: Date()),
                        mode: .create
                    ) { refresh() }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .help("Add a past entry for today")
            }
            if entries.isEmpty && tracker.runningTask == nil {
                Text("No entries yet today").foregroundStyle(.secondary).font(.callout)
            } else {
                ForEach(entries.indices, id: \.self) { i in
                    EntryRow(entry: entries[i]) {
                        let entry = entries[i]
                        EditorCoordinator.shared.open(
                            day: tracker.localDateString(for: entry.start),
                            mode: .edit(original: entry)
                        ) { refresh() }
                    }
                }
                if let task = tracker.runningTask, let since = tracker.runningSince {
                    HStack {
                        Text(timeOnly(since)).monospacedDigit().foregroundStyle(.secondary)
                        Text("–").foregroundStyle(.secondary)
                        Text("now").monospacedDigit().foregroundStyle(.secondary)
                        Text(task).lineLimit(1)
                        Spacer()
                        Text(formatDuration(now.timeIntervalSince(since)))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
        .onAppear { refresh() }
        .onChange(of: tracker.runningTask) { _, _ in refresh() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    private func refresh() {
        let store = LogStore(rootDirectory: AppPaths.applicationSupportDirectory)
        let today = tracker.localDateString(for: Date())
        let day = (try? store.readDay(today)) ?? DayLog(date: today, entries: [])
        entries = day.entries
        var total = day.entries.reduce(0.0) { $0 + $1.duration }
        if let since = tracker.runningSince {
            total += Date().timeIntervalSince(since)
        }
        dailyTotal = total
    }

    private func timeOnly(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }
}

struct EntryRow: View {
    let entry: Entry
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(timeOnly(entry.start)).monospacedDigit().foregroundStyle(.secondary)
                Text("–").foregroundStyle(.secondary)
                Text(timeOnly(entry.stop)).monospacedDigit().foregroundStyle(.secondary)
                Text(entry.task).lineLimit(1).foregroundStyle(.primary)
                Spacer()
                Text(formatDuration(entry.duration)).monospacedDigit().foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.callout)
    }
    private func timeOnly(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    let h = s / 3600
    let m = (s % 3600) / 60
    return String(format: "%dh %02dm", h, m)
}
