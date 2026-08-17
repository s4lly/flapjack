import AppKit
import Foundation

/// A single self-rescheduling timer aimed at the next minute boundary.
/// It drives both the display and the spoken announcements, so the two can
/// never drift apart.
@MainActor
final class ClockEngine: ObservableObject {

    @Published private(set) var now = Date()

    /// Called on every minute boundary (and never for the initial value).
    var onMinute: ((Date) -> Void)?

    /// Called after the clock re-syncs following a system wake. Separate from
    /// `onMinute` because a wake is not a minute boundary: announcements must
    /// not fire, but time-dependent data (e.g. today's events) is stale and
    /// needs a reload.
    var onResync: ((Date) -> Void)?

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var activity: NSObjectProtocol?
    private var started = false

    /// The minute the face is currently showing, so a resync that lands inside
    /// the same minute can skip the republish (and the reload it would trigger)
    /// instead of churning the view tree every time a window is uncovered.
    private var shownMinute: Date?

    func start() {
        guard !started else { return }
        started = true
        beginActivity()
        publish(Date())
        scheduleNextTick()
        observeResyncTriggers()
    }

    // MARK: - App Nap

    /// Opts the process out of App Nap, which is the whole of bug "the clock is
    /// wrong when I'm not looking at it".
    ///
    /// App Nap throttles the timers of an app that is not frontmost and has no
    /// visible windows doing anything interesting — it coalesces them into wide
    /// wake-up buckets, so a timer aimed exactly at the next minute boundary can
    /// fire tens of seconds late. For a clock that is *precisely* the failure
    /// the user sees: Flapjack sits in the corner showing 10:41 while the menu
    /// bar has moved on to 10:43. Nothing about tolerance or run-loop mode can
    /// fix it, because the throttling happens below the run loop.
    ///
    /// The lever is `beginActivity`, and the option set is chosen narrowly:
    ///
    /// - `.userInitiatedAllowingIdleSystemSleep` is the one we want. It declares
    ///   the work user-initiated (which is what makes the process ineligible for
    ///   App Nap and un-throttles its timers) while explicitly *keeping* idle
    ///   system sleep enabled.
    /// - Plain `.userInitiated` is the same thing plus `.idleSystemSleepDisabled`,
    ///   and that is unacceptable: a desk clock must never be the reason a Mac
    ///   refuses to go to sleep. Timers don't need to fire during sleep anyway —
    ///   `NSWorkspace.didWakeNotification` below covers the gap.
    /// - `.latencyCritical` is for real-time media work: it additionally
    ///   suppresses timer coalescing system-wide and is documented as costly to
    ///   battery. A once-a-minute tick that may be a few milliseconds late is
    ///   nobody's latency emergency, so it would be paying a continuous power
    ///   price for precision the face cannot even display.
    /// - `.automaticTerminationDisabled` / `.suddenTerminationDisabled` are
    ///   already handled by the Info.plist keys and say nothing about timers.
    ///
    /// The activity is held for the process's lifetime rather than taken around
    /// each boundary, because the throttling decision is made while the app is
    /// idle *between* boundaries — a token acquired at the boundary would be
    /// acquired after the damage was done.
    private func beginActivity() {
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Flapjack displays and announces the current time on the minute."
        )
    }

    // MARK: - Resync triggers

    /// Everything that can leave the face showing a stale minute. Each one only
    /// corrects the display and reschedules — none of them announce, because a
    /// window being uncovered is not a cadence boundary.
    private func observeResyncTriggers() {
        // Timers don't fire while the Mac sleeps.
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resync() }
        })

        // Belt and braces for the App Nap opt-out: whatever slipped while the
        // app was in the background, the face is right by the time the user has
        // finished clicking on it.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resync() }
        })

        // The user changed the clock, or crossed a timezone: "now" is the same
        // instant but its wall-clock name has changed, so the face is wrong
        // without any time having passed.
        for name in [Notification.Name.NSSystemClockDidChange,
                     Notification.Name.NSSystemTimeZoneDidChange] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.resync(force: true) }
            })
        }
    }

    /// Called by the window layer when the main window becomes visible again
    /// (unminimised, uncovered, or its Space swiped back to). Occlusion is a
    /// separate signal from activation: a clock can sit unfocused-but-visible
    /// for hours, and it can also be hidden while the app is frontmost.
    func windowBecameVisible() {
        resync()
    }

    // MARK: - Ticking

    private func scheduleNextTick() {
        timer?.invalidate()
        guard let next = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) else { return }

        let t = Timer(fireAt: next, interval: 0, target: self,
                      selector: #selector(tick), userInfo: nil, repeats: false)
        t.tolerance = 0
        // .common so it keeps firing while the window is dragged or a menu is open.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func tick() {
        let date = Date()
        publish(date)
        onMinute?(date)
        scheduleNextTick()
    }

    /// Correct the face and re-aim the timer without announcing.
    ///
    /// - Parameter force: republish even when the minute has not changed, for
    ///   the cases where the *instant* is the same but its rendering is not (a
    ///   clock or timezone change).
    private func resync(force: Bool = false) {
        let date = Date()
        let changed = publish(date, force: force)
        scheduleNextTick()
        // Downstream work (reloading today's events) is only warranted when the
        // clock actually moved; an uncovered window shouldn't cost a calendar
        // query.
        if changed { onResync?(date) }
    }

    /// Publishes `date` when it lands in a different minute from the one on
    /// display, and reports whether it did.
    @discardableResult
    private func publish(_ date: Date, force: Bool = false) -> Bool {
        let minute = Calendar.current.dateInterval(of: .minute, for: date)?.start
        guard force || minute == nil || minute != shownMinute else { return false }
        shownMinute = minute
        now = date
        return true
    }

    // `isolated` so the @MainActor-bound timer/observers can be torn down safely
    // (required under the Swift 6 language mode).
    isolated deinit {
        timer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        // Ending the activity is what releases the App Nap opt-out.
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }
}
