import SwiftUI

/// The countdown drain: one square-cornered plane of the colourway's lit tint,
/// filling the window inside the bezel, whose right-to-left edge sweeps across
/// as the next spoken announcement approaches and eases back to full when the
/// clock speaks.
///
/// **The drain is not an object.** It is deliberately not a panel: no rounding,
/// no track behind it, no border of its own. A rounded silhouette leaves wedges
/// of ground outside its corners and reads as a pill sitting *on* the window,
/// and an unlit track claims the emptied part of the countdown is a different
/// surface from the rest of the app. Neither is true. The ground already **is**
/// the empty state, so the drained portion is simply plain ground and the only
/// thing that moves is the boundary between lit and unlit — which is the only
/// thing that ever meant anything.
///
/// **The plane is the whole window, not the face region.** With the events panel
/// open the drain sweeps under it too: one continuous plane behind the face, the
/// divider and the calendar alike, bounded only by the bezel. That is why it is
/// mounted at the window root in `ContentView` rather than inside the face's own
/// stack, and why every events colour has to survive being drawn over two
/// backgrounds (see `EventsPalette`).
///
/// A `TimelineView` drives it rather than the minute tick, because the wipe has
/// to be continuous — the face only changes once a minute, but the countdown
/// needs to move visibly between minutes. The edge position is linear in the
/// time remaining, so the lit width reads directly as "how much of the wait is
/// left": half the interval gone, half the window still lit.
struct CadenceFillView: View {
    let schedule: CadenceSchedule

    /// Time the plane takes to sweep back to full after an announcement. Long
    /// and eased so the refill reads as a deliberate swell, not a flash.
    static let refillDuration: TimeInterval = 1.5

    /// Matches the tick rate, so each step of the wipe is a smooth glide into
    /// the next second's value rather than a stutter.
    static let creepDuration: TimeInterval = 1

    /// The last fraction rendered, used only to tell a refill (value jumps up)
    /// from the ordinary wipe (value creeps down) so each gets its own curve.
    @State private var lastFraction: Double = 1

    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: .now, by: Self.creepDuration)) { context in
                let fraction = schedule.fractionRemaining(at: context.date) ?? 0

                // The plane keeps its full size and is revealed through a
                // leading-anchored mask rather than being resized, so the moving
                // edge is a clean vertical cut with no interpolation of the
                // shape itself.
                Rectangle()
                    .fill(theme.cadenceFill)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: geo.size.width * fraction,
                                          height: geo.size.height)
                    }
                    .animation(
                        fraction > lastFraction
                            ? .easeOut(duration: Self.refillDuration)
                            : .linear(duration: Self.creepDuration),
                        value: fraction
                    )
                    .onChange(of: fraction) { _, new in lastFraction = new }
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
