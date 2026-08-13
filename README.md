# Flapjack

A lightweight macOS flip clock.

## Features

- Classic split-flap clock showing hours and minutes, prominently.
- Freely resizable window — the clock scales to fit, and rearranges itself to `HH` stacked over `MM` (dot separator between) whenever that makes the digits bigger than `HH:MM` across.
- **⌘1** (main row or numeric keypad) toggles always-on-top (window floats above all other windows).
- Time announcements on a configurable cadence:
  - every hour
  - every 15 minutes
  - custom minute interval
  - off
- **Three ways to be told, each switchable on its own** — the "Convey with" toggles in Settings. **Voice** speaks the time aloud ("ten oh-seven PM"); **Notification** posts it as a macOS notification; **Airplane banner** sends a little plane towing the time across your screen. Turn on any, all, or none. Notifications are off until you ask for them — flipping the toggle on is what requests permission.
- **Airplane banner** (off by default): at each cadence tick a plane tows a banner reading the time across whichever desktop you're looking at — over your windows, the Dock and the menu bar — from a random side at a random height, once, in about seven seconds, and then it's gone. It's a ghost: clicks go straight through it, there's nothing to dismiss. The **Preview** button in Settings sends one across right now. One thing macOS won't allow: while another app is in native full screen, the plane can't be shown on that Space, so a tick that lands there passes unseen.
  - Each time check replaces the last, so Notification Center never fills up with stale ones.
  - Whether the notification lingers until you dismiss it or fades after a few seconds is **your** setting, not the app's: **System Settings → Notifications → Flapjack → Alert Style**, "Persistent" vs "Temporary" (called "Alerts" and "Banners" before macOS 26). Settings has a button that takes you straight to that pane.
- **Voice picker** in Settings, with a **Test** button to hear the current time straight away. "Automatic" uses the best voice installed on your Mac.
  - Macs ship with only *compact* voices, which sound robotic. For much better audio, download an enhanced or premium voice — **System Settings → Accessibility → Spoken Content** (called **Read & Speak** on macOS 26) **→ System Voice → Manage Voices**; Ava and Zoe are the best for US English. Settings offers an "Open System Settings…" button that takes you straight there whenever nothing better than a compact voice is installed. New voices show up in the picker as soon as the download finishes — no restart.
- **Turn the music down while it speaks** — "Lower other apps' audio while speaking" in Settings (off by default). Spotify's or Music's volume ramps down to a quarter, the time is spoken, and the volume goes straight back to exactly where it was.
  - macOS asks your permission to control each player the first time — that prompt is why the setting starts off rather than on. If you say no by mistake, Settings shows a button straight to **System Settings → Privacy & Security → Automation**.
  - It only works for players macOS can script, which in practice means Spotify and Music. Audio from a browser tab, a game or a video call **cannot** be lowered — macOS has no per-app volume control for third-party apps, and no way to duck other audio the way iOS does.
  - Paused players are left alone, and a player that isn't already running is never launched.
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
