# FlipClock — v1 Spec

## Product

A lightweight macOS desktop flip clock. The clock face is the entire app: hours and minutes as large split-flap digits.

## Requirements

### Clock display
- Split-flap ("flip clock") style hours and minutes, e.g. `10:07`, with a flip animation when a digit changes.
- 12-hour display; seconds are not shown. The AM/PM indicator is a small, subtle badge tucked into the bottom-right corner of the last minute card — always in-card, never a column beside the digits. Keeping it out of the layout reserves the horizontal space for future features and lets the digits scale larger. It is included in the face's accessibility label, since it is visually small by design.
- Digits use a monospaced/tabular look so the layout doesn't jitter.

### Window
- Freely resizable; clock scales proportionally to fill the window.
- Sensible minimum size; window frame persists across launches.
- Clean look: hidden/minimal title bar, dark clock-card styling.

### Always-on-top
- `⌘1` toggles the window between normal level and floating (above all windows).
- The window does **not** follow the user across Spaces: it stays on the desktop where it lives, and floating applies only on that Space. Swiping to another desktop leaves the clock behind.
- Must work with both the main-row `1` and the numeric-keypad `1`.
- In-app shortcut is sufficient for v1 (app focused). Subtle visual indicator of the pinned state (e.g. small pin glyph).
- Also toggleable from the app menu.

### Spoken time announcements
- Speaks the current time aloud, e.g. "10:07 PM", exactly when the minute ticks over.
- Cadence setting: Off (default) / Every hour (on the hour) / Every 15 minutes / Custom every N minutes (N = 1–180, announced when minute % N == 0, anchored to the hour).
- Settings persist via UserDefaults (@AppStorage). Accessible from a small settings UI (menu or gear popover).
- On-demand: with the app focused, the **spacebar** speaks the current time immediately, independent of the cadence setting (it works even when cadence is Off). Presses carrying ⌘/⌥/⌃ pass through so menu and system shortcuts aren't shadowed, as do presses while a text field is being edited. Rapid taps restart the utterance rather than queueing. Also available as the "Speak Time" menu command.

### Architecture notes
- SwiftPM executable target, packaged into `dist/FlipClock.app` by `scripts/build-app.sh` (no Xcode required, ad-hoc codesigned if needed).
- Keep state in a small observable model (`ClockModel`) ticking on minute boundaries; announcements driven by the same tick.
- Design for a future sync layer: settings/state mutations go through the model, not scattered view code, so a cloud-sync backend can be attached later. No networking in v1.

## Out of scope (v1)
- To-do list, cloud sync, global (unfocused) hotkey, login item, sandboxing/notarization.
