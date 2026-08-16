// PROTOTYPE — throwaway. Answering "what face styling makes Flapjack look like a
// real flip clock, and which colour palettes work?" The current face is
// structurally right but reads as two stacked rounded tiles rather than one
// hinged card, so it never quite says "flip clock".
//
// Two independent axes, switchable live:
//   ←/→  FACE STYLE   1 Current · 2 Classic flip · 3 Minimal flip
//   ↑/↓  PALETTE      A Charcoal · B Daylight · C Pastel · D Mono
//
// The style/palette pair is pushed down as an environment value, so the *same*
// HalfCard the flip animation rotates carries the treatment — no separate
// "static" rendering that the animation would break out of. With no value in
// the environment (i.e. the flag off) every view falls back to its shipped
// body, byte for byte.
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
        case .classic: return "2 Classic"
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

// MARK: - Axis 2: palette

enum FacePalette: Int, CaseIterable {
    case charcoal, daylight, pastel, mono

    var label: String {
        switch self {
        case .charcoal: return "A Charcoal"
        case .daylight: return "B Daylight"
        case .pastel: return "C Pastel"
        case .mono: return "D Mono"
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
                shadeScale: 1.0)
        case .daylight:
            // Paper flip calendar: warm light ground, cream cards, ink digits.
            return FaceTheme(
                ground: Shade(0.929, 0.902, 0.851),
                card: Shade(0.984, 0.969, 0.941),
                digit: Color(red: 0.16, green: 0.14, blue: 0.12),
                // Darker than a literal cast shadow would be: on a cream card a
                // "correct" soft grey crease vanishes at small sizes, and the
                // hinge is the cue that has to survive.
                hinge: Color(red: 0.55, green: 0.51, blue: 0.45),
                accent: Color(red: 0.46, green: 0.42, blue: 0.37),
                badgeText: Color(red: 0.42, green: 0.38, blue: 0.33),
                badgeFill: Color.black.opacity(0.06),
                shadow: Color(red: 0.35, green: 0.28, blue: 0.20).opacity(0.28),
                shadeScale: 0.45)
        case .pastel:
            // Muted sage ground, cool off-white cards, deep grey digits.
            return FaceTheme(
                ground: Shade(0.749, 0.792, 0.741),
                card: Shade(0.925, 0.941, 0.914),
                digit: Color(red: 0.18, green: 0.21, blue: 0.19),
                hinge: Color(red: 0.42, green: 0.48, blue: 0.42),
                accent: Color(red: 0.40, green: 0.46, blue: 0.40),
                badgeText: Color(red: 0.36, green: 0.42, blue: 0.36),
                badgeFill: Color.black.opacity(0.06),
                shadow: Color(red: 0.20, green: 0.26, blue: 0.20).opacity(0.26),
                shadeScale: 0.45)
        case .mono:
            // High-contrast minimal: white cards on pure black, black digits,
            // no shading at all.
            return FaceTheme(
                ground: Shade(0.0, 0.0, 0.0),
                card: Shade(1.0, 1.0, 1.0),
                digit: Color(white: 0.04),
                hinge: Color(white: 0.0),
                accent: Color(white: 0.85),
                badgeText: Color(white: 0.30),
                badgeFill: Color.black.opacity(0.08),
                shadow: Color.black.opacity(0.0),
                shadeScale: 0.0)
        }
    }
}

/// A colour expressed in components so the card shading can be derived from the
/// base rather than hand-listed per palette — that is what keeps the gradient
/// coherent when the ground goes from black to cream.
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
    /// `nil` means "draw the shipped face" — the flag-off path never touches a
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

    private var pin: some View {
        Capsule(style: .continuous)
            .fill(style.theme.ground.color)
            .frame(width: size * 0.034, height: size * 0.070)
    }
}

// MARK: - Prototype ground + face

/// Stands in for `Color.black` at the window root while the flag is set.
struct FaceStyleProtoGround: View {
    @AppStorage("prototypeFacePalette") private var rawPalette: Int = 0

    var body: some View {
        (FacePalette(rawValue: rawPalette) ?? .charcoal).theme.ground.color
            .ignoresSafeArea()
    }
}

/// Stands in for `ClockFaceView` while the flag is set: same face, plus the
/// environment injection and the switcher pill.
struct FaceStyleProtoFace: View {
    let face: ClockFace

    @AppStorage("prototypeFaceStyle") private var rawStyle: Int = 0
    @AppStorage("prototypeFacePalette") private var rawPalette: Int = 0
    @State private var keys = StyleArrowKeyMonitor()

    private var variant: FaceStyleVariant { FaceStyleVariant(rawValue: rawStyle) ?? .current }
    private var palette: FacePalette { FacePalette(rawValue: rawPalette) ?? .charcoal }

    var body: some View {
        ZStack {
            ClockFaceView(face: face)
                .environment(\.faceRenderStyle,
                             FaceRenderStyle(spec: variant.spec, theme: palette.theme))
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

    /// Neutral grey chrome on purpose: the pill has to stay legible on a black
    /// ground and on a cream one without being restyled per palette.
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
        .foregroundStyle(Color.white.opacity(0.85))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.55)))
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
