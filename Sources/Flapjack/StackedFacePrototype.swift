// PROTOTYPE — throwaway. Evaluating whether the face should stack HH over MM
// when the events column squeezes it into a tall, narrow region. Delete once a
// winner is folded into ClockFace.
//
// Four structurally different layouts, switchable live (←/→ or the floating
// pill). Each derives its own unit scale from its own content aspect, so the
// stacked variants genuinely make the digits bigger in a narrow region — that
// is the thing being evaluated.
//
// Run with: open dist/Flapjack.app --args -prototypeStack 1
// No polish, no tests, no accessibility work beyond what falls out for free.

import AppKit
import SwiftUI

// MARK: - Variants

enum StackVariant: Int, CaseIterable {
    case baseline, stacked, stackedSeparator, auto

    var label: String {
        switch self {
        case .baseline: return "A — Baseline (HH:MM)"
        case .stacked: return "B — Stacked"
        case .stackedSeparator: return "C — Stacked + separator"
        case .auto: return "D — Auto"
        }
    }

    var next: StackVariant {
        StackVariant(rawValue: (rawValue + 1) % StackVariant.allCases.count)!
    }

    var previous: StackVariant {
        let n = StackVariant.allCases.count
        return StackVariant(rawValue: (rawValue - 1 + n) % n)!
    }
}

/// What actually gets drawn for a given render pass. `auto` resolves to one of
/// these at layout time.
enum StackLayout { case horizontal, stacked, stackedSeparator }

// MARK: - Metrics

/// Same shape as `FaceMetrics`, but parameterised so each layout derives its own
/// content aspect (and therefore its own unit scale).
struct StackMetrics {
    var cardWidth: CGFloat = 0.64
    var gap: CGFloat = 0.08
    var colonWidth: CGFloat = 0.26
    /// Vertical space between the hour row and the minute row. Zero for the
    /// single-row horizontal layout.
    var rowGap: CGFloat = 0
    /// One card is 1.02 tall (two halves plus the sliver between them).
    var cardHeight: CGFloat = 1.02
    var rows: CGFloat = 1
    var marginFraction: CGFloat = 0.03

    static func forLayout(_ layout: StackLayout) -> StackMetrics {
        switch layout {
        case .horizontal:
            return StackMetrics()
        case .stacked:
            return StackMetrics(rowGap: 0.10, rows: 2)
        case .stackedSeparator:
            // Wider gutter so the dots have somewhere to sit without crowding
            // either row.
            return StackMetrics(rowGap: 0.26, rows: 2)
        }
    }

    /// Horizontal: 4 cards + colon with 4 gaps. Stacked: 2 cards, 1 gap.
    var contentWidth: CGFloat {
        rows > 1 ? 2 * cardWidth + gap : 4 * cardWidth + colonWidth + 4 * gap
    }

    var contentHeight: CGFloat { rows * cardHeight + (rows - 1) * rowGap }

    var contentAspect: CGFloat { contentWidth / contentHeight }

    func unit(fitting size: CGSize) -> CGFloat {
        let margin = min(size.width, size.height) * marginFraction
        let available = CGSize(width: max(0, size.width - 2 * margin),
                               height: max(0, size.height - 2 * margin))
        return min(available.width / contentWidth, available.height / contentHeight)
    }
}

// MARK: - Face

/// One face rendered with a concrete layout.
struct StackFaceView: View {
    let face: ClockFace
    let layout: StackLayout

    var body: some View {
        GeometryReader { geo in
            let m = StackMetrics.forLayout(layout)
            let unit = m.unit(fitting: geo.size)

            Group {
                if layout == .horizontal {
                    horizontalFace(unit: unit, metrics: m)
                } else {
                    stackedFace(unit: unit, metrics: m)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(face.spokenLabel)
    }

    private func horizontalFace(unit: CGFloat, metrics m: StackMetrics) -> some View {
        HStack(alignment: .center, spacing: unit * m.gap) {
            FlipDigit(value: face.hourTens, size: unit).id("h1")
            FlipDigit(value: face.hourOnes, size: unit).id("h2")

            Text(":")
                .font(.system(size: unit * 0.42, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.55))
                .frame(width: unit * m.colonWidth)

            FlipDigit(value: face.minuteTens, size: unit).id("m1")
            minuteOnesCard(unit: unit)
        }
    }

    /// Hours on top, minutes below. No colon: the two rows already read as two
    /// pairs, so the separator is the thing C is testing.
    private func stackedFace(unit: CGFloat, metrics m: StackMetrics) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: unit * m.gap) {
                FlipDigit(value: face.hourTens, size: unit).id("h1")
                FlipDigit(value: face.hourOnes, size: unit).id("h2")
            }

            if layout == .stackedSeparator {
                separator(unit: unit, metrics: m)
            } else {
                Spacer(minLength: 0).frame(height: unit * m.rowGap)
            }

            HStack(spacing: unit * m.gap) {
                FlipDigit(value: face.minuteTens, size: unit).id("m1")
                minuteOnesCard(unit: unit)
            }
        }
    }

    /// The colon's two dots, turned on their side into the row gutter.
    private func separator(unit: CGFloat, metrics m: StackMetrics) -> some View {
        HStack(spacing: unit * 0.09) {
            Circle().frame(width: unit * 0.055, height: unit * 0.055)
            Circle().frame(width: unit * 0.055, height: unit * 0.055)
        }
        .foregroundStyle(Color(white: 0.55))
        .frame(height: unit * m.rowGap)
    }

    /// The badge is layered over the finished card rather than inside it, so it
    /// stays put while the halves flip.
    private func minuteOnesCard(unit: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            FlipDigit(value: face.minuteOnes, size: unit).id("m2")
            MeridiemBadge(text: face.meridiem, unit: unit)
        }
    }
}

// MARK: - Switcher

struct StackedFacePrototypeView: View {
    let face: ClockFace

    @AppStorage("prototypeStackVariant") private var rawVariant: Int = 0
    @State private var keys = StackArrowKeyMonitor()

    /// Region aspect (width / height) at which the two layouts yield the same
    /// unit — below it stacking wins, above it the 4-across face wins. Derived
    /// rather than guessed: in the band where the horizontal face is width-bound
    /// and the stacked face is height-bound, the crossover is simply the ratio of
    /// their content extents. Measured at ~1.47 for the current proportions,
    /// which is why a hand-picked 2.0 threshold was wrong.
    static var autoAspectThreshold: CGFloat {
        StackMetrics.forLayout(.horizontal).contentWidth
            / StackMetrics.forLayout(.stacked).contentHeight
    }

    private var variant: StackVariant { StackVariant(rawValue: rawVariant) ?? .baseline }

    var body: some View {
        GeometryReader { geo in
            let layout = resolvedLayout(in: geo.size)
            ZStack {
                StackFaceView(face: face, layout: layout)
                VStack {
                    Spacer()
                    pill(layout: layout, size: geo.size)
                        .padding(.bottom, 6)
                }
            }
        }
        .onAppear {
            keys.start(
                left: { rawVariant = variant.previous.rawValue },
                right: { rawVariant = variant.next.rawValue }
            )
        }
        .onDisappear { keys.stop() }
    }

    private func resolvedLayout(in size: CGSize) -> StackLayout {
        switch variant {
        case .baseline: return .horizontal
        case .stacked: return .stacked
        case .stackedSeparator: return .stackedSeparator
        case .auto:
            guard size.height > 0 else { return .horizontal }
            // Equivalent to the aspect test above outside the degenerate bands,
            // and correct inside them: just take whichever layout draws bigger.
            let horizontal = StackMetrics.forLayout(.horizontal).unit(fitting: size)
            let stacked = StackMetrics.forLayout(.stacked).unit(fitting: size)
            return stacked > horizontal ? .stacked : .horizontal
        }
    }

    private func pill(layout: StackLayout, size: CGSize) -> some View {
        let unit = StackMetrics.forLayout(layout).unit(fitting: size)
        let aspect = size.height > 0 ? size.width / size.height : 0
        return HStack(spacing: 8) {
            Button("◀") { rawVariant = variant.previous.rawValue }
            Text(variant.label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
            if variant == .auto {
                Text(String(format: "%@ (x%.2f)",
                            layout == .horizontal ? "→ horizontal" : "→ stacked",
                            Self.autoAspectThreshold))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            Text(String(format: "u=%.0f a=%.2f", unit, aspect))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.45))
            Button("▶") { rawVariant = variant.next.rawValue }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(Color.white.opacity(0.8))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.13)))
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}

/// Local ←/→ monitor, live only while the prototype view is on screen.
@MainActor
final class StackArrowKeyMonitor {
    private var monitor: Any?

    func start(left: @escaping @MainActor () -> Void, right: @escaping @MainActor () -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 123: MainActor.assumeIsolated { left() }; return nil
            case 124: MainActor.assumeIsolated { right() }; return nil
            default: return event
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Launch flag: `open dist/Flapjack.app --args -prototypeStack 1`
enum StackProtoFlag {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "prototypeStack") }
}
