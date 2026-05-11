import SwiftUI
import TimesheetTrackerCore

struct WeekView: View {
    @EnvironmentObject var tracker: Tracker
    @State private var window: [String] = []
    @State private var dayLogs: [String: DayLog] = [:]

    var weekTotal: TimeInterval {
        window.reduce(0.0) { acc, day in
            acc + (dayLogs[day]?.entries.reduce(0.0) { $0 + $1.duration } ?? 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if window.isEmpty {
                Text("Loading…").foregroundStyle(.secondary)
            } else {
                ForEach(window, id: \.self) { day in
                    DayRow(day: day, entries: dayLogs[day]?.entries ?? []) { entry in
                        EditorCoordinator.shared.open(
                            day: day, mode: .edit(original: entry)
                        ) { refresh() }
                    } onAdd: {
                        EditorCoordinator.shared.open(
                            day: day, mode: .create
                        ) { refresh() }
                    }
                }
                Divider()
                HStack {
                    Text("Week total").bold()
                    Spacer()
                    Text(formatDuration(weekTotal)).monospacedDigit()
                }
                .font(.callout)
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        let store = LogStore(rootDirectory: AppPaths.applicationSupportDirectory)
        window = WeekAggregation.fridayToThursdayWindow(endingOn: Date())
        var logs: [String: DayLog] = [:]
        for day in window {
            if let log = try? store.readDay(day) { logs[day] = log }
        }
        dayLogs = logs
    }
}

private struct DayRow: View {
    let day: String
    let entries: [Entry]
    let onEdit: (Entry) -> Void
    let onAdd: () -> Void
    @State private var expanded = false

    var dayTotal: TimeInterval { entries.reduce(0.0) { $0 + $1.duration } }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text(formatDate(day))
                    }
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(formatDuration(dayTotal)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)

            if expanded {
                if entries.isEmpty {
                    Text("  No entries").foregroundStyle(.secondary).font(.caption)
                } else {
                    ForEach(entries.indices, id: \.self) { i in
                        Button {
                            onEdit(entries[i])
                        } label: {
                            HStack {
                                Text("  " + timeOnly(entries[i].start))
                                    .monospacedDigit().foregroundStyle(.secondary)
                                Text("–").foregroundStyle(.secondary)
                                Text(timeOnly(entries[i].stop))
                                    .monospacedDigit().foregroundStyle(.secondary)
                                Text(entries[i].task).lineLimit(1).foregroundStyle(.primary)
                                Spacer()
                                Text(formatDuration(entries[i].duration))
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                    }
                }
                HStack {
                    Spacer()
                    Button("+ Add entry", action: onAdd)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        }
    }

    private func formatDate(_ ymd: String) -> String {
        let inFmt = DateFormatter(); inFmt.dateFormat = "yyyy-MM-dd"
        guard let date = inFmt.date(from: ymd) else { return ymd }
        let outFmt = DateFormatter(); outFmt.dateFormat = "EEE d MMM"
        return outFmt.string(from: date)
    }
    private func timeOnly(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
}
