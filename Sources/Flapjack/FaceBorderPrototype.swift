// PROTOTYPE — throwaway. Evaluating what border treatment around the clock-face
// region best makes the cadence fill's right-to-left drain legible: with no
// frame, a half-drained fill gives no cue of "how full is full". Delete once a
// winner is folded into CadenceFill/ContentView.
//
// Four structurally different treatments, switchable live (←/→ or the floating
// pill). Every treatment hugs the FACE REGION ONLY — this view is planted where
// the face's own ZStack lives, so the events panel and the divider are outside
// it by construction.
//
// Run with: open dist/Flapjack.app --args -prototypeBorder 1
// No polish, no tests, no accessibility work beyond what falls out for free.

import AppKit
import SwiftUI

// MARK: - Variants

enum FaceBorderVariant: Int, CaseIterable {
    case none, outline, track, frameAlways

    var label: String {
        switch self {
        case .none: return "A — None (baseline)"
        case .outline: return "B — Outline (amber stroke)"
        case .track: return "C — Track (ghost fill)"
        case .frameAlways: return "D — Frame always (gray)"
        }
    }

    var next: FaceBorderVariant {
        FaceBorderVariant(rawValue: (rawValue + 1) % FaceBorderVariant.allCases.count)!
    }

    var previous: FaceBorderVariant {
        let n = FaceBorderVariant.allCases.count
        return FaceBorderVariant(rawValue: (rawValue - 1 + n) % n)!
    }
}

// MARK: - Treatment palette

enum FaceBorderStyle {
    /// B's stroke: the fill's hue lifted well above the fill's own luminance so
    /// the empty track inside the frame still has an edge to be empty *against*,
    /// then damped with opacity so it never competes with the digits.
    static let outlineColor = Color(red: 0.72, green: 0.52, blue: 0.13).opacity(0.75)
    static let outlineWidth: CGFloat = 2

    /// C's ghost: the same panel colour at roughly a quarter strength, so the
    /// full extent reads as an unlit track rather than a second fill.
    static let ghostOpacity: Double = 0.28

    /// D's frame: neutral and dim enough to sit under the fill without tinting
    /// it, but still visible on black at all times.
    static let frameColor = Color(white: 0.30)
    static let frameWidth: CGFloat = 1
}

// MARK: - Track fill (variant C)

/// A parallel of `CadenceFillView` that draws the fill's *full* extent as a
/// faint ghost with the bright fill draining inside it — the progress-bar-track
/// idiom. Same schedule, same curves; only the rendering differs.
struct TrackCadenceFillView: View {
    let schedule: CadenceSchedule

    @State private var lastFraction: Double = 1

    var body: some View {
        GeometryReader { geo in
            let radius = FaceMetrics.unit(fitting: geo.size) * CadenceFillView.cornerRadiusUnits
            TimelineView(.periodic(from: .now, by: CadenceFillView.creepDuration)) { context in
                let fraction = schedule.fractionRemaining(at: context.date) ?? 0
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(CadenceFillView.panelColor.opacity(FaceBorderStyle.ghostOpacity))

                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(CadenceFillView.panelColor)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: geo.size.width * fraction,
                                       height: geo.size.height)
                        }
                        .animation(
                            fraction > lastFraction
                                ? .easeOut(duration: CadenceFillView.refillDuration)
                                : .linear(duration: CadenceFillView.creepDuration),
                            value: fraction
                        )
                        .onChange(of: fraction) { _, new in lastFraction = new }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Prototype face region

/// Stands in for the face's own ZStack (backdrop + clock) while the prototype
/// flag is set, adding whichever border treatment is selected.
struct FaceBorderPrototypeView: View {
    let schedule: CadenceSchedule
    /// Whether a cadence backdrop would be drawn at all today — B and C key off
    /// this (nothing to frame with the cadence off), D deliberately ignores it.
    let cadenceActive: Bool
    let face: ClockFace

    @AppStorage("prototypeBorderVariant") private var rawVariant: Int = 0
    @State private var keys = BorderArrowKeyMonitor()

    private var variant: FaceBorderVariant { FaceBorderVariant(rawValue: rawVariant) ?? .none }

    var body: some View {
        GeometryReader { geo in
            let radius = FaceMetrics.unit(fitting: geo.size) * CadenceFillView.cornerRadiusUnits
            ZStack {
                backdrop(radius: radius)
                ClockFaceView(face: face)
                VStack {
                    Spacer()
                    pill.padding(.bottom, 6)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            keys.start(
                left: { rawVariant = variant.previous.rawValue },
                right: { rawVariant = variant.next.rawValue }
            )
        }
        .onDisappear { keys.stop() }
    }

    /// `strokeBorder` rather than `stroke` so the line lands wholly inside the
    /// region — a centred stroke would spill half its width onto the divider.
    @ViewBuilder
    private func backdrop(radius: CGFloat) -> some View {
        switch variant {
        case .none:
            if cadenceActive { CadenceFillView(schedule: schedule) }

        case .outline:
            if cadenceActive {
                CadenceFillView(schedule: schedule)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(FaceBorderStyle.outlineColor,
                                  lineWidth: FaceBorderStyle.outlineWidth)
                    .allowsHitTesting(false)
            }

        case .track:
            if cadenceActive { TrackCadenceFillView(schedule: schedule) }

        case .frameAlways:
            if cadenceActive { CadenceFillView(schedule: schedule) }
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(FaceBorderStyle.frameColor,
                              lineWidth: FaceBorderStyle.frameWidth)
                .allowsHitTesting(false)
        }
    }

    private var pill: some View {
        HStack(spacing: 8) {
            Button("◀") { rawVariant = variant.previous.rawValue }
            Text(variant.label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
            Text(cadenceActive ? "cadence on" : "cadence off")
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
final class BorderArrowKeyMonitor {
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

/// Launch flag: `open dist/Flapjack.app --args -prototypeBorder 1`
enum BorderProtoFlag {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "prototypeBorder") }
}
