import AppKit

/// Local key-down monitor for the app's in-window shortcuts. SwiftUI's
/// `.keyboardShortcut` matches on character, so it misses the numeric-keypad 1
/// and can't bind a bare spacebar at all; a key-code monitor catches both.
@MainActor
final class HotkeyMonitor {

    /// Carbon `kVK_ANSI_1`, `kVK_ANSI_Keypad1`, `kVK_ANSI_2`,
    /// `kVK_ANSI_Keypad2`, `kVK_Space`.
    private static let mainRowOne: UInt16 = 18
    private static let keypadOne: UInt16 = 83
    private static let mainRowTwo: UInt16 = 19
    private static let keypadTwo: UInt16 = 84
    private static let space: UInt16 = 49

    private var monitor: Any?

    /// - Parameters:
    ///   - toggleAlwaysOnTop: fired by ⌘1 (main row or keypad).
    ///   - cycleEventsPlacement: fired by ⌘2 (main row or keypad).
    ///   - speakTime: fired by an unmodified spacebar press.
    func start(
        toggleAlwaysOnTop: @escaping @MainActor () -> Void,
        cycleEventsPlacement: @escaping @MainActor () -> Void,
        speakTime: @escaping @MainActor () -> Void
    ) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // `NSEvent` isn't Sendable, so the isolated block yields a plain
            // Bool and the event is returned (or swallowed) out here.
            let handled = MainActor.assumeIsolated { () -> Bool in
                if Self.matchesAlwaysOnTop(event) {
                    toggleAlwaysOnTop()
                    return true
                }
                if Self.matchesCycleEvents(event) {
                    cycleEventsPlacement()
                    return true
                }
                if Self.matchesSpeakTime(event), !Self.isEditingText() {
                    speakTime()
                    return true
                }
                return false
            }
            return handled ? nil : event   // consume, so macOS doesn't beep
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Keypad keys carry `.numericPad` alongside `.command`, so accept either
    /// exactly ⌘ or ⌘ + numeric pad — but nothing else.
    static func matchesAlwaysOnTop(_ event: NSEvent) -> Bool {
        guard event.keyCode == mainRowOne || event.keyCode == keypadOne else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == .command || flags == [.command, .numericPad]
    }

    /// ⌘2, main row or keypad — same modifier rules as ⌘1.
    static func matchesCycleEvents(_ event: NSEvent) -> Bool {
        guard event.keyCode == mainRowTwo || event.keyCode == keypadTwo else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == .command || flags == [.command, .numericPad]
    }

    /// Bare spacebar. Command/Option/Control-space belong to menus, Spotlight
    /// and input-source switching, so those pass straight through; shift and
    /// caps lock are harmless and ignored.
    static func matchesSpeakTime(_ event: NSEvent) -> Bool {
        guard event.keyCode == space else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.isDisjoint(with: [.command, .option, .control, .function])
    }

    /// Space is a legitimate character while typing, so never hijack it from a
    /// text editor. Nothing in the UI is text-editable today; this keeps a
    /// future field from losing its spacebar.
    static func isEditingText() -> Bool {
        let responder = NSApp.keyWindow?.firstResponder
        return responder is NSTextView || responder is NSTextField
    }
}
