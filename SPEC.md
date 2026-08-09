# FlipClock — v1 Spec

## Product

A lightweight macOS desktop flip clock. The clock face is the entire app: hours and minutes as large split-flap digits.

## Requirements

### Clock display
- Split-flap ("flip clock") style hours and minutes, e.g. `10:07`, with a flip animation when a digit changes.
- 12-hour display with a small AM/PM indicator (unobtrusive); seconds are not shown.
- Digits use a monospaced/tabular look so the layout doesn't jitter.

### Window
- Freely resizable; clock scales proportionally to fill the window.
- Sensible minimum size; window frame persists across launches.
- Clean look: hidden/minimal title bar, dark clock-card styling.

### Always-on-top
- `⌘1` toggles the window between normal level and floating (above all windows).
- Must work with both the main-row `1` and the numeric-keypad `1`.
- In-app shortcut is sufficient for v1 (app focused). Subtle visual indicator of the pinned state (e.g. small pin glyph).
- Also toggleable from the app menu.

### Spoken time announcements
- Speaks the current time aloud, e.g. "10:07 PM", exactly when the minute ticks over.
- Cadence setting: Off (default) / Every hour (on the hour) / Every 15 minutes / Custom every N minutes (N = 1–180, announced when minute % N == 0, anchored to the hour).
- Settings persist via UserDefaults (@AppStorage). Accessible from a small settings UI (menu or gear popover).

### Architecture notes
- SwiftPM executable target, packaged into `dist/FlipClock.app` by `scripts/build-app.sh` (no Xcode required, ad-hoc codesigned if needed).
- Keep state in a small observable model (`ClockModel`) ticking on minute boundaries; announcements driven by the same tick.
- Design for a future sync layer: settings/state mutations go through the model, not scattered view code, so a cloud-sync backend can be attached later. No networking in v1.

## Out of scope (v1)
- To-do list, cloud sync, global (unfocused) hotkey, login item, sandboxing/notarization.
