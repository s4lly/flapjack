import SwiftUI
import AppKit

/// The draggable seam between the clock face and the events panel.
///
/// It reports a *panel extent in points* rather than a fraction: the drag is a
/// physical thing the user does in points, and letting the caller convert (and
/// clamp) keeps the geometry knowledge in one place — `EventsPanelMetrics`.
/// The panel always sits on the trailing/bottom side of the seam, so dragging
/// toward the panel shrinks it, which is why the delta is subtracted.
struct SplitDivider: View {

    /// Which way the seam runs. `.vertical` is a vertical hairline dragged
    /// left/right (column placement); `.horizontal` a horizontal one dragged
    /// up/down (below placement).
    enum Seam {
        case vertical
        case horizontal

        var cursor: NSCursor {
            self == .vertical ? .resizeLeftRight : .resizeUpDown
        }
    }

    let seam: Seam
    /// The panel's current extent in points, read when a drag begins so the
    /// gesture's translation has something to be relative to.
    let extent: () -> CGFloat
    /// Called live as the seam moves, with the panel's wanted extent in points.
    let onMove: (CGFloat) -> Void

    @State private var hovering = false
    @State private var dragging = false

    // PROTOTYPE — see FaceStylePrototype.swift. White-on-black hairline and
    // grip vanish entirely on a pastel ground; the colourway supplies both.
    @Environment(\.eventsColors) private var colors

    private var thickness: CGFloat { EventsPanelMetrics.dividerThickness }
    private var active: Bool { hovering || dragging }

    var body: some View {
        ZStack {
            line
            grip
        }
        .frame(width: seam == .vertical ? thickness : nil,
               height: seam == .vertical ? nil : thickness)
        // The hit area is the whole gutter, not just the hairline, so the seam
        // is grabbable without the user having to hunt for a single pixel.
        .overlay(
            DividerHandle(
                cursor: seam.cursor,
                onHover: { hovering = $0 },
                onDrag: { phase in
                    switch phase {
                    case .began:
                        dragging = true
                        return extent()
                    case .moved(let start, let translation):
                        let delta = seam == .vertical ? translation.width : translation.height
                        onMove(start - delta)
                        return nil
                    case .ended:
                        dragging = false
                        return nil
                    }
                }
            )
        )
        .accessibilityElement()
        .accessibilityLabel("Events panel divider")
        .accessibilityHint("Drag to resize the events panel")
    }

    private var line: some View {
        Rectangle()
            .fill(active ? colors.seamActive : colors.seam)
            .frame(width: seam == .vertical ? 1 : nil,
                   height: seam == .vertical ? nil : 1)
            .animation(.easeOut(duration: 0.12), value: active)
    }

    /// Three dots at the centre of the seam: enough to read as a handle at a
    /// glance, quiet enough to disappear into the face when it isn't wanted.
    private var grip: some View {
        let dot: CGFloat = 2.5
        let dots = ForEach(0..<3, id: \.self) { _ in
            Circle()
                .fill(active ? colors.gripActive : colors.grip)
                .frame(width: dot, height: dot)
        }

        return Group {
            if seam == .vertical {
                VStack(spacing: 3) { dots }
            } else {
                HStack(spacing: 3) { dots }
            }
        }
        .animation(.easeOut(duration: 0.12), value: active)
    }
}

/// The seam's mouse handling, in AppKit rather than a SwiftUI `DragGesture`.
///
/// The window is `isMovableByWindowBackground` — the whole face is a drag
/// handle — and AppKit decides that *before* SwiftUI sees the click, by asking
/// the hit-tested view. A SwiftUI gesture therefore loses every drag on the
/// seam to a window move; only a real `NSView` answering
/// `mouseDownCanMoveWindow = false` can claim it. Owning the mouse also lets
/// the cursor come from a cursor rect, which AppKit keeps correct through the
/// drag without any push/pop bookkeeping.
private struct DividerHandle: NSViewRepresentable {

    enum Phase {
        case began
        /// Extent the drag started from, and how far the mouse has moved since,
        /// in SwiftUI's top-left-origin sense.
        case moved(start: CGFloat, translation: CGSize)
        case ended
    }

    let cursor: NSCursor
    let onHover: (Bool) -> Void
    /// Returns the starting extent for `.began`; ignored for the other phases.
    let onDrag: (Phase) -> CGFloat?

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.apply(cursor: cursor, onHover: onHover, onDrag: onDrag)
        return view
    }

    func updateNSView(_ view: HandleView, context: Context) {
        view.apply(cursor: cursor, onHover: onHover, onDrag: onDrag)
    }

    final class HandleView: NSView {
        private var cursor: NSCursor = .arrow
        private var onHover: (Bool) -> Void = { _ in }
        private var onDrag: (Phase) -> CGFloat? = { _ in nil }

        private var dragStart: CGFloat?
        private var mouseOrigin: NSPoint = .zero

        func apply(cursor: NSCursor,
                   onHover: @escaping (Bool) -> Void,
                   onDrag: @escaping (Phase) -> CGFloat?) {
            let changed = self.cursor !== cursor
            self.cursor = cursor
            self.onHover = onHover
            self.onDrag = onDrag
            if changed { window?.invalidateCursorRects(for: self) }
        }

        override var mouseDownCanMoveWindow: Bool { false }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: cursor)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self))
        }

        override func mouseEntered(with event: NSEvent) { onHover(true) }

        override func mouseExited(with event: NSEvent) {
            // A drag that leaves the gutter is still a drag; the highlight only
            // drops when the pointer leaves and nothing is being dragged.
            if dragStart == nil { onHover(false) }
        }

        override func mouseDown(with event: NSEvent) {
            mouseOrigin = event.locationInWindow
            dragStart = onDrag(.began)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = dragStart else { return }
            let now = event.locationInWindow
            // AppKit's window space is bottom-left origin; flip y so callers can
            // think in the same direction SwiftUI lays out in.
            let translation = CGSize(width: now.x - mouseOrigin.x,
                                     height: mouseOrigin.y - now.y)
            _ = onDrag(.moved(start: start, translation: translation))
        }

        override func mouseUp(with event: NSEvent) {
            dragStart = nil
            _ = onDrag(.ended)
            let inside = bounds.contains(convert(event.locationInWindow, from: nil))
            onHover(inside)
        }
    }
}
