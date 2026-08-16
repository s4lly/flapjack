import SwiftUI

/// The countdown backdrop: a framed track behind the flip cards whose lit fill
/// drains right to left as the next spoken announcement approaches, then sweeps
/// back to full when the clock speaks.
///
/// Three layers, drawn inside the face region and nowhere else:
///
/// - the **border**, an amber frame flush with the region's outer edge,
/// - the **track**, the fill's full extent at a faint brightness, and
/// - the **fill** itself, bright, draining inside the track.
///
/// The border and track exist to answer "how full is full": on its own a
/// half-drained fill gives no cue where its full extent ended, so the wipe reads
/// as an arbitrary block of colour rather than as progress. The frame supplies
/// the reference edge and the track supplies the unlit remainder.
///
/// It is driven by a `TimelineView` rather than the minute tick because the
/// wipe has to be continuous — the clock face only changes once a minute, but
/// the countdown needs to move visibly between minutes. The edge position is
/// linear in the time remaining, so the lit width reads directly as "how much
/// of the wait is left": half the interval gone, half the track still lit.
///
/// The wipe uncovers the ground from the *right*, so the surviving colour hugs
/// the leading edge and vanishes off the left at the boundary.
struct CadenceFillView: View {
    let schedule: CadenceSchedule

    /// The panel colour: a dark warm amber, bright enough to read as a lit panel
    /// against the black ground while staying well below the white digits and
    /// the near-black cards in luminance, so nothing on top of it loses contrast.
    /// Warm also keeps it clear of the events timeline's red now-line.
    static let panelColor = Color(red: 0.30, green: 0.215, blue: 0.055)

    /// The frame: the fill's hue lifted well above the fill's own luminance, so
    /// an emptied track still has an edge to be empty *against*, then damped
    /// with opacity so it never competes with the digits.
    static let borderColor = Color(red: 0.72, green: 0.52, blue: 0.13).opacity(0.75)

    /// The unlit remainder: the panel colour at about a third strength, which
    /// reads as a track rather than as a second fill now that the frame is there
    /// to bound it.
    static let trackOpacity: Double = 0.32

    /// Time the panel takes to sweep back to full after an announcement. Long
    /// and eased so the refill reads as a deliberate swell, not a flash.
    static let refillDuration: TimeInterval = 1.5

    /// Matches the tick rate, so each step of the wipe is a smooth glide into
    /// the next second's value rather than a stutter.
    static let creepDuration: TimeInterval = 1

    /// Corner radius as a multiple of the face's card height, so the panel keeps
    /// its proportions at every window size.
    static let cornerRadiusUnits: CGFloat = 0.18

    /// Border thickness, also in face units so it holds its weight against the
    /// digits as the window grows, then clamped: below the floor it disappears
    /// on a small window, above the ceiling it starts to crowd a large one. The
    /// units are chosen to land on 4 pt at the default window size.
    static let borderWidthUnits: CGFloat = 0.023
    static let minBorderWidth: CGFloat = 2
    static let maxBorderWidth: CGFloat = 7

    /// The last fraction rendered, used only to tell a refill (value jumps up)
    /// from the ordinary wipe (value creeps down) so each gets its own curve.
    @State private var lastFraction: Double = 1

    var body: some View {
        GeometryReader { geo in
            let unit = FaceMetrics.unit(fitting: geo.size)
            let border = Self.borderWidth(unit: unit, in: geo.size)
            let radius = unit * Self.cornerRadiusUnits
            // The border's inner edge and the track's silhouette are the same
            // curve: a rounded rect inset by the border width, its radius
            // reduced by the same amount. Deriving both from these two numbers
            // is what guarantees they meet exactly, with no black hairline
            // between the frame and what it frames.
            let innerRadius = max(0, radius - border)
            let inner = CGSize(width: max(0, geo.size.width - 2 * border),
                               height: max(0, geo.size.height - 2 * border))

            TimelineView(.periodic(from: .now, by: Self.creepDuration)) { context in
                let fraction = schedule.fractionRemaining(at: context.date) ?? 0
                ZStack {
                    track(fraction: fraction, size: inner, radius: innerRadius)
                        .padding(border)

                    FaceBorderShape(inset: border, cornerRadius: innerRadius)
                        .fill(Self.borderColor, style: FillStyle(eoFill: true))
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The faint full extent with the bright fill draining inside it.
    private func track(fraction: Double, size: CGSize, radius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Self.panelColor.opacity(Self.trackOpacity))

            // The fill keeps its full-size rounded silhouette and is revealed
            // through a leading-anchored mask, so the corners stay soft while
            // the moving edge itself is a clean vertical cut — shrinking the
            // shape instead would round the trailing edge and read as a pill
            // sliding away rather than a wipe.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Self.panelColor)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: size.width * fraction, height: size.height)
                }
                .animation(
                    fraction > lastFraction
                        ? .easeOut(duration: Self.refillDuration)
                        : .linear(duration: Self.creepDuration),
                    value: fraction
                )
                .onChange(of: fraction) { _, new in lastFraction = new }
        }
        .frame(width: size.width, height: size.height)
    }

    /// The border thickness for a region, never thick enough to swallow the
    /// region it frames.
    static func borderWidth(unit: CGFloat, in size: CGSize) -> CGFloat {
        let scaled = min(max(unit * borderWidthUnits, minBorderWidth), maxBorderWidth)
        return min(scaled, min(size.width, size.height) / 4)
    }
}

/// The frame itself: everything between the region's *square* outer bounds and
/// an inset rounded rect, filled with the even-odd rule.
///
/// Square on the outside is the whole point. Stroking the rounded rect instead
/// — `strokeBorder`, the obvious spelling — leaves the ground showing outside
/// each corner's curve, and where the face region meets the window the ground
/// is the world outside the app: a black sliver between the border and the
/// window edge, most visible at the bottom corners. So the border runs edge to
/// edge and spends its thickness inwards, taking the corner curve on its inner
/// edge only, where it belongs — that curve is the silhouette of the thing
/// being framed.
struct FaceBorderShape: Shape {
    /// Distance from the outer edge to the inner cutout: the border thickness
    /// along the straight runs.
    var inset: CGFloat
    /// Radius of the inner cutout, which is the fill's own radius less `inset`.
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
