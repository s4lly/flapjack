import SwiftUI

enum Half { case top, bottom }

/// One half of a split-flap card: the glyph is drawn whole, then clipped.
struct HalfCard: View {
    let text: String
    let half: Half
    let size: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: size * 0.86, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Color(white: 0.94))
            .frame(width: size * 0.64, height: size)
            .background(
                LinearGradient(
                    colors: half == .top
                        ? [Color(white: 0.17), Color(white: 0.11)]
                        : [Color(white: 0.10), Color(white: 0.15)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(height: size / 2, alignment: half == .top ? .top : .bottom)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: size * 0.06, style: .continuous))
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
        VStack(spacing: max(1, size * 0.012)) {
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
        .shadow(color: .black.opacity(0.5), radius: size * 0.04, y: size * 0.02)
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
