import AppKit

/// Local ⌘1 monitor. SwiftUI's `.keyboardShortcut` matches on character, so it
/// misses the numeric-keypad 1; a key-code monitor catches both.
@MainActor
final class HotkeyMonitor {

    /// Carbon `kVK_ANSI_1` and `kVK_ANSI_Keypad1`.
    private static let mainRowOne: UInt16 = 18
    private static let keypadOne: UInt16 = 83

    private var monitor: Any?

    func start(action: @escaping @MainActor () -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Self.matches(event) else { return event }
            MainActor.assumeIsolated { action() }
            return nil   // consume, so macOS doesn't beep
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Keypad keys carry `.numericPad` alongside `.command`, so accept either
    /// exactly ⌘ or ⌘ + numeric pad — but nothing else.
    static func matches(_ event: NSEvent) -> Bool {
        guard event.keyCode == mainRowOne || event.keyCode == keypadOne else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == .command || flags == [.command, .numericPad]
    }
}
