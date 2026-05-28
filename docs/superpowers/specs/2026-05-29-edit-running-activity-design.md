# Edit the running activity (start time + task)

**Date:** 2026-05-29
**Status:** Approved (design), pending implementation

## Problem

When an activity is running, the popover shows a non-interactive "Running: …" row
with a live duration. If I forgot to hit Start on time (e.g. started working at 09:00
but only clicked Start at 09:15) or mistyped the task name, there's no way to correct
it — I have to stop and re-add the entry manually.

## Goal

Click the running activity in the popover to edit its **start time** and **task name**
in place, with the live elapsed duration updating to match.

## Constraint that shapes the design

The menu-bar popover auto-dismisses the moment a `DatePicker` steals focus. The existing
`EditorCoordinator` already works around this by hosting the entry editor in a floating
`NSWindow` rather than a SwiftUI sheet. The running-activity editor must use the same
floating-window approach — an inline picker in the popover would dismiss itself.

## Decisions

- **Editable:** start time and task name (not stop — there isn't one yet; not delete).
- **Presentation:** a modal floating window titled "Edit running activity", consistent
  with the Add/Edit entry editor.
- **Trigger:** clicking the existing "Running: …" row.

## Design

### Core — `Sources/TimesheetTrackerCore/Tracker.swift`

Add one method (the `Tracker` owns `runningTask`/`runningSince` and the sidecar):

```swift
@discardableResult
public func adjustRunningSession(task rawTask: String, start: Date) -> Bool {
    guard runningTask != nil else { return false }
    let task = rawTask.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !task.isEmpty, start <= clock.now() else { return false }
    runningTask = task
    runningSince = start
    try? sidecar.write(CurrentSession(task: task, startedAt: start))
    return true
}
```

- Guards: a session must be running, task non-empty, and `start` not in the future
  (a future start would make elapsed negative).
- Returns `false` on rejection so the behaviour is unit-testable.
- Persists to the sidecar exactly as `start()` does, so the change survives a restart.

### New view — `Sources/TimesheetTracker/RunningEditorSheet.swift`

A trimmed sibling of `EntryEditorSheet`:

- Fields: **Task** (`TextField`) and **Start** (`DatePicker`, `.hourAndMinute` only).
  No stop picker, no delete button.
- Live **Elapsed** preview driven by a 1 s timer (same pattern as `PopoverView`).
- Initialises from the passed-in `task` and `start`.
- On Save: anchor the picked hour/minute to the **start's existing day**
  (`Calendar.startOfDay(for: start)`), so only the time-of-day changes; validate the task
  is non-empty and the anchored start is `<= Date()`; then call
  `onSave(anchoredTask, anchoredStart)`. Show an inline red error otherwise.
- Cancel calls `onCancel()`.
- Signature: `init(task: String, start: Date, onSave: @escaping (String, Date) -> Void,
  onCancel: @escaping () -> Void)`. The view is Tracker-agnostic — it just reports the
  new values, mirroring how `EntryEditorSheet` reports to the store.

### Coordinator — `Sources/TimesheetTracker/EditorCoordinator.swift`

Add a method alongside the existing `open(day:mode:onSave:)`:

```swift
func openRunningEditor(task: String, start: Date,
                       onSave: @escaping (String, Date) -> Void,
                       onCancel: @escaping () -> Void)
```

It hosts `RunningEditorSheet` in the same floating-`NSWindow` machinery (reusing the single
`window` slot and close observer), titled "Edit running activity". `onSave`/`onCancel`
close the window as the existing `open(...)` does.

### Trigger — `Sources/TimesheetTracker/PopoverView.swift`

Wrap the existing "Running: …" row (lines 31–40) in a plain `Button` with a faint trailing
`pencil` glyph for affordance. The button calls:

```swift
EditorCoordinator.shared.openRunningEditor(
    task: task, start: since,
    onSave: { newTask, newStart in
        tracker.adjustRunningSession(task: newTask, start: newStart)
    },
    onCancel: {}
)
```

`PopoverView` holds the `tracker` (an `@EnvironmentObject`), so it supplies the closure;
the coordinator and sheet stay Tracker-agnostic.

## What does NOT change

- Storage format, `Entry`, `DayLog`, `LogStore` — untouched.
- `start()`, `stop()`, midnight-crossing, auto-stop logic — untouched.
- `EntryEditorSheet` and the completed-entry edit flow — untouched.

## Testing

TDD, core unit tests in `Tests/TimesheetTrackerCoreTests/TrackerTests.swift`:

1. `test_adjustRunningSessionAppliesNewStartAndTaskAndWritesSidecar` — with a session
   running, adjust to an earlier start and a new task; assert `runningSince`/`runningTask`
   update, the result is `true`, and the sidecar reflects the new values.
2. `test_adjustRunningSessionNoOpWhenNothingRunning` — returns `false`, nothing changes.
3. `test_adjustRunningSessionRejectsFutureStart` — a start after `clock.now()` returns
   `false` and leaves `runningSince` unchanged.
4. `test_adjustRunningSessionRejectsEmptyTask` — a whitespace-only task returns `false`
   and leaves the session unchanged.

UI wiring (clickable row, sheet fields, live elapsed, error states) is verified by building
and running the app.

## Out of scope (YAGNI)

- Editing the stop time (no stop exists while running).
- Moving the start to a different calendar day.
- Editing the running activity from anywhere other than the popover.
