import SwiftUI

/// A colour expressed in components, so the card shading can be *derived* from
/// the base rather than hand-listed per colourway. That is what keeps the flip
/// card's gradient coherent when the ground goes from black to peach: the two
/// halves are the same colour lifted and dropped by fixed amounts, and only the
/// amount is per-colourway (`Theme.shadeScale`).
struct Shade: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    func adjusted(by delta: Double) -> Color {
        Color(red: min(1, max(0, r + delta)),
              green: min(1, max(0, g + delta)),
              blue: min(1, max(0, b + delta)))
    }
}

/// The events panel's colours, including the divider's hairline and grip.
///
/// Every one of these has to survive being drawn over **two** backgrounds within
/// a single glance, because the cadence drain sweeps under the panel: a colour
/// is over the plain ground on one side of the moving cut and over the lit fill
/// on the other. Each recipe is therefore tuned for the harder of its two
/// backgrounds and checked against the other.
struct EventsPalette: Equatable {
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
    /// How much of the calendar's own colour a timeline chip's wash carries.
    var chipWash: Double
    /// The all-day pill, always a touch quieter than a timeline chip.
    var allDayWash: Double
    /// Opacity of a hairline outline in the calendar's own colour around each
    /// chip. Zero on black, where a wash already has all the edge it needs.
    ///
    /// It exists for the full-bleed drain. A wash is a *relationship* to what is
    /// behind it, and there are two things behind it: a chip tuned to have an
    /// edge against the ground loses most of it over the lit fill, and one tuned
    /// for the fill is a slab against the ground. Worse, a chip wide enough to
    /// straddle the moving cut showed both at once and appeared to change size
    /// as the edge crossed it. An outline is the same colour on both sides, so
    /// the chip keeps one shape whatever it is lying on.
    var chipEdge: Double
    /// The split divider's hairline and grip, idle and active.
    var seam: Color
    var seamActive: Color
    var grip: Color
    var gripActive: Color

    /// The black-ground recipe. Only Charcoal uses it, and it is the only one
    /// that can go this dim: with a pure-black ground there is nothing behind a
    /// hairline to compete with it.
    static func onBlack(now: Color) -> EventsPalette {
        EventsPalette(
            title: Color(white: 0.90),
            axis: Color(white: 0.44),
            hint: Color(white: 0.42),
            gridline: Color.white.opacity(0.08),
            hourGridline: Color.white.opacity(0.13),
            now: now,
            chipWash: 0.24,
            allDayWash: 0.18,
            chipEdge: 0,
            seam: Color.white.opacity(0.10),
            seamActive: Color.white.opacity(0.30),
            grip: Color.white.opacity(0.30),
            gripActive: Color.white.opacity(0.70))
    }

    /// The light-ground recipe. Only the hue-carrying colours differ between
    /// light colourways, so they are the parameters and everything else is
    /// shared — which is what stops one scheme from quietly drifting more
    /// legible than another.
    static func onLight(ink: Color, muted: Color, now: Color) -> EventsPalette {
        EventsPalette(
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

    /// The mid-dark recipe: the same shape as `onLight` with every polarity
    /// flipped, but *not* the black table. Those values assume a pure-black
    /// ground; over a ~20 %-lightness ground they disappear, and over the lit
    /// tint on top of it they disappear twice. Everything here is lifted to
    /// clear the brighter of the two backgrounds it can land on.
    static func onDark(ink: Color, muted: Color, now: Color) -> EventsPalette {
        EventsPalette(
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

/// Every colour the app draws with, in one value.
///
/// The ordering each colourway keeps is `digits ≪ ground < fill < cards` (light)
/// or `digits ≫ cards > fill > ground` (dark): the cards stay furthest from the
/// ground so the face never sinks into its own backdrop, and the digits stay
/// furthest from everything so they dominate regardless of what is behind them.
struct Theme: Equatable {
    /// The window's ground — what shows where nothing else is drawn, and what a
    /// drained countdown is.
    var ground: Shade
    /// The flip card's base shade; the two halves are this lifted and dropped
    /// by `CardForm`'s offsets, scaled by `shadeScale`.
    var card: Shade
    /// The digits. Never pure white on a dark ground: white glyphs this size
    /// bloom, and bloom is exactly what a night scheme exists to avoid.
    var digit: Color
    /// The hinge split line cutting through the glyph.
    var hinge: Color
    /// The colon, the stacked layout's dots, and the always-on-top pin.
    var accent: Color
    var badgeText: Color
    var badgeFill: Color
    /// How hard `CardForm`'s luminance offsets bite. Light cards need far less
    /// than dark ones before the gradient turns plastic.
    var shadeScale: Double
    /// The lit plane of the cadence drain.
    var cadenceFill: Color
    /// The window bezel: the perimeter border *and* the window's own
    /// `backgroundColor`, which is what the transparent title-bar strip shows.
    /// One colour used twice, so the strip and the perimeter are one frame.
    var bezel: Color
    var events: EventsPalette

    /// The card shade at a luminance offset, damped per colourway.
    func cardShade(_ delta: CGFloat) -> Color {
        card.adjusted(by: Double(delta) * shadeScale)
    }
}

/// The three colourways. A colourway is the whole app's colour identity —
/// ground, cards, digits, countdown, bezel and calendar alike — not a face skin.
enum Colorway: String, CaseIterable, Identifiable {
    case charcoal
    case slate
    case peach

    var id: String { rawValue }

    var label: String {
        switch self {
        case .charcoal: return "Charcoal"
        case .slate: return "Slate"
        case .peach: return "Peach"
        }
    }

    var theme: Theme {
        switch self {
        case .charcoal:
            // Black ground, near-black cards: the scheme the clock shipped with,
            // carried forward with a bezel and a full-bleed drain.
            return Theme(
                ground: Shade(0.0, 0.0, 0.0),
                card: Shade(0.140, 0.140, 0.140),
                digit: Color(white: 0.94),
                hinge: Color(white: 0.02),
                accent: Color(white: 0.55),
                badgeText: Color(white: 0.58),
                badgeFill: Color.white.opacity(0.07),
                shadeScale: 1.0,
                cadenceFill: Color(red: 0.30, green: 0.215, blue: 0.055),
                // Dark bronze, not the old 0.75-alpha gold hairline: the bezel
                // now includes the whole title-bar band, and that gold at this
                // size is a gold *bar* across the top of the app.
                bezel: Color(red: 0.290, green: 0.208, blue: 0.055),
                events: .onBlack(now: Color(red: 1.0, green: 0.27, blue: 0.23)))

        case .slate:
            // The night scheme. Mid-dark rather than black, so the window reads
            // as a coloured object in a dark room rather than a hole in the
            // desktop; the card sits ~0.07 above the ground, the digits at ~0.85
            // rather than 1.0, and the lit tint only ~0.11 above the ground —
            // unmistakable as a moving edge, invisible as glare when it covers
            // the whole window at 3 a.m.
            return Theme(
                ground: Shade(0.149, 0.184, 0.216),
                card: Shade(0.220, 0.259, 0.298),
                digit: Color(red: 0.824, green: 0.859, blue: 0.886),
                hinge: Color(red: 0.086, green: 0.110, blue: 0.137),
                accent: Color(red: 0.541, green: 0.608, blue: 0.659),
                badgeText: Color(red: 0.565, green: 0.631, blue: 0.682),
                badgeFill: Color.white.opacity(0.08),
                // A dark card has room for a real gradient before it turns
                // plastic, and needs one: it has less contrast with its
                // surroundings to do the shaping with.
                shadeScale: 0.72,
                // Bronze, red-dominant. A warm olive also works against a blue
                // ground, but red above green is what keeps the lit state — the
                // state the window is in most of the time — its own colour.
                cadenceFill: Color(red: 0.318, green: 0.271, blue: 0.200),
                // Below the ground, so the bezel reads as a case around the
                // thing rather than a border drawn on it.
                bezel: Color(red: 0.071, green: 0.094, blue: 0.118),
                events: .onDark(ink: Color(red: 0.851, green: 0.882, blue: 0.906),
                                muted: Color(red: 0.580, green: 0.647, blue: 0.698),
                                // Coral rather than scarlet: full-hot red is the
                                // one colour that survives a dark scheme's
                                // dimming and then dominates it.
                                now: Color(red: 0.914, green: 0.392, blue: 0.353)))

        case .peach:
            // The daylight scheme, and the hardest case: the ground is already
            // warm, so the lit fill has to separate on lightness and saturation
            // rather than on hue.
            return Theme(
                ground: Shade(0.902, 0.769, 0.686),
                card: Shade(0.996, 0.976, 0.957),
                digit: Color(red: 0.235, green: 0.145, blue: 0.110),
                hinge: Color(red: 0.561, green: 0.412, blue: 0.333),
                accent: Color(red: 0.463, green: 0.333, blue: 0.267),
                badgeText: Color(red: 0.451, green: 0.325, blue: 0.259),
                badgeFill: Color.black.opacity(0.07),
                shadeScale: 0.42,
                cadenceFill: Color(red: 1.000, green: 0.937, blue: 0.647),
                // Deep cocoa: the only bezel dark enough to hold a ground this
                // light without reading as a second peach.
                bezel: Color(red: 0.259, green: 0.161, blue: 0.118),
                events: .onLight(ink: Color(red: 0.212, green: 0.129, blue: 0.098),
                                 muted: Color(red: 0.451, green: 0.318, blue: 0.251),
                                 // Crimson, not red: a scarlet now-line on an
                                 // orange ground is the same hue family and
                                 // stops reading as a marker.
                                 now: Color(red: 0.604, green: 0.086, blue: 0.180)))
        }
    }
}

/// What the user picks in Settings. `auto` is a *rule*, not a colourway, which
/// is why it can't just be a fourth `Colorway` case.
enum Appearance: String, CaseIterable, Identifiable {
    case auto
    case charcoal
    case slate
    case peach

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .charcoal: return Colorway.charcoal.label
        case .slate: return Colorway.slate.label
        case .peach: return Colorway.peach.label
        }
    }

    /// The colourway to draw with. `auto` follows the system: dark mode gets
    /// Charcoal, light mode gets Peach. Slate is a deliberate choice only —
    /// it is the *quiet* dark scheme, and picking it for someone because their
    /// Mac is in dark mode would be choosing a taste on their behalf.
    func colorway(for colorScheme: ColorScheme) -> Colorway {
        switch self {
        case .auto: return colorScheme == .dark ? .charcoal : .peach
        case .charcoal: return .charcoal
        case .slate: return .slate
        case .peach: return .peach
        }
    }
}

private struct ThemeKey: EnvironmentKey {
    /// Production always has a theme — the root injects the resolved one before
    /// anything draws. This default exists only so previews and the type system
    /// have something to hold.
    static let defaultValue = Colorway.charcoal.theme
}

extension EnvironmentValues {
    /// The colourway every view draws with, injected once at the window root so
    /// the face, the countdown, the divider, the calendar and the window's own
    /// chrome can never read different values.
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
