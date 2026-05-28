# Last Week section in the popover

**Date:** 2026-05-29
**Status:** Approved (design), pending implementation

## Problem

The timesheet week runs Friday→Thursday, and I submit my timesheet on Thursday (the
last day of the week). I keep forgetting to submit on Thursdays. When I open the app on
Friday — the start of a new week — there's no way to see last week's totals to submit
late. The popover only ever shows the current Friday→Thursday week.

## Goal

Show the previous Friday→Thursday week alongside the current one in the popover, with the
same per-day rows, totals, and editing, so I can review and submit last week's hours when
I've missed the Thursday deadline.

## Decisions

- **Display:** A collapsible `DisclosureGroup` titled "Last week", placed directly below
  the existing "This week" group. **Collapsed by default** so the popover stays compact.
- **Editing:** Fully editable — the same `DayRow` (edit-on-tap, "+ Add entry") as this
  week, so forgotten entries can be added when catching up.
- **Visibility:** Always rendered (just collapsed), even when last week recorded no time.
  Predictable — it's always there when I go looking for it.

## Approach

Approach A — parameterise the rendering view so a single component serves both weeks.

The data layer already supports any week: `WeekAggregation.fridayToThursdayWindow(endingOn:)`
produces the Friday→Thursday window for whatever date it's given. No storage or file
changes are needed.

To keep all date arithmetic in the unit-tested `WeekAggregation` layer (and out of the
SwiftUI view), `WeekView` is changed to **render an injected window** (`[String]` of
`yyyy-MM-dd` dates) rather than computing `Date()` internally. `PopoverView` supplies each
window from `WeekAggregation`.

### Data layer — `Sources/TimesheetTrackerCore/WeekAggregation.swift`

Add one helper, alongside the existing `fridayToThursdayWindow`:

```swift
/// The Friday→Thursday window for the week *before* the one containing `date`.
public static func lastWeekWindow(relativeTo date: Date = Date(),
                                  calendar: Calendar = .current) -> [String] {
    let priorWeekDate = calendar.date(byAdding: .day, value: -7, to: date) ?? date
    return fridayToThursdayWindow(endingOn: priorWeekDate, calendar: calendar)
}
```

Rationale: a date 7 days before any day in the current week lands in the prior week, and
the existing window helper resolves it to that week's Friday→Thursday range. No new range
logic — just composition over the tested helper.

### View — `Sources/TimesheetTracker/WeekView.swift`

`WeekView` becomes presentational over an injected window:

- Replace the `@State private var window: [String]` with a stored `let window: [String]`
  property (the window is now supplied by the parent).
- Keep `@State private var dayLogs` and the `weekTotal` computed property (it already reads
  from `window` + `dayLogs`, unchanged).
- `refresh()` no longer computes the window; it only reloads `dayLogs` for the injected
  `window`:

  ```swift
  private func refresh() {
      let store = LogStore(rootDirectory: AppPaths.applicationSupportDirectory)
      var logs: [String: DayLog] = [:]
      for day in window {
          if let log = try? store.readDay(day) { logs[day] = log }
      }
      dayLogs = logs
  }
  ```

- Reload when the popover appears *and* when the injected window changes (e.g. the clock
  rolls past midnight while the popover is open):

  ```swift
  .onAppear { refresh() }
  .onChange(of: window) { refresh() }
  ```

- `DayRow` and all editing wiring (`EditorCoordinator.shared.open(...)`) are unchanged —
  both weeks get identical edit/add behaviour for free.

### View — `Sources/TimesheetTracker/PopoverView.swift`

- Add `@State private var lastWeekExpanded = false` (mirrors the existing `weekExpanded`).
- Pass this week's window into the existing group:

  ```swift
  DisclosureGroup(isExpanded: $weekExpanded) {
      WeekView(window: WeekAggregation.fridayToThursdayWindow(endingOn: tickNow))
  } label: {
      Text("This week").font(.callout)
  }
  ```

- Add a second group directly below it:

  ```swift
  DisclosureGroup(isExpanded: $lastWeekExpanded) {
      WeekView(window: WeekAggregation.lastWeekWindow(relativeTo: tickNow))
  } label: {
      Text("Last week").font(.callout)
  }
  ```

Using `tickNow` (already updated every second by the existing timer) keeps both windows
live across a midnight rollover without extra plumbing. The recomputed window array is
value-equal second-to-second, so `WeekView`'s `.onChange(of: window)` only fires when the
week actually changes — no per-second reload churn.

## What does NOT change

- Storage format, file naming, `DayLog`, `Entry`, `LogStore` — untouched.
- `DayRow` and the editor flow — untouched; reused verbatim.
- `fridayToThursdayWindow` behaviour — untouched.
- Duration / week-total formatting — untouched.

## Testing

Unit tests in `Tests/TimesheetTrackerCoreTests/WeekAggregationTests.swift`:

1. `test_lastWeekWindowFromFridayReturnsPriorFridayToThursday` — `relativeTo` a Friday
   (`2026-05-29`) returns `["2026-05-22" … "2026-05-28"]` (7 dates, Fri→Thu).
2. `test_lastWeekWindowFromThursdayReturnsPriorWeek` — `relativeTo` a Thursday
   (`2026-06-04`, this week's last day) returns the same prior-week window
   `["2026-05-22" … "2026-05-28"]`, asserting it does not return the current week.

Both assert `count == 7` and exact membership, reusing the existing `ymd(_:)` helper.

UI wiring (the second DisclosureGroup, collapsed default, editability) is verified by
building and running the app and confirming "Last week" appears below "This week", expands
to last week's days, and supports edit / "+ Add entry".

## Out of scope (YAGNI)

- Arbitrary week navigation (back/forward beyond last week).
- Any "submitted" status tracking — the app has no such concept.
- Persisting the expanded/collapsed state across launches.
