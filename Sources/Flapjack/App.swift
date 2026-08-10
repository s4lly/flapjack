import SwiftUI

@main
struct FlapjackApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var engine = ClockEngine()
    @StateObject private var windows = WindowController()
    @StateObject private var events = EventsService()

    private let announcer = Announcer()
    private let hotkeys = HotkeyMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(engine)
                .environmentObject(windows)
                .environmentObject(events)
                .onAppear(perform: bootstrap)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        // Matches the face's own aspect ratio (plus the title bar strip) so a
        // fresh window opens with the clock already filling it edge to edge.
        .defaultSize(width: 560, height: 190)
        .commands {
            CommandGroup(after: .toolbar) {
                Button(settings.alwaysOnTop ? "Turn Off Always on Top" : "Always on Top") {
                    settings.toggleAlwaysOnTop()
                }
                .keyboardShortcut("1", modifiers: .command)

                // Title carries the current state, since the command cycles
                // rather than toggles. The key equivalent covers the main-row
                // 2 only; HotkeyMonitor picks up the keypad one.
                Button(eventsMenuTitle) { cycleEventsPlacement() }
                    .keyboardShortcut("2", modifiers: .command)

                // Discoverability only — the bare-space binding lives in
                // HotkeyMonitor, since SwiftUI can't express an unmodified
                // spacebar shortcut here without stealing it from text fields.
                Button("Speak Time") { announcer.announce(Date()) }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }

    /// Wires the model layer together once the window exists.
    @MainActor
    private func bootstrap() {
        engine.onMinute = { date in
            MainActor.assumeIsolated {
                refreshEvents(at: date)
                guard settings.shouldAnnounce(at: date) else { return }
                announcer.announce(date)
            }
        }
        // Timers don't fire during sleep, so a wake can land far past the last
        // tick with a stale (or now-yesterday's) event list.
        engine.onResync = { date in
            MainActor.assumeIsolated { refreshEvents(at: date) }
        }
        engine.start()
        // A panel restored as visible needs access before its first fetch;
        // requestAccessIfNeeded is a no-op once the user has decided.
        if settings.eventsPlacement != .off {
            events.requestAccessIfNeeded()
        }
        refreshEvents(at: Date())
        // Spacebar speaks on demand regardless of the cadence setting — it's a
        // "what time is it?" trigger, not an announcement.
        hotkeys.start(
            toggleAlwaysOnTop: { settings.toggleAlwaysOnTop() },
            cycleEventsPlacement: { cycleEventsPlacement() },
            speakTime: { announcer.announce(Date()) }
        )
    }

    private var eventsMenuTitle: String {
        switch settings.eventsPlacement {
        case .off: return "Events: Off"
        case .column: return "Events: Right Column"
        case .below: return "Events: Below"
        }
    }

    /// Only fetches when the panel is actually visible and readable — a hidden
    /// panel shouldn't cost a calendar query every minute.
    @MainActor
    private func refreshEvents(at date: Date) {
        guard settings.eventsPlacement != .off, events.authorization == .granted else { return }
        events.refresh(now: date)
    }

    /// Placement changes live here rather than in `AppSettings` so that model
    /// stays pure state: turning the panel on is what triggers the permission
    /// prompt, and the first fetch.
    @MainActor
    private func cycleEventsPlacement() {
        settings.cycleEventsPlacement()
        guard settings.eventsPlacement != .off else { return }
        events.requestAccessIfNeeded()
        refreshEvents(at: Date())
    }
}
