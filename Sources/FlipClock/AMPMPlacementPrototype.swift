// PROTOTYPE — throwaway. Evaluating AM/PM placements. Delete after a winner is
// folded into ClockFace.
//
// Four structurally different placements for the AM/PM indicator, switchable
// live (arrow keys or the floating pill). Each variant recomputes its own unit
// scale from its own content aspect, so removing the trailing meridiem column
// genuinely makes the digits bigger — that is the thing being evaluated.
//
// Run with: open dist/FlipClock.app --args -prototypeAMPM 1
// No polish, no tests, no accessibility work beyond what falls out for free.

import AppKit
import SwiftUI

// MARK: - Variants

enum ProtoVariant: Int, CaseIterable {
    case baseline, badge, colonSlot, dynamic

    var label: String {
        switch self {
        case .baseline: return "A — Baseline (side column)"
        case .badge: return "B — Card badge"
        case .colonSlot: return "C — Colon slot"
        case .dynamic: return "D — Dynamic"
        }
    }

    var next: ProtoVariant { ProtoVariant(rawValue: (rawValue + 1) % ProtoVariant.allCases.count)! }
    var previous: ProtoVariant {
        let n = ProtoVariant.allCases.count
        return ProtoVariant(rawValue: (rawValue - 1 + n) % n)!
    }
}

/// Where the meridiem actually gets drawn for a given render pass. `dynamic`
/// resolves to one of these at layout time.
enum ProtoPlacement { case sideColumn, badge, colonSlot }

// MARK: - Metrics

/// Same shape as `FaceMetrics`, but parameterised so each placement can derive
/// its own content aspect (and therefore its own unit scale).
struct ProtoMetrics {
    var cardWidth: CGFloat = 0.64
    var gap: CGFloat = 0.08
    var colonWidth: CGFloat = 0.26
    /// 0 when the meridiem doesn't claim a column of its own.
    var meridiemWidth: CGFloat = 0
    var contentHeight: CGFloat = 1.02
    var marginFraction: CGFloat = 0.03

    static func forPlacement(_ placement: ProtoPlacement) -> ProtoMetrics {
        switch placement {
        case .sideColumn:
            return ProtoMetrics(meridiemWidth: 0.27)
        case .badge:
            return ProtoMetrics(meridiemWidth: 0)
        case .colonSlot:
            // Widened just enough to hold "AM" under the dots; still ~1/3 the
            // cost of the full trailing column.
            return ProtoMetrics(colonWidth: 0.34, meridiemWidth: 0)
        }
    }

    /// 4 digit cards + colon (+ meridiem column when present).
    var elementCount: CGFloat { meridiemWidth > 0 ? 6 : 5 }

    var contentWidth: CGFloat {
        4 * cardWidth + colonWidth + meridiemWidth + (elementCount - 1) * gap
    }

    var contentAspect: CGFloat { contentWidth / contentHeight }

    func unit(fitting size: CGSize) -> CGFloat {
        let margin = min(size.width, size.height) * marginFraction
        let available = CGSize(width: max(0, size.width - 2 * margin),
                               height: max(0, size.height - 2 * margin))
        return min(available.width / contentWidth, available.height / contentHeight)
    }
}

// MARK: - Face

/// One face rendered with a concrete placement.
struct ProtoFaceView: View {
    let face: ClockFace
    let placement: ProtoPlacement

    var body: some View {
        GeometryReader { geo in
            let m = ProtoMetrics.forPlacement(placement)
            let unit = m.unit(fitting: geo.size)

            HStack(alignment: .center, spacing: unit * m.gap) {
                FlipDigit(value: face.hourTens, size: unit).id("h1")
                FlipDigit(value: face.hourOnes, size: unit).id("h2")

                colonColumn(unit: unit, metrics: m)

                FlipDigit(value: face.minuteTens, size: unit).id("m1")

                ZStack(alignment: .bottomTrailing) {
                    FlipDigit(value: face.minuteOnes, size: unit).id("m2")
                    if placement == .badge {
                        badge(unit: unit)
                    }
                }

                if placement == .sideColumn {
                    Text(face.meridiem)
                        .font(.system(size: unit * 0.16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: unit * m.meridiemWidth, alignment: .leading)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private func colonColumn(unit: CGFloat, metrics m: ProtoMetrics) -> some View {
        if placement == .colonSlot {
            VStack(spacing: unit * 0.02) {
                Text(":")
                    .font(.system(size: unit * 0.42, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.55))
                Text(face.meridiem)
                    .font(.system(size: unit * 0.15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: unit * m.colonWidth)
        } else {
            Text(":")
                .font(.system(size: unit * 0.42, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.55))
                .frame(width: unit * m.colonWidth)
        }
    }

    private func badge(unit: CGFloat) -> some View {
        Text(face.meridiem)
            .font(.system(size: unit * 0.13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(white: 0.62))
            .padding(.horizontal, unit * 0.035)
            .padding(.vertical, unit * 0.012)
            .background(
                RoundedRectangle(cornerRadius: unit * 0.03, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .padding(unit * 0.045)
    }
}

// MARK: - Switcher

struct AMPMPlacementPrototypeView: View {
    let face: ClockFace

    @AppStorage("prototypeAMPMVariant") private var rawVariant: Int = 0
    @State private var keys = ProtoArrowKeyMonitor()

    private var variant: ProtoVariant { ProtoVariant(rawValue: rawVariant) ?? .baseline }

    var body: some View {
        GeometryReader { geo in
            let placement = resolvedPlacement(in: geo.size)
            ZStack {
                ProtoFaceView(face: face, placement: placement)
                VStack {
                    Spacer()
                    pill(placement: placement, size: geo.size)
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

    /// D: if the window is wider than the with-column face aspect, height binds
    /// and the column is free — keep it. Otherwise width binds, so drop the
    /// column and let the digits have it.
    private func resolvedPlacement(in size: CGSize) -> ProtoPlacement {
        switch variant {
        case .baseline: return .sideColumn
        case .badge: return .badge
        case .colonSlot: return .colonSlot
        case .dynamic:
            guard size.height > 0 else { return .sideColumn }
            let windowAspect = size.width / size.height
            let faceAspect = ProtoMetrics.forPlacement(.sideColumn).contentAspect
            return windowAspect >= faceAspect ? .sideColumn : .badge
        }
    }

    private func pill(placement: ProtoPlacement, size: CGSize) -> some View {
        let unit = ProtoMetrics.forPlacement(placement).unit(fitting: size)
        return HStack(spacing: 8) {
            Button("◀") { rawVariant = variant.previous.rawValue }
            Text(variant.label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
            if variant == .dynamic {
                Text(placement == .sideColumn ? "→ column" : "→ badge")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            Text(String(format: "u=%.0f", unit))
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
final class ProtoArrowKeyMonitor {
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

/// Launch flag: `open dist/FlipClock.app --args -prototypeAMPM 1`
enum ProtoFlag {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "prototypeAMPM") }
}
