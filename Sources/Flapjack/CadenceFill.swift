import SwiftUI

/// The countdown backdrop: a lit panel behind the flip cards that wipes away
/// left to right as the next spoken announcement approaches, then sweeps back
/// to full when the clock speaks.
///
/// It is driven by a `TimelineView` rather than the minute tick because the
/// wipe has to be continuous — the clock face only changes once a minute, but
/// the countdown needs to move visibly between minutes. The edge position is
/// linear in the time remaining, so the lit width reads directly as "how much
/// of the wait is left": half the interval gone, half the face still lit.
///
/// The wipe uncovers the black ground from the *left*, so the surviving colour
/// hugs the trailing edge and vanishes off the right at the boundary.
struct CadenceFillView: View {
    let schedule: CadenceSchedule

    /// The panel colour: a dark warm amber, bright enough to read as a lit panel
    /// against the black ground while staying well below the white digits and
    /// the near-black cards in luminance, so nothing on top of it loses contrast.
    /// Warm also keeps it clear of the events timeline's red now-line.
    static let panelColor = Color(red: 0.30, green: 0.215, blue: 0.055)

    /// Time the panel takes to sweep back to full after an announcement. Long
    /// and eased so the refill reads as a deliberate swell, not a flash.
    static let refillDuration: TimeInterval = 1.5

    /// Matches the tick rate, so each step of the wipe is a smooth glide into
    /// the next second's value rather than a stutter.
    static let creepDuration: TimeInterval = 1

    /// Corner radius as a multiple of the face's card height, so the panel keeps
    /// its proportions at every window size.
    static let cornerRadiusUnits: CGFloat = 0.18

    /// The last fraction rendered, used only to tell a refill (value jumps up)
    /// from the ordinary wipe (value creeps down) so each gets its own curve.
    @State private var lastFraction: Double = 1

    var body: some View {
        GeometryReader { geo in
            let radius = FaceMetrics.unit(fitting: geo.size) * Self.cornerRadiusUnits
            TimelineView(.periodic(from: .now, by: Self.creepDuration)) { context in
                let fraction = schedule.fractionRemaining(at: context.date) ?? 0
                // The panel keeps its full-size rounded silhouette and is
                // revealed through a trailing-anchored mask, so the corners stay
                // soft while the moving edge itself is a clean vertical cut —
                // shrinking the shape instead would round the leading edge and
                // read as a pill sliding away rather than a wipe.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Self.panelColor)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .mask(alignment: .trailing) {
                        Rectangle()
                            .frame(width: geo.size.width * fraction,
                                   height: geo.size.height)
                    }
                    .animation(
                        fraction > lastFraction
                            ? .easeOut(duration: Self.refillDuration)
                            : .linear(duration: Self.creepDuration),
                        value: fraction
                    )
                    .onChange(of: fraction) { _, new in lastFraction = new }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
