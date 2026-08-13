import AppKit
import SwiftUI

/// The third way the clock can convey a cadence boundary: a little character
/// carries a banner with the time across the screen, once, and is gone.
///
/// The sibling of `Announcer` and `NotificationAnnouncer` — same lifetime, same
/// main-actor isolation, same `TimePhrase.display` wording, so all three convey
/// methods can never disagree about what time it is.
///
/// What distinguishes it is that it owns a *window*. Each flight builds its own
/// borderless, transparent overlay spanning one screen, flies the character
/// across it, and closes it when the character is fully offscreen. Nothing is
/// kept alive between flights: an invisible full-screen window sitting around
/// forever is a liability (Space changes, display reconfiguration, click-through
/// regressions) for no gain, since building one is cheap.
///
/// `BannerStyle` chooses who does the carrying. It is a property of the flight,
/// not of the controller: the window, the path, the timing and the teardown are
/// identical either way, so the style travels with the plan into the view and
/// nothing else in here has to know about it.
@MainActor
final class BannerFlightController {

    /// Flights already in the air are independent windows, so a boundary that
    /// lands mid-flight can simply add another. Two at once still reads as
    /// charming; a stack of them would read as a bug, so extras are dropped.
    static let maxConcurrentFlights = 2

    /// Seconds for one crossing. Randomised inside the band so repeated flights
    /// don't feel mechanical.
    static let durationRange: ClosedRange<Double> = 6...8

    /// Strong references are what keep each flight alive: the windows are
    /// created with `isReleasedWhenClosed = false` (the AppKit default of
    /// `true` is a manual-retain-era convention that over-releases under ARC),
    /// so ARC owns them and this array is that ownership.
    private var flights: [NSWindow] = []

    /// Sends one banner across the screen the pointer is on.
    ///
    /// The pointer's screen is the right target for the same reason the events
    /// panel follows the window: it is where the user is looking. With no
    /// screen under the pointer (possible mid-display-change) the main screen
    /// stands in.
    func fly(at date: Date, style: BannerStyle) {
        guard flights.count < Self.maxConcurrentFlights else { return }
        guard let screen = Self.targetScreen() else { return }

        let plan = FlightPlan(
            screen: screen.frame.size,
            duration: .random(in: Self.durationRange),
            style: style
        )
        let window = Self.makeWindow(on: screen)
        window.contentView = NSHostingView(
            rootView: BannerFlightView(text: TimePhrase.display(for: date), plan: plan)
        )
        // Not `makeKeyAndOrderFront`: the overlay must never take focus, and
        // `orderFrontRegardless` shows it without activating Flapjack — which
        // matters most when the user is inside another app's fullscreen Space.
        window.orderFrontRegardless()
        flights.append(window)

        // The window closes on a timer rather than a SwiftUI completion
        // callback: the animation runs inside the hosting view, and a timer
        // that outlives it by a beat is both simpler and impossible to strand.
        Task { [weak self, weak window] in
            try? await Task.sleep(for: .seconds(plan.duration + 0.2))
            guard let self, let window else { return }
            window.orderOut(nil)
            window.close()
            self.flights.removeAll { $0 === window }
        }
    }

    /// A pure ghost: click-through, shadowless, transparent, above everything.
    ///
    /// `.screenSaver` clears ordinary and floating windows, the Dock and the
    /// menu bar, which a banner flying in the top or bottom of the band needs.
    ///
    /// `.canJoinAllSpaces` is what puts the flight on whatever desktop the user
    /// is *currently* viewing rather than the one Flapjack's window lives on
    /// (the main window deliberately does the opposite). `.stationary` keeps it
    /// from being dragged around by a Space swipe mid-flight, and
    /// `.ignoresCycle` keeps it out of ⌘`.
    ///
    /// It does *not* draw over another app's native full-screen Space, and no
    /// window level reaches there. Measured on macOS 26 across six
    /// level/behaviour combinations: all of them appear over a full-screen app
    /// when the owning process is an accessory app and none of them do when it
    /// is a regular, Dock-icon app — `.fullScreenAuxiliary` and macOS 15's
    /// `.canJoinAllApplications` included. The only lever is flipping
    /// `NSApp.activationPolicy` to `.accessory` *before* creating the window
    /// (re-ordering an existing one after the flip does nothing), which would
    /// make Flapjack's Dock icon disappear and come back around every flight.
    /// A boundary that lands while the user is in full screen passes unseen
    /// instead.
    private static func makeWindow(on screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
        ]
        window.setFrame(screen.frame, display: false)
        return window
    }

    private static func targetScreen() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }
}

/// Everything decided once per flight, so the view can stay a pure function of
/// elapsed time.
struct FlightPlan {

    /// Which way the character is pointing — it always leads, and the banner
    /// always trails behind it.
    enum Direction {
        case rightward
        case leftward
    }

    let direction: Direction
    let duration: Double
    let style: BannerStyle

    /// Top-left corner of the assembly's lane, in the view's own coordinates.
    let altitude: CGFloat

    /// Where the assembly starts and ends, offscreen at both ends.
    let startX: CGFloat
    let endX: CGFloat

    /// Total width of character + tow line + banner. Modest by design:
    /// noticeable crossing a 1440-point screen, nowhere near dominating it.
    static let assemblyWidth: CGFloat = 250
    static let assemblyHeight: CGFloat = 54

    /// The tow line is the same length whoever is pulling it; the character's
    /// lane is not, since the cat is both wider and taller than the plane. The
    /// banner takes whatever is left, so the assembly is the same total width
    /// in both styles and the two flights read as the same object.
    static let towLineWidth: CGFloat = 18

    init(screen: CGSize, duration: Double, style: BannerStyle, direction: Direction? = nil) {
        self.direction = direction ?? (Bool.random() ? .rightward : .leftward)
        self.duration = duration
        self.style = style

        // A comfortable band: clear of the menu bar at the top and the Dock at
        // the bottom, so the banner is never half-hidden behind either.
        let top = screen.height * 0.05
        let bottom = max(top, screen.height * 0.90 - Self.assemblyHeight)
        altitude = .random(in: top...bottom)

        let offLeft = -Self.assemblyWidth
        let offRight = screen.width
        switch self.direction {
        case .rightward:
            startX = offLeft
            endX = offRight
        case .leftward:
            startX = offRight
            endX = offLeft
        }
    }
}

/// The flight itself: a character towing a banner, animated straight across on
/// a linear ramp.
///
/// Every moving part — the crossing, the bob, and the cat's wave — is computed
/// from elapsed time inside a `TimelineView(.animation)` rather than handed to
/// SwiftUI as an implicit animation, and that choice was forced by two measured
/// failures of the implicit route on this window.
///
/// First, two `withAnimation` calls in one runloop tick get coalesced into a
/// single transaction: the bob's `repeatForever(autoreverses:)` captured the
/// crossing as well, and the plane flew back and forth across the screen instead
/// of over it. Splitting them into scoped `.animation(_:value:)` modifiers fixed
/// the direction but not the second problem — a `.linear(duration: 7)` offset
/// kicked off from `onAppear` on a just-ordered-front hosting view ran its whole
/// crossing in about 1.5 s, four times too fast, every time.
///
/// Driving the offset from the clock sidesteps both: the frame the character is
/// drawn at is a pure function of how long it has been flying, so the duration
/// is exactly the duration and constant speed is constant by construction. The
/// bob and the wave come off the same clock for free — which is why the paw is
/// a `sin` of elapsed time and not a `repeatForever` rotation, and why it starts
/// waving on the first frame the window is shown rather than whenever the
/// animation system gets round to it.
private struct BannerFlightView: View {
    let text: String
    let plan: FlightPlan

    /// Nil until the view is on screen, so the character waits offscreen rather
    /// than starting its run against a clock that began before it appeared.
    @State private var takeoff: Date?

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = takeoff.map { context.date.timeIntervalSince($0) } ?? 0
            let progress = min(max(elapsed / plan.duration, 0), 1)
            let x = plan.startX + (plan.endX - plan.startX) * progress
            // ~0.3 Hz, ±5 pt: enough to read as flying, not enough to distract.
            let bob = sin(elapsed * 2) * 5

            assembly(elapsed: elapsed)
                .frame(width: FlightPlan.assemblyWidth, height: FlightPlan.assemblyHeight)
                .offset(x: x, y: plan.altitude + bob)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { takeoff = .now }
    }

    /// The character always leads, so the order of the two halves flips with the
    /// direction — but only the character is mirrored. Mirroring the banner too
    /// would reverse the time, which is the one thing the whole flight exists
    /// to show.
    @ViewBuilder
    private func assembly(elapsed: Double) -> some View {
        HStack(spacing: 0) {
            if plan.direction == .rightward {
                banner
                towLine
                character(elapsed: elapsed)
            } else {
                character(elapsed: elapsed)
                towLine
                banner
            }
        }
    }

    /// Both characters are drawn facing right and mirrored as a whole when
    /// flying the other way, so the cat's raised paw stays on its leading side
    /// without any per-direction geometry.
    @ViewBuilder
    private func character(elapsed: Double) -> some View {
        Group {
            switch plan.style {
            case .airplane: plane
            case .cat: cat(elapsed: elapsed)
            }
        }
        .scaleEffect(x: plan.direction == .rightward ? 1 : -1, y: 1)
    }

    // MARK: - Airplane

    private static let planeLaneWidth: CGFloat = 46

    private var plane: some View {
        // The SF Symbol points right, which is what makes mirroring it enough
        // to lead in the other direction too.
        Image(systemName: "airplane")
            .font(.system(size: 34, weight: .regular))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)
            .frame(width: Self.planeLaneWidth)
    }

    // MARK: - Waving cat

    private static let catLaneWidth: CGFloat = 62
    private static let catPointSize: CGFloat = 36

    /// `cat.fill` is a side-on silhouette facing right, standing on all four
    /// legs — available since macOS 14, so it needs no fallback at this
    /// deployment target. The greeting is the part the symbol can't do: a paw
    /// is drawn over the cat's chest as a capsule with a rounded pad on the
    /// end, pivoting about its base so it sweeps rather than slides, in the
    /// same white with the same shadow so it reads as part of the silhouette
    /// rather than a decal on top of it.
    ///
    /// Two waves a second, swinging either side of upright: fast enough to be
    /// unmistakably a wave at a glance from across a 1440-point screen, slow
    /// enough not to blur.
    private func cat(elapsed: Double) -> some View {
        let wave = sin(elapsed * 4 * .pi)
        let angle = Self.pawRestAngle + wave * Self.pawSwing

        return Image(systemName: "cat.fill")
            .font(.system(size: Self.catPointSize, weight: .regular))
            .foregroundStyle(.white)
            .overlay(alignment: .center) { paw(angle: angle) }
            .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)
            .frame(width: Self.catLaneWidth)
    }

    /// Degrees from vertical. Twenty each way, measured against the alternatives
    /// on a contact sheet of both extremes: any wider, or any further forward,
    /// and the top of the stroke lands on the cat's own head, which reads as a
    /// blob rather than a wave.
    private static let pawRestAngle: Double = 0
    private static let pawSwing: Double = 20

    /// Anchored so its base sits inside the cat's shoulder, measured from the
    /// centre of the symbol's box: the join has to be *under* the silhouette or
    /// the wave looks like a floating stick, and the paw has to clear the cat's
    /// back at every angle or it reads as a leg rather than a greeting.
    private static let pawBase = CGPoint(x: 4, y: 1)
    private static let pawLength: CGFloat = 23
    private static let pawWidth: CGFloat = 5

    private func paw(angle: Double) -> some View {
        Capsule(style: .continuous)
            .fill(.white)
            .frame(width: Self.pawWidth, height: Self.pawLength)
            .overlay(alignment: .top) {
                // The pad: a slightly fatter round tip, which is what turns a
                // rotating bar into a paw.
                Circle()
                    .fill(.white)
                    .frame(width: Self.pawWidth + 2, height: Self.pawWidth + 2)
                    .offset(y: -1)
            }
            // Rotating about the base is the whole gesture: the tip travels and
            // the shoulder stays put, which is what a wave is.
            .rotationEffect(.degrees(angle), anchor: .bottom)
            .offset(x: Self.pawBase.x, y: Self.pawBase.y - Self.pawLength / 2)
    }

    // MARK: - Banner

    private var towLine: some View {
        Rectangle()
            .fill(.white.opacity(0.8))
            .frame(width: FlightPlan.towLineWidth, height: 2)
            .shadow(color: .black.opacity(0.5), radius: 2)
    }

    /// Styled to stay readable over anything the user might have on screen: a
    /// near-opaque dark ground, white tabular type, a light hairline border and
    /// a drop shadow so it separates from dark backgrounds as well as light.
    private var banner: some View {
        Text(text)
            .font(.system(size: 24, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 2)
            .frame(width: bannerWidth)
    }

    /// Whatever the character and its tow line leave over, so both styles fill
    /// the same assembly width.
    private var bannerWidth: CGFloat {
        let lane = plan.style == .cat ? Self.catLaneWidth : Self.planeLaneWidth
        return FlightPlan.assemblyWidth - lane - FlightPlan.towLineWidth
    }
}
