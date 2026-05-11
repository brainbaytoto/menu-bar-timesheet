import SwiftUI
import TimesheetTrackerCore

struct WeekView: View {
    @EnvironmentObject var tracker: Tracker
    @State private var summary: WeekAggregation.WeekSummary = .init(days: [])

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if summary.days.isEmpty {
                Text("Loading…").foregroundStyle(.secondary)
            } else {
                ForEach(summary.days, id: \.date) { day in
                    DayRow(day: day)
                }
                Divider()
                HStack {
                    Text("Week total").bold()
                    Spacer()
                    Text(formatDuration(summary.totalSeconds)).monospacedDigit()
                }
                .font(.callout)
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        let store = LogStore(rootDirectory: AppPaths.applicationSupportDirectory)
        let window = WeekAggregation.fridayToThursdayWindow(endingOn: Date())
        let days = window.compactMap { try? store.readDay($0) }
        summary = WeekAggregation.summarize(days: days, window: window)
    }
}

private struct DayRow: View {
    let day: WeekAggregation.DaySummary
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text(formatDate(day.date))
                    }
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(formatDuration(day.totalSeconds)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)

            if expanded {
                ForEach(day.tasks, id: \.task) { t in
                    HStack {
                        Text("  • \(t.task)").foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text(formatDuration(t.totalSeconds))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
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
}
