import SwiftUI

/// How often the drain needs a fresh frame, and whether the resulting step is
/// large enough to be worth animating.
///
/// The drain's only job is to move one vertical edge across the window, so the
/// smallest change worth drawing is one point of travel — anything finer than
/// that lands on the same pixel column. That makes the natural tick rate a
/// property of the *speed* of the edge rather than a fixed one-second beat:
/// spread a 15-minute gap across a 900-point window and the edge covers a point
/// a second, but spread an hour across the same window and it takes four
/// seconds to move that same point. Ticking on the fixed second in the second
/// case redraws the window four times for every visible change.
///
/// The `animates` question matters far more than the tick rate, because an
/// implicit animation is not a cheaper way to draw the same motion — it is a
/// *continuous* one. A one-second `.linear` on the mask puts SwiftUI's animation
/// driver in charge until it finishes, and since the next tick starts another
/// one immediately, the window's whole display list is rebuilt at the display's
/// refresh rate forever. Measured on a 731×275 window that cost 7% of a core
/// with the clock face alone and 12% with the events panel open, because the
/// per-frame cost is the size of the *hierarchy*, not the size of the animating
/// layer. Stepping instead costs one render per tick.
///
/// So the tick is chosen to make each step about one point and the animation is
/// reserved for steps too coarse to pass as continuous motion. The floor is
/// deliberately below a second: a very wide window or a short cadence is exactly
/// the case where a fixed one-second tick would force a multi-point jump and
/// hence an animation, and two cheap renders a second beat sixty.
struct DrainCadence: Equatable {

    /// Steps at or above this many points read as a jump rather than a creep,
    /// so they get an animation despite the cost. Below it the step is at most
    /// a hairline and is simply drawn.
    static let animationThreshold: Double = 2

    /// Never redraw faster than this (the cheap-renders ceiling) …
    static let minimumTick: TimeInterval = 0.5
    /// … nor slower than this, so even the laziest cadence still looks alive.
    static let maximumTick: TimeInterval = 10

    /// Seconds between redraws.
    let tick: TimeInterval

    /// How far the edge travels in one tick, in points.
    let stepPoints: Double

    var animates: Bool { stepPoints >= Self.animationThreshold }

    /// - Parameters:
    ///   - spanSeconds: the whole gap between announcement boundaries, which is
    ///     what the full window width represents.
    ///   - width: the plane's width in points — the distance the edge travels
    ///     over that span.
    init(spanSeconds: TimeInterval, width: Double) {
        guard spanSeconds > 0, width > 0 else {
            tick = Self.minimumTick
            stepPoints = 0
            return
        }
        let secondsPerPoint = spanSeconds / width
        tick = min(max(secondsPerPoint, Self.minimumTick), Self.maximumTick)
        stepPoints = tick / secondsPerPoint
    }
}

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
/// left": half the interval gone, half the window still lit. How *often* that
/// timeline fires, and whether the step between fires is animated, is
/// `DrainCadence`'s decision — see there for why both are chosen rather than
/// fixed.
struct CadenceFillView: View {
    let schedule: CadenceSchedule

    /// False while the window is fully hidden — minimised, behind another
    /// window, or on another Space. A `TimelineView` keeps ticking regardless
    /// of whether anyone can see it (measured: 10% of a core with the window
    /// minimised), and the drain has no state to keep warm — its position is a
    /// pure function of the clock — so the honest thing is to stop entirely and
    /// recompute on the way back.
    var isVisible: Bool = true

    /// Time the plane takes to sweep back to full after an announcement. Long
    /// and eased so the refill reads as a deliberate swell, not a flash.
    static let refillDuration: TimeInterval = 1.5

    /// The last fraction rendered, used only to tell a refill (value jumps up)
    /// from the ordinary wipe (value creeps down) so each gets its own curve.
    @State private var lastFraction: Double = 1

    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let cadence = DrainCadence(spanSeconds: spanSeconds,
                                       width: geo.size.width)
            if isVisible {
                TimelineView(.periodic(from: .now, by: cadence.tick)) { context in
                    plane(at: context.date, in: geo.size, cadence: cadence)
                }
            } else {
                // Hidden: draw the plane once, unanimated, so the moment the
                // window is revealed it is already in the right place and the
                // timeline picks up from there.
                plane(at: .now, in: geo.size, cadence: cadence, animated: false)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The plane keeps its full size and is revealed through a leading-anchored
    /// mask rather than being resized, so the moving edge is a clean vertical
    /// cut with no interpolation of the shape itself.
    @ViewBuilder
    private func plane(at date: Date,
                       in size: CGSize,
                       cadence: DrainCadence,
                       animated: Bool = true) -> some View {
        let fraction = schedule.fractionRemaining(at: date) ?? 0
        let refilling = fraction > lastFraction

        Rectangle()
            .fill(theme.cadenceFill)
            .mask(alignment: .leading) {
                Rectangle().frame(width: size.width * fraction, height: size.height)
            }
            // The refill is always animated: it is a whole-window jump, and the
            // swell is the point of it. The creep is animated only when a step
            // is too coarse to pass for continuous motion on its own.
            .animation(
                animated && refilling ? .easeOut(duration: Self.refillDuration)
                    : animated && cadence.animates ? .linear(duration: cadence.tick)
                    : nil,
                value: fraction
            )
            .onChange(of: fraction) { _, new in lastFraction = new }
            .frame(width: size.width, height: size.height)
    }

    /// The gap between announcement boundaries, which the full width represents.
    private var spanSeconds: TimeInterval {
        TimeInterval(schedule.stepMinutes ?? 0) * 60
    }
}
