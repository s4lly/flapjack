# Flapjack

A lightweight macOS flip clock.

## Features

- Classic split-flap clock showing hours and minutes, prominently.
- Freely resizable window — the clock scales to fit, and rearranges itself to `HH` stacked over `MM` (dot separator between) whenever that makes the digits bigger than `HH:MM` across.
- **⌘1** (main row or numeric keypad) toggles always-on-top (window floats above all other windows).
- Spoken time announcements ("ten oh-seven PM") with configurable cadence:
  - every hour
  - every 15 minutes
  - custom minute interval
  - off
- A **cadence countdown fill** behind the clock: a warm amber panel that fills the face when the time is announced and then drains right to left as the next announcement approaches, so the wait is visible at a glance. Only shown when a cadence is set; switch it off with "Show cadence fill" in Settings.
- Today's remaining calendar events beside the clock (EventKit — any account synced to macOS Calendar). **⌘2** (main row or numeric keypad) cycles the panel off → right column → below the clock; the clock rescales to the space that's left. Calendar access is asked for only when you first turn the panel on.
- **Spacebar** speaks the current time on demand (app focused) — works even with the cadence set to off. Also in the menu as "Speak Time".

Planned: cloud sync between the desktop app and a web backend (future to-do list and other features will build on it).

## Installing (Homebrew)

```sh
brew tap s4lly/tap
brew trust s4lly/tap   # newer Homebrew requires trusting third-party taps once
brew install --cask flapjack
# ad-hoc signed, not notarized — clear Gatekeeper quarantine once:
xattr -dr com.apple.quarantine /Applications/Flapjack.app
```

Future versions arrive with `brew upgrade`. Releasing a new version (maintainer): `./scripts/release.sh <version>` — builds, publishes the GitHub release, and updates the [tap](https://github.com/s4lly/homebrew-tap).

## Building

Requires macOS with Swift (Command Line Tools are enough — no Xcode needed).

```sh
./scripts/build-app.sh
open dist/Flapjack.app
```

Running the unit tests needs a full Xcode (the Command Line Tools ship no test framework):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```
