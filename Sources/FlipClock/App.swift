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
        .defaultSize(width: 560, height: 220)
        .commands {
            CommandGroup(after: .toolbar) {
                Button(settings.alwaysOnTop ? "Turn Off Always on Top" : "Always on Top") {
                    settings.toggleAlwaysOnTop()
                }
                .keyboardShortcut("1", modifiers: .command)
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
        hotkeys.start { settings.toggleAlwaysOnTop() }
    }
}
