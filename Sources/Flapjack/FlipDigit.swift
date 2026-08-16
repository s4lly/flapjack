import SwiftUI

enum Half { case top, bottom }

/// The card's *form* — everything about a flip card that isn't a colour. All
/// lengths are fractions of the card height, so the card keeps its proportions
/// at every window size.
///
/// One card per digit, cut across the middle by the hinge's split line. The two
/// halves are shaded apart rather than outlined, and the corners either side of
/// the hinge stay **square** — that is the single biggest fidelity lever, since
/// rounding them makes one card look like two stacked tiles.
enum CardForm {
    /// Outer corner radius. References run ~8–10 % of card height.
    static let cornerRadius: CGFloat = 0.095
    /// The hinge's split line: a dark hairline cutting straight through the
    /// glyph. Thin enough to read as a seam rather than a gap.
    static let splitLine: CGFloat = 0.010
    /// The split line spans the card's width exactly, since it *is* the card's
    /// waist rather than a decoration laid on it.
    static let cardWidth: CGFloat = 0.64

    /// Luminance offsets from the card's base shade: (top of the half, bottom of
    /// the half). Light from above, gently — the top half sits slightly lighter
    /// than the bottom one, which is what makes the two halves read as two faces
    /// of one object rather than as two colours.
    static let topShades: (CGFloat, CGFloat) = (0.028, 0.000)
    static let bottomShades: (CGFloat, CGFloat) = (-0.024, -0.004)

    static func gradient(for half: Half, theme: Theme) -> LinearGradient {
        let pair = half == .top ? topShades : bottomShades
        return LinearGradient(colors: [theme.cardShade(pair.0), theme.cardShade(pair.1)],
                              startPoint: .top, endPoint: .bottom)
    }

    /// Outer corners rounded, hinge corners square.
    static func shape(for half: Half, size: CGFloat) -> UnevenRoundedRectangle {
        let outer = size * cornerRadius
        return half == .top
            ? UnevenRoundedRectangle(topLeadingRadius: outer, bottomLeadingRadius: 0,
                                     bottomTrailingRadius: 0, topTrailingRadius: outer,
                                     style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: outer,
                                     bottomTrailingRadius: outer, topTrailingRadius: 0,
                                     style: .continuous)
    }
}

/// One half of a split-flap card: the glyph is drawn whole, then clipped.
struct HalfCard: View {
    let text: String
    let half: Half
    let size: CGFloat

    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: size * 0.86, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(theme.digit)
            .frame(width: size * CardForm.cardWidth, height: size)
            .background(CardForm.gradient(for: half, theme: theme))
            .frame(height: size / 2, alignment: half == .top ? .top : .bottom)
            .clipped()
            .clipShape(CardForm.shape(for: half, size: size))
    }
}

/// The hinge's split line, drawn *behind* the two halves so it shows through the
/// gap between them and a flipping half sweeps over it.
///
/// Painted rather than left transparent: on a light colourway the ground behind
/// the card is nowhere near dark enough to read as a crease, so letting it show
/// through would make the hinge vanish exactly where the card needs it most.
private struct HingeLine: View {
    let size: CGFloat

    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.hinge)
            // Same one-point floor the stack's spacing takes, or the painted
            // line stops filling the gap on a small window — which is the size
            // at which the hinge is the only card cue still legible.
            .frame(width: size * CardForm.cardWidth,
                   height: max(1, size * CardForm.splitLine))
            .allowsHitTesting(false)
    }
}

/// A single split-flap digit: the old top half falls away, then the new bottom
/// half swings up. The two phases are sequential — that asymmetry is what sells
/// the mechanical weight.
struct FlipDigit: View {
    let value: String
    let size: CGFloat

    @State private var old = ""
    @State private var topAngle: Double = 0
    @State private var bottomAngle: Double = 0

    private static let phase = 0.14

    var body: some View {
        ZStack {
            HingeLine(size: size)

            VStack(spacing: max(1, size * CardForm.splitLine)) {
                ZStack {
                    HalfCard(text: value, half: .top, size: size)
                    HalfCard(text: old, half: .top, size: size)
                        .rotation3DEffect(.degrees(topAngle), axis: (x: 1, y: 0, z: 0),
                                          anchor: .bottom, anchorZ: 0, perspective: 0.5)
                }
                ZStack {
                    HalfCard(text: old, half: .bottom, size: size)
                    HalfCard(text: value, half: .bottom, size: size)
                        .rotation3DEffect(.degrees(bottomAngle), axis: (x: 1, y: 0, z: 0),
                                          anchor: .top, anchorZ: 0, perspective: 0.5)
                }
            }
        }
        .onAppear { old = value }
        .onChange(of: value) { _, newValue in flip(to: newValue) }
    }

    private func flip(to newValue: String) {
        topAngle = 0
        bottomAngle = 90
        withAnimation(.easeIn(duration: Self.phase)) { topAngle = -90 }
        withAnimation(.easeOut(duration: Self.phase).delay(Self.phase)) { bottomAngle = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.phase * 2) {
            old = newValue
            topAngle = 0
        }
    }
}
