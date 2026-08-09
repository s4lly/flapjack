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

    func configure(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window

        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.black
        window.minSize = NSSize(width: 280, height: 130)
        window.setFrameAutosaveName("FlipClockMain")
    }

    func setFloating(_ on: Bool) {
        window?.level = on ? .floating : .normal
    }
}
