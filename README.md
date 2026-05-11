# Timesheet Tracker

A tiny menu bar app for macOS that records start/stop timestamps for whatever you're working on, then surfaces a 7-day summary you can read off when filling in your real timesheet (Xero Me, Harvest, a corporate intranet form — whatever you transcribe into manually).

## Why

I have to fill in my timesheet on the Xero Me app on my phone every Thursday afternoon. I needed something that did exactly three things — Start, Stop, name the task — and then showed me daily totals at the end of the week. No projects, no clients, no syncing, no signup. This is that app.

## What it does

- Lives in the menu bar (`⏱` icon). No Dock icon, no window stealing focus.
- Type a task name + Return → tracking starts. Type a new name + Return → previous stops, new one starts (no gap).
- "Today" list shows each entry with start time, stop time, duration, and a live counter for whatever's currently running.
- "This week" expands into 7 days of daily totals (Friday → Thursday cadence). Each day expands further to show its individual entries, tappable to edit.
- Tap any past entry to change the task name, start time, stop time, or delete it. `+` adds a missed entry retroactively.
- Auto-stops at a configurable end-of-day time so you don't accidentally log 16 hours when you forget to hit Stop.
- Survives crashes / restarts by writing a sidecar file for the in-flight session.
- Stores everything in plain JSON at `~/Library/Application Support/TimesheetTracker/logs/YYYY-MM-DD.json` — hand-editable if you'd rather use a text editor.

## Build

Requires macOS 14 (Sonoma) or later and Xcode command-line tools.

```bash
./scripts/build-app.sh release
cp -R "build/Timesheet Tracker.app" /Applications/
```

To auto-start at login, either add it via **System Settings → General → Login Items**, or run:

```bash
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Timesheet Tracker.app", hidden:false, name:"Timesheet Tracker"}'
```

## Tests

```bash
swift test
```

35 unit tests covering the storage layer, the tracker state machine (start/stop, task switching, midnight split, auto-stop, sidecar resume), and the weekly aggregation function. The SwiftUI views are tested manually.

## Project layout

```
Sources/
  TimesheetTrackerCore/   ← pure Swift, no UI; all the logic that matters
  TimesheetTracker/       ← SwiftUI MenuBarExtra app
Tests/                    ← XCTest against the core
scripts/                  ← build-app.sh + Info.plist for bundling
docs/superpowers/         ← design spec + implementation plan
```

## Status

Works for me. Built in an afternoon as a personal tool. Open an issue if something breaks; PRs welcome.

## License

MIT.
