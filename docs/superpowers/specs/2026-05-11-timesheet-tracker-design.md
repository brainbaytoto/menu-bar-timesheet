# Timesheet Time Tracker — Design Spec

**Date:** 2026-05-11
**Status:** Approved (awaiting written-spec review before plan)
**Author:** Anthony Toci (designed collaboratively with Claude)

## Purpose

A tiny macOS menu bar app that records time spent on tasks throughout the day so the user can transcribe **total hours per day** into the Xero Me mobile timesheet app each Thursday afternoon.

The app is not a full timesheet system. It is a personal log that produces a glanceable weekly summary the user reads off-screen while typing into Xero Me on a phone.

## Non-goals

- No CSV/spreadsheet export.
- No upload, sync, or integration with Xero or any other service.
- No team/multi-user features.
- No reporting beyond a 7-day rolling view.
- No editing of past entries from inside the UI (edit the JSON files by hand if needed).
- No global hotkey in v1.

## User stories

1. Sitting at my Mac, I type the task I'm starting in the menu bar popover and hit Return. Time tracking begins.
2. I switch tasks — I open the popover, type the new task name, hit Return. Previous task stops, new one starts, no gap.
3. I glance at the menu bar and see the current task + icon, so I know I'm still tracking the right thing.
4. End of day, I hit Stop (or auto-stop fires at 6pm). The session ends.
5. Thursday afternoon, I open the popover, click "This week", and see a list of the last 7 days with total hours per day. I read off each daily total and type it into Xero Me on my phone.

## Architecture

Single SwiftUI macOS app target. Three layers:

- **UI** — `MenuBarExtra` scene with a popover. Holds no state; observes the tracker.
- **Tracker** (`@Observable` class) — in-memory source of truth for "is something running, what task, since when". Exposes `start(task:)`, `stop()`, and current state. Owns the auto-stop timer.
- **Log store** — pure file I/O over per-day JSON files. Append-only writes; on-demand reads for "today" and "this week".

The tracker writes a completed entry to the log store every time a session ends (Stop, new task, auto-stop, clean quit). While a session is in-flight, the tracker persists a `current-session.json` sidecar so a crash or restart can recover the running session.

Each layer is independently testable: log store with a temp directory, tracker with a fake clock and a fake store, UI with previews.

## Data model

**Storage location:** `~/Library/Application Support/TimesheetTracker/`
- `logs/YYYY-MM-DD.json` — one file per day
- `current-session.json` — sidecar for in-flight session (deleted when session ends)

**Per-day log file** — `logs/2026-05-11.json`:

```json
{
  "date": "2026-05-11",
  "entries": [
    { "task": "Code review",    "start": "2026-05-11T09:02:14+10:00", "stop": "2026-05-11T10:15:03+10:00" },
    { "task": "Client meeting", "start": "2026-05-11T10:15:03+10:00", "stop": "2026-05-11T11:00:00+10:00" }
  ]
}
```

- ISO 8601 timestamps with timezone offset (so DST and travel don't corrupt durations).
- `date` is the local-time date the entry's `start` falls on.
- An entry that crosses midnight is split into two entries, each written to its own day's file (keeps "total hours per day" honest).
- Entries are appended in chronological order. The app never rewrites past entries.

**Live session sidecar** — `current-session.json`:

```json
{ "task": "Code review", "startedAt": "2026-05-11T09:02:14+10:00" }
```

Written immediately when Start is pressed, deleted when the session ends. Presence on launch = session was running when the app last closed → tracker resumes it.

**Preferences** — `UserDefaults`:

| Key                          | Type   | Default  |
|------------------------------|--------|----------|
| `autoStopEnabled`            | Bool   | `true`   |
| `autoStopTime`               | String | `"18:00"` (HH:MM, 24-hour, local) |
| `menuBarTaskNameMaxLength`   | Int    | `20`     |

## UI and interaction flow

**Menu bar item** — `MenuBarExtra` with a custom label:
- Stopped: SF Symbol `timer` outlined.
- Running: `timer` filled + task name truncated to `menuBarTaskNameMaxLength` chars (with `…`). E.g. `⏱ Code review`.

**Popover** — single panel, ~320pt wide:

```
┌─────────────────────────────────────┐
│ What are you working on?            │
│ ┌─────────────────────────────────┐ │
│ │ Code review                     │ │  ← TextField, focuses on open
│ └─────────────────────────────────┘ │
│                                     │
│         [  Start  ]   [  Stop  ]    │  ← Stop disabled when not running
│                                     │
│ Running: Code review · 1h 13m       │  ← only shown when running
│ ─────────────────────────────────── │
│ Today — 3h 47m total                │
│   09:02 – 10:15  Code review  1h13m │
│   10:15 – 11:00  Client mtg   0h45m │
│   11:00 – now    Code review  1h49m │
│                                     │
│ [ This week ▾ ]            [ ⚙ ]   │
└─────────────────────────────────────┘
```

**Interactions:**
- **Start** with text in the field → tracker starts that task. If another session was running, it is stopped first.
- **Return** in the text field while running, with a different name → stop current, start new.
- **Return** with the same name as currently running → no-op (no zero-second entry).
- **Stop** → ends current session; text field is cleared.
- **"This week ▾"** → expands the popover to show the last 7 days (Friday-to-Thursday, matching the Xero cadence), each row showing the daily total. Per-task breakdown via a disclosure triangle.
- **⚙** → opens a small Preferences window: auto-stop on/off, auto-stop time, menu-bar truncation length.

**Keyboard:**
- Text field has focus on popover open.
- Return = Start.
- Esc closes the popover.
- No global hotkey in v1.

**Auto-stop:** one timer fires at `autoStopTime` each day. If a session is running, it is stopped with that exact moment as the stop time. Silent — no popup. Fires once per day; sessions started after auto-stop time run normally.

## Error handling and edge cases

**File I/O failures**
- Log directory missing on first launch → created lazily.
- Read failure (corrupt JSON, permission denied) → log via `os.Logger`, surface a small red banner in the popover (`Couldn't load today's log — see Console`). Never blocks Start/Stop. The tracker keeps running in memory; the next successful write recreates the file.
- Write failure → retry once after 200ms; if still failing, keep the entry buffered in memory and surface the banner. Buffer flushes on next successful write.

**Crash / unclean quit recovery**
- On launch, if `current-session.json` exists: tracker enters running state with that task and original start time. The user can hit Stop normally — stop time is "now", not when the crash happened. (Better to slightly over-attribute than to silently lose hours.)

**Midnight crossing**
- Running session at local midnight → tracker silently closes the entry at `23:59:59.999` of the old day and opens a new entry at `00:00:00.000` of the new day, same task. Both halves written to their respective day files. No user-visible interruption.

**Auto-stop edge cases**
- Mac asleep at `autoStopTime` → timer doesn't fire. On wake, tracker checks "is a session running, and has the auto-stop time already passed today?" If yes, stop retroactively at today's `autoStopTime`.
- Auto-stop fires at most once per day. A session started after auto-stop time runs normally until manually stopped or until the next day's auto-stop time.

**Empty task name** → Start button disabled.

**Same-task-as-currently-running** → no-op.

**Time changes (DST, manual clock change, travel)** → timestamps store the offset at the instant they were recorded. Durations are computed from absolute instants, not wall-clock strings.

**System sleep mid-session** → macOS sleep does not stop the session. Session continues on wake with its original start time. Combined with auto-stop-on-wake, "I shut my laptop at 6pm without stopping" still produces the right end time.

## Testing strategy

**Unit tests (XCTest)** — the bulk of testing.

`LogStore` (temp directory):
- Empty directory → reading today returns empty.
- Write an entry → readable verbatim.
- Append a second entry → both present, in order.
- Cross-day write → correct file picked per entry date.
- Corrupt JSON file → surfaces an error, doesn't crash.

`Tracker` (fake clock + in-memory fake store):
- Start with empty task → rejected.
- Start → state is running with correct task and start time.
- Stop → state is stopped, entry written with correct start/stop pair.
- Start while running with new name → previous entry written, new session running, zero gap.
- Start while running with same name → no-op.
- Midnight crossing while running → two entries written, split at `23:59:59.999` / `00:00:00.000`.
- Auto-stop time passes while running → entry written with auto-stop time as stop.
- Auto-stop time already passed when wake-from-sleep is signaled → retroactive stop.
- Sidecar present on init → tracker resumes that session.
- Time zone change mid-session → durations remain correct.

`WeeklyView` aggregation (pure function):
- Empty week → zero total each day.
- Multiple sessions same task → grouped under that task per day.
- Daily totals sum correctly.
- Friday-to-Thursday window correct around week boundaries.

**SwiftUI previews** for popover states: stopped, running, with today's entries, with week expanded, with error banner.

**Manual smoke test before shipping:**
- Start, wait 30 sec, Stop → entry in today's JSON file.
- Start task A, type task B + Return → two entries, no gap.
- Force-quit while running, relaunch → still running with original start time.
- Set auto-stop to 1 min in the future, leave running → stops at that minute.
- Restart Mac while running → resumes on next launch.

**Not tested:**
- `MenuBarExtra` rendering (Apple's, not ours).
- File permissions outside Application Support.

## Tech stack

- **Language:** Swift 5.9+
- **UI:** SwiftUI with `MenuBarExtra` (macOS 13 Ventura minimum)
- **Persistence:** `Foundation` `JSONEncoder` / `JSONDecoder` to flat files; `UserDefaults` for preferences
- **Tests:** XCTest
- **Build:** Xcode project (single app target + single test target). No external dependencies.

## App bundle

- **Display name:** `Timesheet Tracker`
- **Bundle identifier:** `com.anthonytoci.TimesheetTracker`
- **Info.plist `LSUIElement`:** `true` (menu-bar-agent app — no Dock icon, doesn't appear in Cmd+Tab)
- **Minimum deployment target:** macOS 13.0
- **Signing:** local development signing only (no notarisation in v1; user runs from `/Applications` or anywhere).

## Out of scope for v1 (possible later)

- Global hotkey to open popover or start/stop.
- Editing past entries in the UI.
- CSV export.
- Tags / projects / clients as separate fields.
- Reporting beyond 7-day view.
- iCloud sync.
