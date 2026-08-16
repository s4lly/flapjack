// PROTOTYPE — throwaway. Round 3.
//
// Round 1 fixed the form (**Classic flip**). Round 2 made a palette a complete
// COLOURWAY rather than just a face, and moved the frame out to a window bezel.
// Round 3 answers what is left, which is what the countdown *is*:
//
// 1. **The drain is no longer an object.** Round 2 still drew it as a rounded
//    panel with a faint track behind it: a pill inside the bezel, with wedges of
//    ground showing outside its corners. Both cues are gone. The lit fill is now
//    a SQUARE-cornered plane that starts at the bezel's inner edge, and the
//    drained part is simply the ground — there is no "unlit track" tint, because
//    the ground already IS the empty state. What remains is the one thing that
//    was ever doing the work: a vertical cut sweeping right to left, easing back
//    to full when the clock speaks.
//
// 2. **The plane is the whole app, not the face region.** With the calendar open
//    the fill sweeps under it too — one continuous plane behind the face, the
//    divider and the events panel alike, bounded only by the bezel. That is why
//    every events colour has to survive being drawn over *two* backgrounds now
//    (see `EventsColorway`), and why the fill lives at the window root in
//    `ContentView` rather than inside the face's own `ZStack`.
//
// 3. **Dark pastels.** The five round-2 colourways are all daylight schemes; a
//    clock that sits on a desk at night wants the same colour identity at low
//    output. D1–D3 are mid-dark (not black) grounds with soft light digits and a
//    lit tint dim enough to read as "warm lamp" rather than "screen on".
//
// A colourway is therefore:
//
//   ground · cards · digits · colon/badge · cadence (fill/frame) ·
//   events (rules, chips, text, now-line) · divider
//
// Two axes, switchable live:
//   ←/→  FACE STYLE   Classic · Minimal                        (default Classic)
//   ↑/↓  COLOURWAY    0 Charcoal · P1 Sage · P2 Lavender · P3 Peach · P4 Powder
//                     D1 Deep sage · D2 Deep indigo · D3 Deep slate
//
// The colourway is injected at the *window root* rather than at the face, so the
// cadence fill, the events panel, the divider and the window's own chrome all
// read the same values. With no value in the environment (the flag off) every
// view falls back to its shipped body, byte for byte.
//
// The frame (see `WindowFrameOverlay`): the cadence border used to hug the face
// region, which put a bar down the seam between the face and the calendar. It is
// now a window bezel — the same colour as the title-bar strip, wrapped around
// all four window edges, around everything, and now also the boundary the
// full-bleed fill runs up to.
//
// Run with: open dist/Flapjack.app --args -prototypeStyle 1
// No polish, no tests, no accessibility work beyond what falls out for free.

import AppKit
import SwiftUI

// MARK: - Axis 1: face style

/// Round 2 kept "Current" (the shipped card) on the cycle as a control. It has
/// lost every comparison it was in, so the axis is down to the two candidates
/// and `classic` is first — which also makes the default the zero value.
enum FaceStyleVariant: Int, CaseIterable {
    case classic = 0
    case minimal = 1

    var label: String {
        switch self {
        case .classic: return "Classic"
        case .minimal: return "Minimal"
        }
    }

    /// Everything about the card's *form* — the palette supplies the colours.
    var spec: FaceStyleSpec {
        switch self {
        case .classic:
            // The researched look. Bigger radius (references run ~8–10% of card
            // height), SQUARE corners either side of the hinge so the two halves
            // read as one card, an explicitly painted hinge line, a light-from-
            // above gradient with a crease shadow under the hinge, side pivot
            // pins, soft drop shadow.
            return FaceStyleSpec(cornerRadius: 0.095,
                                 squareHingeCorners: true,
                                 hingeGap: 0.014,
                                 paintsHinge: true,
                                 topShades: (0.055, -0.005),
                                 bottomShades: (-0.045, 0.012),
                                 pins: true,
                                 shadow: true)
        case .minimal:
            // Same structural cue, none of the ornament: hinge and gradients
            // only, flatter, no pins, no shadow.
            return FaceStyleSpec(cornerRadius: 0.085,
                                 squareHingeCorners: true,
                                 hingeGap: 0.010,
                                 paintsHinge: true,
                                 topShades: (0.028, 0.000),
                                 bottomShades: (-0.024, -0.004),
                                 pins: false,
                                 shadow: false)
        }
    }
}

/// The card's form, all lengths as fractions of the card height (`size`).
struct FaceStyleSpec {
    var cornerRadius: CGFloat
    /// Whether the two corners either side of the hinge are square. This is the
    /// single biggest fidelity lever: rounding them makes one card look like two
    /// tiles.
    var squareHingeCorners: Bool
    var hingeGap: CGFloat
    /// Paint the gap with the hinge colour rather than letting the ground show
    /// through — required for the light palettes, where a transparent gap
    /// disappears.
    var paintsHinge: Bool
    /// Luminance offsets from the card's base shade: (top of half, bottom of half).
    var topShades: (CGFloat, CGFloat)
    var bottomShades: (CGFloat, CGFloat)
    var pins: Bool
    var shadow: Bool
}

// MARK: - Axis 2: colourway

/// A colour expressed in components so the card shading can be derived from the
/// base rather than hand-listed per palette — that is what keeps the gradient
/// coherent when the ground goes from black to sage.
struct Shade {
    var r: Double, g: Double, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    var color: Color { Color(red: r, green: g, blue: b) }

    func adjusted(by delta: Double) -> Color {
        Color(red: min(1, max(0, r + delta)),
              green: min(1, max(0, g + delta)),
              blue: min(1, max(0, b + delta)))
    }
}

/// The countdown backdrop's two colours.
///
/// Round 2 had three: fill, track, frame. The track is gone — with the panel
/// full-bleed and square there is nothing left for a track to bound, and the
/// ground reads as "drained" perfectly well on its own once the pill silhouette
/// that made it look like *outside* the countdown is removed. So the invariant
/// is now just **lit vs ground**, and it has to hold in both directions:
///
/// - on a light ground, a dark amber inverts into a stain, so every light
///   colourway lifts a saturated warm tint clearly ABOVE its ground;
/// - on a dark ground the lift is the same sign but much smaller, because the
///   plane now covers the whole window and a bright one at 3 a.m. is a lamp
///   pointed at the user. D1–D3 lift by roughly 0.10–0.13 in linear terms:
///   unmistakable as a moving edge, invisible as glare.
///
/// The ordering every palette keeps is `digits ≪ ground < fill < cards` (light)
/// or `digits ≫ cards > fill > ground` (dark): the cards stay furthest from the
/// ground so the face never sinks into its own backdrop, and the digits stay
/// furthest from everything so they dominate regardless of what is behind them.
struct CadenceColorway {
    /// The lit plane.
    var fill: Color
    /// The window bezel. Also the window's `backgroundColor`, which is what the
    /// title-bar strip shows, so the strip and the perimeter are one thing.
    var frame: Color
}

/// The events panel's colours. On black these are dim greys and a hot red; on a
/// pastel ground every one of them has to flip sense — text goes dark, the
/// rules go from white-over-black to black-over-tint, and the now-line has to be
/// deepened or it screams.
///
/// Round 3 adds a second constraint on every one of them: the fill now runs
/// under the panel, so each colour is drawn over the ground on one side of the
/// moving edge and over the lit tint on the other, *within a single glance*. The
/// recipes below are therefore tuned for the harder of the two backgrounds and
/// checked against the other — which mostly cost the chip washes, which had been
/// set just high enough to have an edge against the ground alone.
struct EventsColorway {
    /// Event titles and all-day labels.
    var title: Color
    /// Hour labels and the time range under a title.
    var axis: Color
    /// Empty-state and permission text.
    var hint: Color
    var gridline: Color
    var hourGridline: Color
    /// The one saturated thing in the panel.
    var now: Color
    /// How much of the calendar's own colour the chip wash carries. Light
    /// grounds need more than black did: at 0.24 a pastel-over-pastel chip has
    /// no edge at all.
    var chipWash: Double
    /// The all-day pill, always a touch quieter than a timeline chip.
    var allDayWash: Double
    /// Opacity of a hairline outline in the calendar's own colour around each
    /// chip. Zero on black, where a wash already has all the edge it needs.
    ///
    /// It exists for the full-bleed drain. A wash is a *relationship* to what is
    /// behind it, and there are now two things behind it: a chip tuned to have
    /// an edge against the ground loses most of it over the lit fill, and one
    /// tuned for the fill is a slab against the ground. Worse, a chip wide
    /// enough to straddle the moving cut showed both at once and appeared to
    /// change size as the edge crossed it. An outline is the same colour on both
    /// sides, so the chip keeps one shape whatever it is lying on.
    var chipEdge: Double
    /// The split divider's hairline and grip, idle and active.
    var seam: Color
    var seamActive: Color
    var grip: Color
    var gripActive: Color

    static let shipped = EventsColorway(
        title: Color(white: 0.90),
        axis: Color(white: 0.44),
        hint: Color(white: 0.42),
        gridline: Color.white.opacity(0.08),
        hourGridline: Color.white.opacity(0.13),
        now: Color(red: 1.0, green: 0.27, blue: 0.23),
        chipWash: 0.24,
        allDayWash: 0.18,
        chipEdge: 0,
        seam: Color.white.opacity(0.10),
        seamActive: Color.white.opacity(0.30),
        grip: Color.white.opacity(0.30),
        gripActive: Color.white.opacity(0.70))

    /// The light-ground recipe. Only the hue-carrying colours differ between the
    /// four pastels, so they are the parameters and everything else is shared —
    /// which is what stops one scheme from quietly drifting more legible than
    /// its siblings.
    ///
    /// The washes went up from round 2's 0.38/0.30: over the lit fill — which is
    /// lighter *and* warmer than the ground — a chip at 0.38 lost most of its
    /// edge, so a chip that straddled the moving cut appeared to change size.
    /// The rules went the same way, since a black hairline at 0.13 over a bright
    /// cream fill is nearly nothing.
    static func light(ink: Color, muted: Color, now: Color) -> EventsColorway {
        EventsColorway(
            title: ink,
            axis: muted,
            hint: muted,
            gridline: Color.black.opacity(0.17),
            hourGridline: Color.black.opacity(0.34),
            now: now,
            chipWash: 0.46,
            allDayWash: 0.38,
            chipEdge: 0.85,
            seam: Color.black.opacity(0.22),
            seamActive: Color.black.opacity(0.48),
            grip: Color.black.opacity(0.40),
            gripActive: Color.black.opacity(0.66))
    }

    /// The dark-ground recipe: the same shape as `light` with every polarity
    /// flipped, but *not* the shipped black table. The shipped values assume a
    /// pure-black ground and go as dim as 0.42 white; over a 20 %-lightness
    /// ground they disappear, and over the lit tint on top of it they disappear
    /// twice. Everything here is lifted to clear the brighter of the two
    /// backgrounds it can land on.
    static func dark(ink: Color, muted: Color, now: Color) -> EventsColorway {
        EventsColorway(
            title: ink,
            axis: muted,
            hint: muted,
            gridline: Color.white.opacity(0.13),
            hourGridline: Color.white.opacity(0.26),
            now: now,
            chipWash: 0.42,
            allDayWash: 0.34,
            chipEdge: 0.80,
            seam: Color.white.opacity(0.18),
            seamActive: Color.white.opacity(0.42),
            grip: Color.white.opacity(0.34),
            gripActive: Color.white.opacity(0.72))
    }
}

enum FacePalette: Int, CaseIterable {
    case charcoal, sage, lavender, peach, powder
    case deepSage, deepIndigo, deepSlate

    var label: String {
        switch self {
        case .charcoal: return "0 Charcoal"
        case .sage: return "P1 Sage"
        case .lavender: return "P2 Lavender"
        case .peach: return "P3 Peach"
        case .powder: return "P4 Powder"
        case .deepSage: return "D1 Deep sage"
        case .deepIndigo: return "D2 Deep indigo"
        case .deepSlate: return "D3 Deep slate"
        }
    }

    var theme: FaceTheme {
        switch self {
        case .charcoal:
            return FaceTheme(
                ground: Shade(0.0, 0.0, 0.0),
                card: Shade(0.140, 0.140, 0.140),
                digit: Color(white: 0.94),
                hinge: Color(white: 0.02),
                accent: Color(white: 0.55),
                badgeText: Color(white: 0.58),
                badgeFill: Color.white.opacity(0.07),
                shadow: Color.black.opacity(0.5),
                shadeScale: 1.0,
                cadence: CadenceColorway(
                    fill: Color(red: 0.30, green: 0.215, blue: 0.055),
                    // NOT the shipped border colour. That was a 4pt hairline
                    // of 0.75-alpha amber; the bezel now includes the whole
                    // title-bar band, and the same gold at that size is a gold
                    // *bar* across the top of the app. Dark bronze keeps the
                    // amber family at a weight a case can carry.
                    frame: Color(red: 0.290, green: 0.208, blue: 0.055)),
                events: .shipped)

        case .sage:
            // Muted green. The quietest of the four — the ground is close enough
            // to neutral that the warm fill has to do all the "lit" work.
            return FaceTheme(
                ground: Shade(0.706, 0.749, 0.694),
                card: Shade(0.976, 0.980, 0.965),
                digit: Color(red: 0.145, green: 0.192, blue: 0.157),
                hinge: Color(red: 0.400, green: 0.463, blue: 0.400),
                accent: Color(red: 0.322, green: 0.396, blue: 0.325),
                badgeText: Color(red: 0.310, green: 0.384, blue: 0.314),
                badgeFill: Color.black.opacity(0.07),
                shadow: Color(red: 0.145, green: 0.208, blue: 0.149).opacity(0.30),
                shadeScale: 0.42,
                cadence: CadenceColorway(
                    fill: Color(red: 0.933, green: 0.898, blue: 0.706),
                    frame: Color(red: 0.196, green: 0.259, blue: 0.204)),
                events: .light(ink: Color(red: 0.129, green: 0.176, blue: 0.141),
                               muted: Color(red: 0.318, green: 0.384, blue: 0.322),
                               now: Color(red: 0.706, green: 0.145, blue: 0.129)))

        case .lavender:
            return FaceTheme(
                ground: Shade(0.749, 0.729, 0.812),
                card: Shade(0.976, 0.973, 0.992),
                digit: Color(red: 0.169, green: 0.145, blue: 0.235),
                hinge: Color(red: 0.443, green: 0.412, blue: 0.529),
                accent: Color(red: 0.365, green: 0.337, blue: 0.463),
                badgeText: Color(red: 0.353, green: 0.325, blue: 0.451),
                badgeFill: Color.black.opacity(0.07),
                shadow: Color(red: 0.192, green: 0.161, blue: 0.278).opacity(0.30),
                shadeScale: 0.42,
                cadence: CadenceColorway(
                    // Peachy cream rather than yellow: against a cool violet
                    // ground a yellow fill reads acid, and the complement is
                    // already doing the "different temperature" work.
                    fill: Color(red: 0.957, green: 0.882, blue: 0.784),
                    frame: Color(red: 0.216, green: 0.196, blue: 0.298)),
                events: .light(ink: Color(red: 0.153, green: 0.129, blue: 0.220),
                               // A shade darker than the badge/accent grey the
                               // face uses: lavender is the lightest of the four
                               // grounds, so the hour ruler needs the help.
                               muted: Color(red: 0.310, green: 0.286, blue: 0.412),
                               now: Color(red: 0.714, green: 0.145, blue: 0.204)))

        case .peach:
            // The hardest case: the ground is already warm, so a warm fill has
            // to separate on lightness and on saturation rather than on hue.
            return FaceTheme(
                ground: Shade(0.902, 0.769, 0.686),
                card: Shade(0.996, 0.976, 0.957),
                digit: Color(red: 0.235, green: 0.145, blue: 0.110),
                hinge: Color(red: 0.561, green: 0.412, blue: 0.333),
                accent: Color(red: 0.463, green: 0.333, blue: 0.267),
                badgeText: Color(red: 0.451, green: 0.325, blue: 0.259),
                badgeFill: Color.black.opacity(0.07),
                shadow: Color(red: 0.290, green: 0.176, blue: 0.129).opacity(0.30),
                shadeScale: 0.42,
                cadence: CadenceColorway(
                    fill: Color(red: 1.000, green: 0.937, blue: 0.647),
                    // Deep cocoa: the only bezel dark enough to hold a ground
                    // this light without reading as a second peach.
                    frame: Color(red: 0.259, green: 0.161, blue: 0.118)),
                events: .light(ink: Color(red: 0.212, green: 0.129, blue: 0.098),
                               muted: Color(red: 0.451, green: 0.318, blue: 0.251),
                               // Crimson, not red: a scarlet now-line on an
                               // orange ground is the same hue family and stops
                               // reading as a marker.
                               now: Color(red: 0.604, green: 0.086, blue: 0.180)))

        case .powder:
            return FaceTheme(
                ground: Shade(0.702, 0.784, 0.843),
                card: Shade(0.965, 0.980, 0.992),
                digit: Color(red: 0.114, green: 0.180, blue: 0.235),
                hinge: Color(red: 0.373, green: 0.478, blue: 0.549),
                accent: Color(red: 0.290, green: 0.404, blue: 0.478),
                badgeText: Color(red: 0.278, green: 0.392, blue: 0.467),
                badgeFill: Color.black.opacity(0.07),
                shadow: Color(red: 0.110, green: 0.180, blue: 0.239).opacity(0.30),
                shadeScale: 0.42,
                cadence: CadenceColorway(
                    fill: Color(red: 0.965, green: 0.902, blue: 0.714),
                    frame: Color(red: 0.129, green: 0.216, blue: 0.286)),
                events: .light(ink: Color(red: 0.098, green: 0.161, blue: 0.212),
                               muted: Color(red: 0.278, green: 0.392, blue: 0.467),
                               now: Color(red: 0.729, green: 0.161, blue: 0.145)))

        // The three deep schemes below are the pastels' night shift, and they
        // are built by the same recipe rather than by "darken everything":
        //
        //   ground   ~19–21 % lightness, desaturated — mid-dark, deliberately
        //            not black, so the window still reads as a coloured object
        //            in a dark room rather than as a hole in the desktop;
        //   card     ~0.07 above the ground, which is the smallest step that
        //            still separates a card from its backdrop once the lit
        //            plane is behind it;
        //   digit    soft light (~0.83), never 1.0 — white digits this size on
        //            a dark ground bloom, and bloom is exactly the thing a
        //            night scheme exists to avoid;
        //   cadence  a warm tint ~0.11 above the ground: enough that the moving
        //            cut is obvious at a glance, dim enough that a full plane
        //            is not a light source;
        //   frame    ~0.09, below the ground, so the bezel still reads as a
        //            case around the thing rather than a border on it.
        //
        // `shadeScale` is 0.72 rather than the pastels' 0.42: a dark card has
        // room for a real gradient before it turns plastic, and needs one, since
        // it has less contrast with its surroundings to do the shaping.
        case .deepSage:
            return FaceTheme(
                ground: Shade(0.165, 0.200, 0.173),
                // Lifted past the nominal 0.07 step: D1's lit tint is the
                // closest of the three to its own card, and with the plane
                // behind the whole face a card only 0.07 up read as a smudge
                // rather than as an object sitting on the light.
                card: Shade(0.259, 0.298, 0.267),
                digit: Color(red: 0.827, green: 0.859, blue: 0.824),
                hinge: Color(red: 0.094, green: 0.118, blue: 0.098),
                accent: Color(red: 0.549, green: 0.612, blue: 0.553),
                badgeText: Color(red: 0.573, green: 0.635, blue: 0.576),
                badgeFill: Color.white.opacity(0.08),
                shadow: Color.black.opacity(0.45),
                shadeScale: 0.72,
                cadence: CadenceColorway(
                    // Warm olive, not amber: on a green ground a pure amber at
                    // this luminance reads as a stain rather than as light.
                    fill: Color(red: 0.278, green: 0.290, blue: 0.208),
                    frame: Color(red: 0.075, green: 0.094, blue: 0.078)),
                events: .dark(ink: Color(red: 0.855, green: 0.882, blue: 0.851),
                              muted: Color(red: 0.588, green: 0.647, blue: 0.592),
                              // Coral rather than the shipped scarlet: full-hot
                              // red is the one colour that survives a dark
                              // scheme's dimming and then dominates it.
                              now: Color(red: 0.902, green: 0.376, blue: 0.325)))

        case .deepIndigo:
            return FaceTheme(
                ground: Shade(0.176, 0.169, 0.235),
                card: Shade(0.251, 0.243, 0.322),
                digit: Color(red: 0.843, green: 0.835, blue: 0.894),
                hinge: Color(red: 0.106, green: 0.102, blue: 0.153),
                accent: Color(red: 0.573, green: 0.561, blue: 0.663),
                badgeText: Color(red: 0.596, green: 0.584, blue: 0.686),
                badgeFill: Color.white.opacity(0.08),
                shadow: Color.black.opacity(0.45),
                shadeScale: 0.72,
                cadence: CadenceColorway(
                    // The one place a genuinely warm tint works unaltered: the
                    // ground is cool and violet, so a dim ember separates on
                    // temperature and needs almost no lift in luminance.
                    fill: Color(red: 0.322, green: 0.267, blue: 0.239),
                    frame: Color(red: 0.086, green: 0.082, blue: 0.129)),
                events: .dark(ink: Color(red: 0.867, green: 0.859, blue: 0.914),
                              muted: Color(red: 0.612, green: 0.600, blue: 0.702),
                              now: Color(red: 0.918, green: 0.373, blue: 0.400)))

        case .deepSlate:
            return FaceTheme(
                ground: Shade(0.149, 0.184, 0.216),
                card: Shade(0.220, 0.259, 0.298),
                digit: Color(red: 0.824, green: 0.859, blue: 0.886),
                hinge: Color(red: 0.086, green: 0.110, blue: 0.137),
                accent: Color(red: 0.541, green: 0.608, blue: 0.659),
                badgeText: Color(red: 0.565, green: 0.631, blue: 0.682),
                badgeFill: Color.white.opacity(0.08),
                shadow: Color.black.opacity(0.45),
                shadeScale: 0.72,
                cadence: CadenceColorway(
                    // Bronze, red-dominant. The obvious choice for a blue
                    // ground is the same warm olive D1 uses, and it works — but
                    // it works so well that D1 and D3 became the same scheme the
                    // moment the plane was lit, since the fill covers most of
                    // the window and the ground barely shows. Pushing the red
                    // above the green keeps the two apart in the state they are
                    // in most of the time.
                    fill: Color(red: 0.318, green: 0.271, blue: 0.200),
                    frame: Color(red: 0.071, green: 0.094, blue: 0.118)),
                events: .dark(ink: Color(red: 0.851, green: 0.882, blue: 0.906),
                              muted: Color(red: 0.580, green: 0.647, blue: 0.698),
                              now: Color(red: 0.914, green: 0.392, blue: 0.353)))
        }
    }
}

struct FaceTheme {
    var ground: Shade
    var card: Shade
    var digit: Color
    var hinge: Color
    var accent: Color
    var badgeText: Color
    var badgeFill: Color
    var shadow: Color
    /// How hard the style's luminance offsets bite. Light cards need far less
    /// than dark ones before the gradient turns plastic.
    var shadeScale: Double
    var cadence: CadenceColorway
    var events: EventsColorway
}

/// What the card views actually read.
struct FaceRenderStyle {
    var spec: FaceStyleSpec
    var theme: FaceTheme

    func shade(_ delta: CGFloat) -> Color {
        theme.card.adjusted(by: Double(delta) * theme.shadeScale)
    }

    func gradient(for half: Half) -> LinearGradient {
        let pair = half == .top ? spec.topShades : spec.bottomShades
        return LinearGradient(colors: [shade(pair.0), shade(pair.1)],
                              startPoint: .top, endPoint: .bottom)
    }

    /// Outer corners rounded, hinge corners square when the style asks for it.
    func shape(for half: Half, size: CGFloat) -> UnevenRoundedRectangle {
        let outer = size * spec.cornerRadius
        let inner = spec.squareHingeCorners ? 0 : outer
        return half == .top
            ? UnevenRoundedRectangle(topLeadingRadius: outer, bottomLeadingRadius: inner,
                                     bottomTrailingRadius: inner, topTrailingRadius: outer,
                                     style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: inner, bottomLeadingRadius: outer,
                                     bottomTrailingRadius: outer, topTrailingRadius: inner,
                                     style: .continuous)
    }
}

private struct FaceRenderStyleKey: EnvironmentKey {
    static let defaultValue: FaceRenderStyle? = nil
}

extension EnvironmentValues {
    /// `nil` means "draw the shipped look" — the flag-off path never touches a
    /// line of prototype rendering.
    var faceRenderStyle: FaceRenderStyle? {
        get { self[FaceRenderStyleKey.self] }
        set { self[FaceRenderStyleKey.self] = newValue }
    }
}

// MARK: - Hinge furniture

/// The hinge line, drawn *behind* the two halves so it shows through the gap and
/// a flipping half sweeps over it. Painted rather than left transparent because
/// on the light palettes the ground is not dark enough to read as a crease.
struct HingeLine: View {
    let style: FaceRenderStyle
    let size: CGFloat

    var body: some View {
        Rectangle()
            .fill(style.theme.hinge)
            // Same floor the VStack's spacing takes, or the painted line stops
            // filling the gap on a small window — which is exactly the size at
            // which the hinge is the *only* card cue still legible.
            .frame(width: size * 0.64, height: max(1, size * style.spec.hingeGap))
            .allowsHitTesting(false)
    }
}

/// The pivot pins: small notches in the ground colour biting into the card's
/// sides at hinge height, so they read as the pivot cut-out rather than as
/// stickers. They must be drawn in *front* of the halves — behind, the card
/// swallows the half of each notch that does the work. Suppressed below a size
/// where they would be sub-pixel mush.
struct HingePins: View {
    let style: FaceRenderStyle
    let size: CGFloat

    static let minimumSize: CGFloat = 56

    var body: some View {
        HStack(spacing: 0) {
            pin
            Spacer(minLength: 0)
            pin
        }
        .frame(width: size * 0.64 + size * 0.022)
        .allowsHitTesting(false)
    }

    /// The notch is cut out of the *cadence panel* as much as out of the card,
    /// so it takes whatever is directly behind the card rather than the ground:
    /// on a light palette with the fill lit, a ground-coloured pin is a visible
    /// dark fleck. Blending is close enough at this size and needs no knowledge
    /// of which layer it happens to be sitting over.
    private var pin: some View {
        Capsule(style: .continuous)
            .fill(style.theme.ground.color.opacity(0.85))
            .frame(width: size * 0.034, height: size * 0.070)
    }
}

// MARK: - The window bezel

/// The frame, moved out of the face region and onto the window.
///
/// Round 1 drew the cadence border around the *face*, which meant a bar of amber
/// down the seam where the face met the calendar — the frame was claiming to
/// enclose the clock while the window enclosed something bigger. And the title
/// bar sat in a fourth colour again, because `titlebarAppearsTransparent` lets
/// the window's `backgroundColor` show through the strip and that was still
/// black.
///
/// Both are the same fix: one bezel colour, used twice. `WindowController`
/// paints the strip with it (see `setChrome`) and this overlay runs it around
/// the remaining three edges, so the top strip and the perimeter are continuous
/// with no seam at the corners. Being an overlay on the window root, it is
/// outside the face/divider/calendar split entirely — there is nothing for it to
/// draw along the divider, which is exactly the ask.
///
/// It does not react to the cadence. The frame is now the window's case, not
/// part of the countdown: dimming it when the cadence is off would leave the
/// title-bar strip (which cannot dim with it without also restating the window
/// background on every toggle) a different colour from the sides — the seam this
/// whole rework exists to remove.
struct WindowFrameOverlay: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let width = CadenceFillView.borderWidth(unit: FaceMetrics.unit(fitting: geo.size),
                                                    in: geo.size)
            FaceBorderShape(inset: width, cornerRadius: max(0, 10 - width))
                .fill(color, style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }
}

// MARK: - Prototype ground + shell

/// Stands in for `Color.black` at the window root while the flag is set.
///
/// Deliberately *without* `.ignoresSafeArea()`, unlike the shipped ground it
/// replaces. That is the other half of the frame rework: a hidden-title-bar
/// window still keeps a title-bar-height safe area at the top, and the shipped
/// ground painted straight through it — which is why the strip behind the
/// traffic lights read as a band of its own, sitting above the framed face.
/// Held back to the safe area, the strip shows the window's `backgroundColor`
/// instead, which `FaceStyleProtoShell` has set to the bezel colour. The strip
/// therefore *is* the frame's top run, and `WindowFrameOverlay` carries the same
/// colour down the sides and along the bottom.
struct FaceStyleProtoGround: View {
    @AppStorage("prototypeFacePalette") private var rawPalette: Int = 0

    var body: some View {
        (FacePalette(rawValue: rawPalette) ?? .charcoal).theme.ground.color
    }
}

/// Wraps the whole window: injects the colourway everything reads, draws the
/// bezel, and keeps the window's own chrome colour in step with it.
struct FaceStyleProtoShell: ViewModifier {
    @AppStorage("prototypeFaceStyle") private var rawStyle: Int = FaceStyleVariant.classic.rawValue
    @AppStorage("prototypeFacePalette") private var rawPalette: Int = 0
    @EnvironmentObject private var windows: WindowController

    private var palette: FacePalette { FacePalette(rawValue: rawPalette) ?? .charcoal }
    private var variant: FaceStyleVariant { FaceStyleVariant(rawValue: rawStyle) ?? .classic }

    func body(content: Content) -> some View {
        content
            .environment(\.faceRenderStyle,
                         FaceRenderStyle(spec: variant.spec, theme: palette.theme))
            .overlay(WindowFrameOverlay(color: palette.theme.cadence.frame))
            .onAppear { windows.setChrome(NSColor(palette.theme.cadence.frame)) }
            .onChange(of: rawPalette) { _, _ in
                windows.setChrome(NSColor(palette.theme.cadence.frame))
            }
    }
}

extension View {
    /// PROTOTYPE — no-op unless the launch flag is set.
    @ViewBuilder
    func faceStylePrototypeShell() -> some View {
        if FaceStyleProtoFlag.isEnabled {
            modifier(FaceStyleProtoShell())
        } else {
            self
        }
    }
}

/// Stands in for `ClockFaceView` while the flag is set: same face, plus the
/// switcher pill and the arrow-key monitor. The colourway itself now arrives
/// from the shell, so this view only owns the *controls*.
struct FaceStyleProtoFace: View {
    let face: ClockFace

    @AppStorage("prototypeFaceStyle") private var rawStyle: Int = FaceStyleVariant.classic.rawValue
    @AppStorage("prototypeFacePalette") private var rawPalette: Int = 0
    @State private var keys = StyleArrowKeyMonitor()

    private var variant: FaceStyleVariant { FaceStyleVariant(rawValue: rawStyle) ?? .classic }
    private var palette: FacePalette { FacePalette(rawValue: rawPalette) ?? .charcoal }

    var body: some View {
        ZStack {
            ClockFaceView(face: face)
            VStack {
                Spacer()
                pill.padding(.bottom, 6)
            }
        }
        .onAppear {
            keys.start(
                left: { rawStyle = cycle(rawStyle, by: -1, of: FaceStyleVariant.allCases.count) },
                right: { rawStyle = cycle(rawStyle, by: 1, of: FaceStyleVariant.allCases.count) },
                up: { rawPalette = cycle(rawPalette, by: -1, of: FacePalette.allCases.count) },
                down: { rawPalette = cycle(rawPalette, by: 1, of: FacePalette.allCases.count) }
            )
        }
        .onDisappear { keys.stop() }
    }

    private func cycle(_ value: Int, by step: Int, of count: Int) -> Int {
        ((value + step) % count + count) % count
    }

    /// Neutral dark chrome on purpose: the pill has to stay legible on a black
    /// ground and on a pastel one without being restyled per palette.
    private var pill: some View {
        HStack(spacing: 8) {
            Button("◀") { rawStyle = cycle(rawStyle, by: -1, of: FaceStyleVariant.allCases.count) }
            Text(variant.label)
            Text("·").foregroundStyle(.white.opacity(0.4))
            Text(palette.label)
            Button("▶") { rawStyle = cycle(rawStyle, by: 1, of: FaceStyleVariant.allCases.count) }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(Color.white.opacity(0.9))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.62)))
        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
    }
}

/// Local arrow-key monitor, live only while the prototype face is on screen.
@MainActor
final class StyleArrowKeyMonitor {
    private var monitor: Any?

    func start(left: @escaping @MainActor () -> Void,
               right: @escaping @MainActor () -> Void,
               up: @escaping @MainActor () -> Void,
               down: @escaping @MainActor () -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 123: MainActor.assumeIsolated { left() }; return nil
            case 124: MainActor.assumeIsolated { right() }; return nil
            case 126: MainActor.assumeIsolated { up() }; return nil
            case 125: MainActor.assumeIsolated { down() }; return nil
            default: return event
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Launch flag: `open dist/Flapjack.app --args -prototypeStyle 1`
enum FaceStyleProtoFlag {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "prototypeStyle") }
}
