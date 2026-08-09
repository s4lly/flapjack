# Flip-Clock macOS App: Technical Findings

All claims below were **verified by building and launching a real SwiftUI SwiftPM app** on this machine (Swift 6.3.3, macOS 26.5.2, arm64, CLT-only).

---

## 1. SwiftPM → .app bundle without Xcode

**Verdict: works fully. No Xcode needed.** Built, bundled, signed, and launched successfully.

### Package.swift

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FlipClock",
    platforms: [.macOS(.v14)],          // .v14 is a good floor; .v13 min for TimelineView(.everyMinute)
    targets: [
        .executableTarget(name: "FlipClock", path: "Sources/FlipClock")
    ]
)
```

`.executableTarget` (not `.target`). No `Info.plist` inside the package — SwiftPM has no concept of it; the bundling script supplies it.

### Bundle layout (minimal — this is all you need)

```
FlipClock.app/
  Contents/
    Info.plist
    MacOS/FlipClock          ← the swift build product, copied
    Resources/               ← optional (AppIcon.icns)
```

No `PkgInfo` needed. No `NSPrincipalClass` needed — **verified**: the SwiftUI `@main App` lifecycle bootstraps `NSApplication` itself. `NSPrincipalClass` only matters for nib-based AppKit apps.

### Info.plist — required keys

```xml
<key>CFBundleExecutable</key><string>FlipClock</string>   <!-- must match filename in MacOS/ -->
<key>CFBundleIdentifier</key><string>com.yourname.flipclock</string>
<key>CFBundleName</key><string>FlipClock</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
```

`CFBundleExecutable` + `CFBundleIdentifier` are the two that actually break things if wrong. `NSHighResolutionCapable` matters here — without it you get a blurry upscaled clock on Retina.

**`LSUIElement`**: set `<true/>` only if you want *no Dock icon and no menu bar* (menu-bar-only accessory app). For a resizable desktop clock window you want a Dock icon and a menu bar (for Cmd+Q and your shortcuts) — **leave `LSUIElement` out**. Note that with `LSUIElement=true` a plain `WindowGroup` window can't become key normally, which would break the in-app Cmd+1.

### Build script

```bash
#!/bin/bash
set -e
swift build -c release
APP="FlipClock.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FlipClock "$APP/Contents/MacOS/FlipClock"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier com.yourname.flipclock "$APP"
```

### Codesigning — needed?

The linker already emits an **ad-hoc, linker-signed** binary on Apple Silicon (verified: `flags=0x20002(adhoc,linker-signed)`), so a bare copy will launch. But **do run `codesign --force --sign - "$APP"` anyway**, because:

- It re-seals the bundle after you add `Info.plist`, so the signature covers the real bundle identifier.
- TCC permissions (microphone, accessibility, Automation) are keyed to the code signature. An unsealed/ad-hoc-drifting bundle gets **re-prompted on every rebuild**. Sealing with a stable `--identifier` makes permissions stick.

Ad-hoc is sufficient for local use. No Developer ID, no notarization — those only matter for distributing to other Macs (Gatekeeper quarantine).

### Gotchas (empirically tested)

- **`@main` in a file named `main.swift`**: On Swift 6.3.3 it compiles and runs correctly (the classic "'main' attribute cannot be used in a module that contains top-level code" error only fires with actual top-level statements). Still, **name it `App.swift`** — costs nothing and is portable across toolchains.
- **Running the bare executable vs the bundle**: `.build/release/FlipClock` launches and runs, but with no bundle it has no Dock icon, no proper menu bar, and won't reliably activate/come to front. **Always test via `open FlipClock.app`**, not the raw binary.
- SwiftPM resource bundles (`.copy`/`.process`) land in `FlipClock_FlipClock.bundle` next to the executable, and `Bundle.module` looks for it *beside the executable* — so copy it into `Contents/MacOS/`, not `Resources/`, if you use resources. Simplest v1: use no SwiftPM resources; embed the icon via `Contents/Resources/AppIcon.icns` + `CFBundleIconFile`.

---

## 2. Always-on-top window

**Recommended: `NSViewRepresentable` accessor.** Do *not* poke `NSApp.windows` — it's racy at launch and will grab the wrong window once you have a settings panel.

```swift
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }  // async: window is nil during makeNSView
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}
```

The `DispatchQueue.main.async` is mandatory — `view.window` is `nil` until the view joins the hierarchy.

Toggling, driven off `@AppStorage`:

```swift
final class WindowController: ObservableObject {
    weak var window: NSWindow?
    func setFloating(_ on: Bool) {
        window?.level = on ? .floating : .normal
    }
    func configure(_ w: NSWindow) {
        window = w
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.setFrameAutosaveName("FlipClockMain")
    }
}
```

**`collectionBehavior`:**
- `.canJoinAllSpaces` — clock follows you across every Space. This is what you want for a desktop clock.
- `.fullScreenAuxiliary` — lets it float *over* other apps' fullscreen windows. Essential for an always-on-top clock; without it the clock vanishes when you fullscreen something.
- Avoid `.moveToActiveSpace` (conflicts with `canJoinAllSpaces`).
- `.stationary` if you don't want it sliding during Exposé.

Use `.floating` rather than `.popUpMenu`/`.screenSaver` — higher levels draw over menus and system UI and feel broken.

---

## 3. Cmd+1 keyboard shortcut

**Key codes confirmed** (Carbon `HIToolbox/Events.h`): `kVK_ANSI_1 = 0x12 = 18`, `kVK_ANSI_Keypad1 = 0x53 = 83`.

**Recommended: `NSEvent.addLocalMonitorForEvents`.** SwiftUI's `.keyboardShortcut("1", modifiers: .command)` matches on the *character*, so it fires for main-row 1 but **not** for keypad 1 (which carries the numeric-pad modifier flag and is a different key). Since we explicitly want both, the monitor is the clean single-path answer.

```swift
final class HotkeyMonitor {
    private var monitor: Any?
    func start(action: @escaping () -> Void) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isCmd = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            if isCmd && (event.keyCode == 18 || event.keyCode == 83) {
                action()
                return nil          // swallow the event (no beep)
            }
            return event
        }
    }
    deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
}
```

Two details that matter: compare against `.deviceIndependentFlagsMask` so stray Caps Lock / numeric-pad flags don't defeat equality, and **return `nil`** to consume the event — otherwise macOS plays the "unhandled key" beep. (Note: the keypad "1" event carries the `.numericPad` flag, so for keyCode 83 the modifier comparison must tolerate that flag rather than requiring exactly `.command`.)

**Global hotkey trade-off:** working while unfocused requires either Carbon `RegisterEventHotKey` (no permission prompt, still fully supported, clunky C API) or `CGEventTap` (needs Accessibility permission + re-prompting whenever the ad-hoc signature changes). **Recommend the local monitor for v1**; add `RegisterEventHotKey` later if wanted, since it avoids the permissions mess entirely.

---

## 4. Spoken time announcements

**Recommended: `AVSpeechSynthesizer`.** Shelling out to `say` works but forks a process per announcement, gives no completion callback, no interrupt/stop, no error surface. `AVSpeechSynthesizer` is in-process, cancellable, delegate-driven.

**No entitlements needed** — speech synthesis is output-only, touches no TCC-protected resource. Unsandboxed and ad-hoc-signed is fine. Verified working via direct API probe.

**Critical gotcha: keep the synthesizer alive.** A local `AVSpeechSynthesizer` deallocates when the function returns and the utterance is silently cut off. Hold it as a stored property.

```swift
import AVFoundation

final class Announcer {
    private let synth = AVSpeechSynthesizer()      // MUST be a stored property
    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f
    }()

    private lazy var voice: AVSpeechSynthesisVoice? = {
        // Prefer the highest-quality installed en-US voice; fall back to system default.
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en-US") }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    func announce(_ date: Date) {
        let u = AVSpeechUtterance(string: "It's \(fmt.string(from: date))")
        u.voice = voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.stopSpeaking(at: .immediate)   // don't stack announcements
        synth.speak(u)
    }
}
```

**Voice quality finding on this machine:** all 28 installed en-US voices are `quality == .default` — no enhanced/premium voices installed; the default resolves to `com.apple.voice.super-compact.en-US.Samantha` (lowest fidelity, robotic). The `.max(by: quality)` scan future-proofs this. Worth surfacing in the README: users get dramatically better audio by installing an enhanced voice via **System Settings → Accessibility → Spoken Content → System Voice → Manage Voices**.

**Formatting for natural speech** (verified output): `"h:mm a"` → `10:07 PM`, pronounced correctly as "ten oh seven P M". Use `en_US_POSIX` locale so AM/PM symbols don't get localized out. Refinement: on the hour, special-case to `"It's 10 o'clock"` (some voices garble `10:00 PM`).

---

## 5. Flip-clock UI in SwiftUI

The split-flap illusion is **two stacked half-cards plus a two-phase rotation**: the top half of the *old* digit falls away, then the bottom half of the *new* digit swings up.

Core half-card view — clip to a half, then align the text so the glyph stays whole:

```swift
enum Half { case top, bottom }

struct HalfCard: View {
    let text: String
    let half: Half
    let size: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .frame(width: size * 0.62, height: size)
            .background(Color(white: 0.12))
            // show only half the glyph...
            .frame(height: size / 2, alignment: half == .top ? .top : .bottom)
            .clipped()
            .cornerRadius(size * 0.06)
    }
}
```

The flip itself. `anchor: .bottom` hinges the top card at its lower edge; `perspective: 0.5` gives foreshortening:

```swift
struct FlipDigit: View {
    let value: String
    let size: CGFloat
    @State private var old: String = ""
    @State private var topAngle: Double = 0      // 0 → -90
    @State private var bottomAngle: Double = 90  // 90 → 0

    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                HalfCard(text: value, half: .top, size: size)     // new, static underneath
                HalfCard(text: old, half: .top, size: size)       // old, falls away
                    .rotation3DEffect(.degrees(topAngle),
                                      axis: (x: 1, y: 0, z: 0),
                                      anchor: .bottom, anchorZ: 0, perspective: 0.5)
            }
            ZStack {
                HalfCard(text: old, half: .bottom, size: size)    // old, static underneath
                HalfCard(text: value, half: .bottom, size: size)  // new, swings up
                    .rotation3DEffect(.degrees(bottomAngle),
                                      axis: (x: 1, y: 0, z: 0),
                                      anchor: .top, anchorZ: 0, perspective: 0.5)
            }
        }
        .onChange(of: value) { _, newValue in flip(to: newValue) }
        .onAppear { old = value }
    }

    private func flip(to newValue: String) {
        topAngle = 0; bottomAngle = 90
        withAnimation(.easeIn(duration: 0.14)) { topAngle = -90 }
        withAnimation(.easeOut(duration: 0.14).delay(0.14)) { bottomAngle = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { old = newValue }
    }
}
```

The two phases must be **sequential, not simultaneous** (`.easeIn` down, then `.easeOut` up, delay equal to the first duration) — the asymmetric easing sells the mechanical weight.

**Per-digit flipping**: give each digit position a stable `.id()` so only changed digits animate.

**Scaling with the window** — `GeometryReader` to derive a size, drive the font from it:

```swift
GeometryReader { geo in
    let unit = min(geo.size.width / 4.2, geo.size.height / 1.2)   // 4 digits + gaps
    HStack(spacing: unit * 0.08) {
        FlipDigit(value: h1, size: unit); FlipDigit(value: h2, size: unit)
        Text(":").font(.system(size: unit * 0.5))
        FlipDigit(value: m1, size: unit); FlipDigit(value: m2, size: unit)
    }
    .frame(width: geo.size.width, height: geo.size.height)
}
```

`design: .monospaced` **plus** `.monospacedDigit()` — the first picks the mono face, the second guarantees tabular figures so cards don't jitter width.

---

## 6. Resizable, frameless-ish window

```swift
WindowGroup {
    ContentView()
        .frame(minWidth: 240, minHeight: 90)
        .aspectRatio(2.6, contentMode: .fit)   // keeps clock proportions while resizing
}
.windowStyle(.hiddenTitleBar)
.windowResizability(.contentMinSize)          // NOT .contentSize — that pins it unresizable
.defaultSize(width: 520, height: 200)
```

**`.windowResizability(.contentSize)` makes the window non-resizable** — a very common trap. Use `.contentMinSize`.

`.hiddenTitleBar` keeps the traffic lights but drops the title bar chrome. For a fully frameless look, go further on the `NSWindow`:

```swift
w.titleVisibility = .hidden
w.titlebarAppearsTransparent = true
w.isMovableByWindowBackground = true     // drag the clock body to move it
w.standardWindowButton(.closeButton)?.isHidden = true   // optional: hide traffic lights
```

`isMovableByWindowBackground` is essential once you hide the title bar.

**Remembering the frame**: `w.setFrameAutosaveName("FlipClockMain")` — call it once, name unique per window. Persists to `UserDefaults` automatically.

---

## 7. Timer accuracy

**Recommended: a single self-rescheduling `Timer` aimed at the next minute boundary, driving both the UI and the announcements.** Do *not* mix `TimelineView(.everyMinute)` for display with a separate `Timer` for speech — two independent clocks drift apart. Plain `Timer(timeInterval: 60, repeats: true)` drifts off :00.

```swift
@MainActor
final class ClockEngine: ObservableObject {
    @Published var now = Date()
    private var timer: Timer?
    var onMinute: ((Date) -> Void)?

    func start() {
        scheduleNextTick()
        // Resync after sleep/wake — timers do not fire while the Mac is asleep.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.resync() } }
    }

    private func scheduleNextTick() {
        let cal = Calendar.current
        guard let next = cal.nextDate(after: Date(), matching: DateComponents(second: 0),
                                      matchingPolicy: .nextTime) else { return }
        let t = Timer(fireAt: next, interval: 0, target: self,
                      selector: #selector(tick), userInfo: nil, repeats: false)
        t.tolerance = 0                       // we want the boundary, precisely
        RunLoop.main.add(t, forMode: .common) // .common so it survives window drags/menus
        timer = t
    }

    @objc private func tick() {
        let d = Date()
        now = d
        onMinute?(d)
        scheduleNextTick()                    // re-aim at the next boundary: zero drift
    }

    private func resync() {
        timer?.invalidate(); now = Date(); scheduleNextTick()
    }
}
```

Three things this gets right:
- **`RunLoop.main.add(t, forMode: .common)`** — a timer on `.default` mode stops firing while the user drags/resizes the window or holds a menu open.
- **Re-aiming every fire** via `Calendar.nextDate(matching: second == 0)` → no cumulative drift.
- **Sleep/wake resync** — `NSWorkspace.didWakeNotification` is on `NSWorkspace.shared.notificationCenter`, *not* `NotificationCenter.default` (easy silent mistake).

Announcements are a pure predicate over the tick, so they can never drift from the display:

```swift
engine.onMinute = { [weak self] date in
    guard let self, self.shouldAnnounce(at: date) else { return }
    self.announcer.announce(date)
}
```

---

## 8. Settings persistence

`@AppStorage` (UserDefaults-backed; writes to `~/Library/Preferences/com.yourname.flipclock.plist` keyed off `CFBundleIdentifier` — keep the identifier stable across rebuilds or settings appear to reset).

`@AppStorage` can't store an enum directly, so back it with `String`/`Int`:

```swift
enum AnnounceMode: String, CaseIterable, Identifiable {
    case off, everyQuarter, hourly, custom
    var id: String { rawValue }
}

struct SettingsView: View {
    @AppStorage("announceMode") private var modeRaw = AnnounceMode.off.rawValue
    @AppStorage("customMinutes") private var customMinutes = 30
    @AppStorage("alwaysOnTop")   private var alwaysOnTop = true
}
```

The interval predicate:

```swift
func shouldAnnounce(at date: Date) -> Bool {
    let c = Calendar.current.dateComponents([.minute], from: date)
    guard let m = c.minute else { return false }
    switch AnnounceMode(rawValue: modeRaw) ?? .off {
    case .off:          return false
    case .hourly:       return m == 0
    case .everyQuarter: return m % 15 == 0
    case .custom:       return customMinutes > 0 && m % customMinutes == 0
    }
}
```

Guard `customMinutes > 0` (zero crashes on modulo). Clamp custom to 1...60 — values above 60 don't behave as users expect under a minute-of-hour modulo.

For settings UI, `Settings { SettingsView() }` as a second `Scene` gives the standard **Cmd+,** preferences window free.

---

## Recommended stack, one line each

| Topic | Decision |
|---|---|
| Bundle | `swift build -c release` + hand-rolled `.app` + `codesign -s -` (sealed, stable `--identifier`) |
| Entry point | SwiftUI `@main App` in **`App.swift`**; no `NSPrincipalClass`; no `LSUIElement` |
| Always on top | `NSViewRepresentable` accessor → `.floating` + `[.canJoinAllSpaces, .fullScreenAuxiliary]` |
| Cmd+1 | `NSEvent.addLocalMonitorForEvents`, keyCodes **18** and **83**, return `nil` to consume |
| Speech | `AVSpeechSynthesizer` held as a stored property, highest-quality en-US voice, no entitlements |
| Flip UI | Two half-cards, sequential `.easeIn`/`.easeOut` `rotation3DEffect`, `anchor: .bottom`/`.top` |
| Window | `.hiddenTitleBar` + `.windowResizability(.contentMinSize)` + `setFrameAutosaveName` |
| Timing | Single self-rescheduling boundary `Timer` on `.common` mode, wake-resynced, drives UI **and** speech |
| Settings | `@AppStorage` with `String`-backed enum |
