import SwiftUI

/// The app's case: one continuous frame in the colourway's bezel colour around
/// all four edges of the window.
///
/// It is drawn *twice from one colour*. The top run is the window's own
/// `backgroundColor` — with `titlebarAppearsTransparent` the title-bar strip
/// shows it through, so the strip is the frame's top edge (see
/// `WindowController.setChrome`). This overlay runs the same colour down the
/// sides and along the bottom. The two meet with no seam at the corners because
/// they are the same value, and the ground is deliberately *not* extended into
/// the safe area, so nothing paints over the strip.
///
/// Being an overlay on the window root, it sits outside the face/divider/panel
/// split entirely: there is nothing for it to draw along the divider, which is
/// exactly the point — a frame that ran down the seam would be claiming to
/// enclose the clock while the window enclosed something bigger.
///
/// It does not react to the cadence. The bezel is the window's case, not part of
/// the countdown: dimming it when the cadence is off would leave the title-bar
/// strip a different colour from the sides, which is the seam this frame exists
/// to remove.
struct WindowBezel: View {
    let color: Color

    /// Bezel thickness in face units, so it holds its weight against the digits
    /// as the window grows, then clamped: below the floor it disappears on a
    /// small window, above the ceiling it crowds a large one. The units are
    /// chosen to land on 4 pt at the default window size.
    static let widthUnits: CGFloat = 0.023
    static let minWidth: CGFloat = 2
    static let maxWidth: CGFloat = 7

    /// Radius of the window's own rounded corners, which the frame's inner edge
    /// follows inward from.
    private static let windowCornerRadius: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let width = Self.width(in: geo.size)
            BezelFrameShape(inset: width,
                            cornerRadius: max(0, Self.windowCornerRadius - width))
                .fill(color, style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }

    /// The frame thickness for a window, never thick enough to swallow what it
    /// frames.
    static func width(in size: CGSize) -> CGFloat {
        let unit = FaceMetrics.unit(fitting: size)
        let scaled = min(max(unit * widthUnits, minWidth), maxWidth)
        return min(scaled, min(size.width, size.height) / 4)
    }
}

/// The frame itself: everything between the window's *square* outer bounds and
/// an inset rounded rect, filled with the even-odd rule.
///
/// Square on the outside is the whole point. Stroking the rounded rect instead
/// — `strokeBorder`, the obvious spelling — leaves the ground showing outside
/// each corner's curve, and at the window's edge that ground is a sliver between
/// the frame and the world outside the app, most visible at the bottom corners.
/// So the frame runs edge to edge and spends its thickness inwards, taking the
/// corner curve on its inner edge only, where it belongs — that curve is the
/// silhouette of the thing being framed.
struct BezelFrameShape: Shape {
    /// Distance from the outer edge to the inner cutout: the frame thickness
    /// along the straight runs.
    var inset: CGFloat
    /// Radius of the inner cutout.
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let hole = rect.insetBy(dx: inset, dy: inset)
        guard hole.width > 0, hole.height > 0 else { return path }
        path.addPath(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: hole)
        )
        return path
    }
}
