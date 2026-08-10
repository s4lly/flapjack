# Flapjack — v1 Spec

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
- **Cadence countdown fill**: while a cadence is set, a rounded panel sits behind the flip cards — a dark warm amber that reads as a lit ground against the black, well below the digits and cards in luminance so nothing on top of it loses contrast, and far enough from red not to be confused with the events timeline's now-line. It fills the face region completely the moment the clock speaks, then wipes away **left to right** linearly with the time remaining: the black ground is uncovered from the left and the surviving colour hugs the right edge, its width being the fraction of the wait still ahead (half the interval gone → right half still lit), vanishing off the right at the boundary. The refill sweeps back to full with a ~1.5 s ease-out so it swells rather than flashes. A `TimelineView` ticking once a second drives the wipe, since the face itself only changes once a minute. The panel keeps its full-size rounded silhouette and is revealed through a trailing-anchored mask, so the corners stay soft while the moving edge is a clean vertical cut — shrinking the shape itself would round the leading edge and read as a pill sliding away rather than a wipe. It lives inside the face's own region, so it never spills onto the events panel or the divider, and its corner radius scales with the face unit.
- Boundaries come from one pure value type, `CadenceSchedule`, which both the spoken announcement and the countdown read, so the two can never disagree. Boundaries are anchored to the top of the hour in every mode: a minute-of-hour is a boundary when it is a multiple of the step. That makes the top of the hour a boundary always, which matters when the step doesn't divide 60 — with N = 7 the boundaries are :00, :07 … :56 and then :00 of the next hour, so the final gap of the hour is 4 minutes, not 7. The countdown divides by the actual gap between the surrounding boundaries rather than by a nominal N, so the panel always starts full and always reaches empty.
- The fill is hidden with cadence Off (there is nothing to count down to) and can be switched off outright via the "Show cadence fill" setting (`showCadenceFill`, default on). The fraction is recomputed from the current settings on every tick, so changing the cadence retargets the countdown immediately. The spacebar's on-demand speech is deliberately outside the schedule and leaves the countdown untouched.
- On-demand: with the app focused, the **spacebar** speaks the current time immediately, independent of the cadence setting (it works even when cadence is Off). Presses carrying ⌘/⌥/⌃ pass through so menu and system shortcuts aren't shadowed, as do presses while a text field is being edited. Rapid taps restart the utterance rather than queueing. Also available as the "Speak Time" menu command.

### Events panel (EventKit)
- Shows today's remaining calendar events beside the clock. Strictly opt-in: placement is a three-state setting — Off (default) / Column (beside the face) / Below (under the face) — cycled Off → Column → Below → Off.
- Data comes from the macOS calendar store via EventKit, so any account the user has synced there is included (iCloud, Exchange, and Google via System Settings → Internet Accounts). Flapjack talks to no calendar service directly and does no networking.
- Access is requested only when the user first turns the panel on (Off → Column), never at launch. The three app-level states are not-determined / granted / denied; write-only and restricted count as denied, since neither can read events. Denied is surfaced to the UI so it can explain how to grant access in System Settings, rather than showing an empty list.
- The fetch window runs from "now" to the end of the current day, across all calendars. All-day events sort first, then everything else by start time.
- Refresh triggers: the existing minute tick (so past events drop off as the clock advances), `EKEventStoreChanged` notifications (edits made in Calendar or an account sync), and system wake — the clock engine exposes a resync hook separate from the minute tick, because a wake is not a minute boundary and must not trigger a spoken announcement. Refresh is skipped entirely while placement is Off or access isn't granted.
- Events reach the views as a plain `EventItem` value type (title, start/end, all-day flag, calendar name and colour). No EventKit type crosses into the UI, so a future backend-brokered event source can fill the same shape.
- `⌘2` (main row or numeric keypad) cycles the placement, and the View menu carries the same command with its current state in the title — "Events: Off" / "Events: Right Column" / "Events: Below" — since a cycling command can't show a checkmark honestly.
- A row is one line: a small per-calendar colour dot, the start time (locale short form with the AM/PM designator dropped — the panel only covers the rest of today — or "all-day"), then the title, truncated at the tail. Dim greys on black, matching the face: time in a tabular/monospaced grey, title slightly brighter. All type is scaled from a single unit derived from the panel's own size, so the panel stays legible whether the window is tiny or full-screen.
- Non-list states use the same dim hint style: empty is "No more events today", not-determined shows "Connecting…" (the access request is in flight, triggered by the cycle), and denied spells out "Calendar access needed — grant in System Settings → Privacy & Security → Calendars" in smaller, wrapping text.
- Column layout: a vertical day timeline on the trailing edge, scrollable vertically with hidden scroll indicators. Below layout: a horizontal day timeline under the face, scrollable horizontally.
- The split is the user's, not a fixed number: a **divider bar** sits on the seam — vertical in Column (dragged left/right), horizontal in Below (dragged up/down) — and drags the panel's share live, the face and the timeline both reflowing during the drag rather than on release. Two fractions persist independently, `eventsColumnFraction` (default 0.34) and `eventsBelowFraction` (default 0.30), written through `AppSettings` on every drag step so an unexpected quit keeps the split.
- The fraction is bounded to 0.15–0.5 — the face always keeps the larger half — and then clamped in points so both halves stay usable at the minimum window size: the panel floors at 120 pt (column) / 64 pt (strip) and the face keeps at least 150 pt wide / 50 pt tall, minus the 9 pt divider gutter. Because the stored value is a fraction, resizing the window reapplies the split proportionally.
- The divider reads as a hairline (white at 10% opacity) with a three-dot grip at its centre; the whole 9 pt gutter is the hit area, hovering or dragging lifts the line and dots to a brighter grey, and the pointer becomes the appropriate resize cursor over it. Its mouse handling is a real `NSView` (`SplitDivider`'s handle) answering `mouseDownCanMoveWindow = false` — the window is movable by its background, and AppKit decides that before SwiftUI sees the click, so a plain `DragGesture` would lose every drag to a window move.
- The panel's space is reserved before the face is measured: the face's unit is computed from the window minus the column's width (or the strip's height) and the divider gutter, keeping the existing ~3% margin, so the digits rescale as the divider moves. With placement Off the face gets the whole window exactly as it did before the panel existed, and in every mode the flip animation and the in-card AM/PM badge are untouched — the panel is a sibling of the face, never an overlay.

### Architecture notes
- SwiftPM executable target, packaged into `dist/Flapjack.app` by `scripts/build-app.sh` (no Xcode required, ad-hoc codesigned if needed).
- Keep state in a small observable model (`ClockModel`) ticking on minute boundaries; announcements driven by the same tick.
- Design for a future sync layer: settings/state mutations go through the model, not scattered view code, so a cloud-sync backend can be attached later. No networking in v1.

## Out of scope (v1)
- To-do list, cloud sync, global (unfocused) hotkey, login item, sandboxing/notarization.
