import AppKit
import SwiftUI

/// Hands the hosting `NSWindow` back once the view has joined the hierarchy.
/// (`view.window` is nil during `makeNSView`, hence the async hop.)
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Owns the main window's AppKit-level configuration.
@MainActor
final class WindowController: ObservableObject {
    private weak var window: NSWindow?

    /// Whether any part of the main window is actually on screen.
    ///
    /// AppKit's own answer, not an inference from activation: a window that is
    /// minimised, fully covered by another app's window, or on a Space the user
    /// has swiped away from is `.visible`-less, while an unfocused window in
    /// plain sight is still visible. Anything that animates continuously reads
    /// this and stops when it is false — a hidden window that keeps rendering
    /// is pure waste, and the countdown drain was measured burning 10% of a
    /// core while minimised.
    @Published private(set) var isVisible = true

    private var occlusionObserver: NSObjectProtocol?

    /// The window's background colour, which a transparent title bar shows
    /// through — so it is also the top edge of the app's bezel, and has to be
    /// the colourway's bezel colour. Held as state rather than set once because
    /// the window may not exist yet when the colourway is first resolved, and
    /// because the colourway can change while the app runs.
    private var chrome: NSColor?

    func configure(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window

        // Deliberately NOT `.canJoinAllSpaces`: the window stays on the Space it
        // was opened on, so swiping to another desktop leaves the clock behind.
        // `.fullScreenAuxiliary` only governs overlaying fullscreen windows, not
        // Space-following, so it stays — it keeps the floating clock visible over
        // a fullscreened app rather than vanishing.
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = chrome ?? NSColor.black
        window.minSize = NSSize(width: 280, height: 130)
        window.setFrameAutosaveName("FlapjackMain")

        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window, queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window else { return }
                self.setVisible(window.occlusionState.contains(.visible))
            }
        }
        setVisible(window.occlusionState.contains(.visible))
    }

    private func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        onVisible?(visible)
    }

    /// Fired when the window comes back into view, so the clock can correct
    /// itself before the user has finished looking at it.
    var onVisible: ((Bool) -> Void)?

    /// Paints the title-bar strip — the bezel's top run.
    func setChrome(_ color: NSColor) {
        guard chrome != color else { return }
        chrome = color
        window?.backgroundColor = color
    }

    func setFloating(_ on: Bool) {
        window?.level = on ? .floating : .normal
    }

    // `isolated` so the @MainActor-bound observer can be torn down safely
    // (required under the Swift 6 language mode).
    isolated deinit {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }
}
