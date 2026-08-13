import AppKit
import SwiftUI

/// The third way the clock can convey a cadence boundary: a little plane tows a
/// banner with the time across the screen, once, and is gone.
///
/// The sibling of `Announcer` and `NotificationAnnouncer` — same lifetime, same
/// main-actor isolation, same `TimePhrase.display` wording, so all three convey
/// methods can never disagree about what time it is.
///
/// What distinguishes it is that it owns a *window*. Each flight builds its own
/// borderless, transparent overlay spanning one screen, flies the plane across
/// it, and closes it when the plane is fully offscreen. Nothing is kept alive
/// between flights: an invisible full-screen window sitting around forever is a
/// liability (Space changes, display reconfiguration, click-through regressions)
/// for no gain, since building one is cheap.
@MainActor
final class AirplaneBannerController {

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

    /// Sends one plane across the screen the pointer is on.
    ///
    /// The pointer's screen is the right target for the same reason the events
    /// panel follows the window: it is where the user is looking. With no
    /// screen under the pointer (possible mid-display-change) the main screen
    /// stands in.
    func fly(at date: Date) {
        guard flights.count < Self.maxConcurrentFlights else { return }
        guard let screen = Self.targetScreen() else { return }

        let plan = FlightPlan(screen: screen.frame.size, duration: .random(in: Self.durationRange))
        let window = Self.makeWindow(on: screen)
        window.contentView = NSHostingView(
            rootView: AirplaneBannerView(text: TimePhrase.display(for: date), plan: plan)
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

/// Everything random about one flight, decided once so the view can stay pure.
struct FlightPlan {

    /// Which way the plane is pointing — it always leads, and the banner always
    /// trails behind it.
    enum Direction {
        case rightward
        case leftward
    }

    let direction: Direction
    let duration: Double

    /// Top-left corner of the assembly's lane, in the view's own coordinates.
    let altitude: CGFloat

    /// Where the assembly starts and ends, offscreen at both ends.
    let startX: CGFloat
    let endX: CGFloat

    /// Total width of plane + tow line + banner. Modest by design: noticeable
    /// crossing a 1440-point screen, nowhere near dominating it.
    static let assemblyWidth: CGFloat = 250
    static let assemblyHeight: CGFloat = 54

    init(screen: CGSize, duration: Double, direction: Direction? = nil) {
        self.direction = direction ?? (Bool.random() ? .rightward : .leftward)
        self.duration = duration

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

/// The flight itself: a plane silhouette towing a banner, animated straight
/// across on a linear ramp.
///
/// The position is computed from elapsed time inside a `TimelineView(.animation)`
/// rather than handed to SwiftUI as an implicit animation, and that choice was
/// forced by two measured failures of the implicit route on this window.
///
/// First, two `withAnimation` calls in one runloop tick get coalesced into a
/// single transaction: the bob's `repeatForever(autoreverses:)` captured the
/// crossing as well, and the plane flew back and forth across the screen instead
/// of over it. Splitting them into scoped `.animation(_:value:)` modifiers fixed
/// the direction but not the second problem — a `.linear(duration: 7)` offset
/// kicked off from `onAppear` on a just-ordered-front hosting view ran its whole
/// crossing in about 1.5 s, four times too fast, every time.
///
/// Driving the offset from the clock sidesteps both: the frame the plane is
/// drawn at is a pure function of how long it has been flying, so the duration
/// is exactly the duration and constant speed is constant by construction. The
/// bob comes off the same clock for free.
private struct AirplaneBannerView: View {
    let text: String
    let plan: FlightPlan

    /// Nil until the view is on screen, so the plane waits offscreen rather
    /// than starting its run against a clock that began before it appeared.
    @State private var takeoff: Date?

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = takeoff.map { context.date.timeIntervalSince($0) } ?? 0
            let progress = min(max(elapsed / plan.duration, 0), 1)
            let x = plan.startX + (plan.endX - plan.startX) * progress
            // ~0.3 Hz, ±5 pt: enough to read as flying, not enough to distract.
            let bob = sin(elapsed * 2) * 5

            assembly
                .frame(width: FlightPlan.assemblyWidth, height: FlightPlan.assemblyHeight)
                .offset(x: x, y: plan.altitude + bob)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { takeoff = .now }
    }

    /// The plane always leads, so the order of the two halves flips with the
    /// direction — but only the plane is mirrored. Mirroring the banner too
    /// would reverse the time, which is the one thing the whole flight exists
    /// to show.
    @ViewBuilder
    private var assembly: some View {
        HStack(spacing: 0) {
            if plan.direction == .rightward {
                banner
                towLine
                plane
            } else {
                plane
                towLine
                banner
            }
        }
    }

    private var plane: some View {
        Image(systemName: "airplane")
            .font(.system(size: 34, weight: .regular))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)
            // The SF Symbol points right; flipping it is what makes the plane
            // lead in the other direction too.
            .scaleEffect(x: plan.direction == .rightward ? 1 : -1, y: 1)
            .frame(width: 46)
    }

    private var towLine: some View {
        Rectangle()
            .fill(.white.opacity(0.8))
            .frame(width: 18, height: 2)
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
            .frame(width: FlightPlan.assemblyWidth - 64)
    }
}
