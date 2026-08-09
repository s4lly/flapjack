import SwiftUI

@main
struct FlipClockApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var engine = ClockEngine()
    @StateObject private var windows = WindowController()

    private let announcer = Announcer()
    private let hotkeys = HotkeyMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(engine)
                .environmentObject(windows)
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
                guard settings.shouldAnnounce(at: date) else { return }
                announcer.announce(date)
            }
        }
        engine.start()
        // Spacebar speaks on demand regardless of the cadence setting — it's a
        // "what time is it?" trigger, not an announcement.
        hotkeys.start(
            toggleAlwaysOnTop: { settings.toggleAlwaysOnTop() },
            speakTime: { announcer.announce(Date()) }
        )
    }
}
