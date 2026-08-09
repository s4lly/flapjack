# FlipClock

A lightweight macOS flip clock.

## Features

- Classic split-flap clock showing hours and minutes, prominently.
- Freely resizable window — the clock scales to fit.
- **⌘1** (main row or numeric keypad) toggles always-on-top (window floats above all other windows).
- Spoken time announcements ("ten oh-seven PM") with configurable cadence:
  - every hour
  - every 15 minutes
  - custom minute interval
  - off

Planned: cloud sync between the desktop app and a web backend (future to-do list and other features will build on it).

## Building

Requires macOS with Swift (Command Line Tools are enough — no Xcode needed).

```sh
./scripts/build-app.sh
open dist/FlipClock.app
```
