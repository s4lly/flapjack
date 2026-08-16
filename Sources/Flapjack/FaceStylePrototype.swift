// PROTOTYPE — throwaway. Round 2.
//
// Round 1 answered the form question: **Classic flip** is the card, so the style
// axis is now locked to it by default (still switchable with ←/→ for
// comparison). What is open is colour, and specifically what a *light* face
// costs: the cadence backdrop was authored as "dark amber lit against black",
// which on a pastel ground inverts into a dirty smudge, and the events panel was
// authored as "dim greys on black", which on a pastel ground is unreadable.
//
// So a palette here is no longer just the face. It is a COMPLETE colourway:
//
//   ground · cards · digits · colon/badge · cadence (fill/track/frame) ·
//   events (rules, chips, text, now-line) · divider
//
// Two axes, switchable live:
//   ←/→  FACE STYLE   1 Current · 2 Classic · 3 Minimal        (default Classic)
//   ↑/↓  COLOURWAY    0 Charcoal · P1 Sage · P2 Lavender · P3 Peach · P4 Powder
//
// The colourway is injected at the *window root* rather than at the face, so the
// cadence fill, the events panel, the divider and the window's own chrome all
// read the same values. With no value in the environment (the flag off) every
// view falls back to its shipped body, byte for byte.
//
// The frame rework (see `WindowFrameOverlay`): the cadence border used to hug
// the face region, which put a bar down the seam between the face and the
// calendar. It is now a window bezel — the same colour as the title-bar strip,
// wrapped around all four window edges, around everything. The cadence fill and
// track stay in the face region as before.
//
// Run with: open dist/Flapjack.app --args -prototypeStyle 1
// No polish, no tests, no accessibility work beyond what falls out for free.

import AppKit
import SwiftUI

// MARK: - Axis 1: face style

enum FaceStyleVariant: Int, CaseIterable {
    case current, classic, minimal

    var label: String {
        switch self {
        case .current: return "1 Current"
        case .classic: return "Classic"
        case .minimal: return "3 Minimal"
        }
    }

    /// Everything about the card's *form* — the palette supplies the colours.
    var spec: FaceStyleSpec {
        switch self {
        case .current:
            // The shipped look, restated in the prototype's own vocabulary:
            // both halves fully rounded (so the hinge corners are round too),
            // the gap merely the VStack's sliver of ground, shadow on.
            return FaceStyleSpec(cornerRadius: 0.06,
                                 squareHingeCorners: false,
                                 hingeGap: 0.012,
                                 paintsHinge: false,
                                 topShades: (0.030, -0.030),
                                 bottomShades: (-0.040, 0.010),
                                 pins: false,
                                 shadow: true)
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

/// The countdown backdrop's three colours.
///
/// The invariant that has to hold in every palette is **lit vs drained**: the
/// fill must read as a panel with the light on and the uncovered track as the
/// same panel with it off. On black that means the fill is *brighter* than the
/// ground. On a pastel ground the same instinct — a dark amber — inverts it into
/// a stain, so every light colourway derives its fill as a saturated warm tint
/// clearly LIGHTER than its ground, and its track as that same tint most of the
/// way back down to the ground.
///
/// The ordering each light palette keeps is
/// `digits ≪ ground < track < fill < cards`: the cards stay the lightest thing
/// on screen so the face never sinks into its own backdrop, and the digits stay
/// the darkest so they dominate regardless of what is behind them.
struct CadenceColorway {
    /// The lit panel.
    var fill: Color
    /// The panel unlit — the fill's full extent, so a half-drained wipe still
    /// says where "full" was.
    var track: Color
    /// The window bezel. Also the window's `backgroundColor`, which is what the
    /// title-bar strip shows, so the strip and the perimeter are one thing.
    var frame: Color

    /// The shipped values, for the flag-off path and the charcoal comparison.
    static let shipped = CadenceColorway(
        fill: Color(red: 0.30, green: 0.215, blue: 0.055),
        track: Color(red: 0.30, green: 0.215, blue: 0.055).opacity(0.32),
        frame: Color(red: 0.72, green: 0.52, blue: 0.13).opacity(0.75))
}

/// The events panel's colours. On black these are dim greys and a hot red; on a
/// pastel ground every one of them has to flip sense — text goes dark, the
/// rules go from white-over-black to black-over-tint, and the now-line has to be
/// deepened or it screams.
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
        seam: Color.white.opacity(0.10),
        seamActive: Color.white.opacity(0.30),
        grip: Color.white.opacity(0.30),
        gripActive: Color.white.opacity(0.70))

    /// The light-ground recipe. Only the hue-carrying colours differ between the
    /// four pastels, so they are the parameters and everything else is shared —
    /// which is what stops one scheme from quietly drifting more legible than
    /// its siblings.
    static func light(ink: Color, muted: Color, now: Color) -> EventsColorway {
        EventsColorway(
            title: ink,
            axis: muted,
            hint: muted,
            gridline: Color.black.opacity(0.13),
            hourGridline: Color.black.opacity(0.28),
            now: now,
            chipWash: 0.38,
            allDayWash: 0.30,
            seam: Color.black.opacity(0.16),
            seamActive: Color.black.opacity(0.42),
            grip: Color.black.opacity(0.34),
            gripActive: Color.black.opacity(0.62))
    }
}

enum FacePalette: Int, CaseIterable {
    case charcoal, sage, lavender, peach, powder

    var label: String {
        switch self {
        case .charcoal: return "0 Charcoal"
        case .sage: return "P1 Sage"
        case .lavender: return "P2 Lavender"
        case .peach: return "P3 Peach"
        case .powder: return "P4 Powder"
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
                    track: Color(red: 0.096, green: 0.069, blue: 0.018),
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
                    track: Color(red: 0.796, green: 0.812, blue: 0.702),
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
                    track: Color(red: 0.820, green: 0.792, blue: 0.843),
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
                    track: Color(red: 0.937, green: 0.827, blue: 0.686),
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
                    track: Color(red: 0.847, green: 0.847, blue: 0.784),
                    frame: Color(red: 0.129, green: 0.216, blue: 0.286)),
                events: .light(ink: Color(red: 0.098, green: 0.161, blue: 0.212),
                               muted: Color(red: 0.278, green: 0.392, blue: 0.467),
                               now: Color(red: 0.729, green: 0.161, blue: 0.145)))
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
