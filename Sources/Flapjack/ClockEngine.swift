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
    private var wakeObserver: NSObjectProtocol?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        now = Date()
        scheduleNextTick()

        // Timers don't fire while the Mac sleeps; resync on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resync() }
        }
    }

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
        now = date
        onMinute?(date)
        scheduleNextTick()
    }

    private func resync() {
        let date = Date()
        now = date
        scheduleNextTick()
        onResync?(date)
    }

    // `isolated` so the @MainActor-bound timer/observer can be torn down safely
    // (required under the Swift 6 language mode).
    isolated deinit {
        timer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }
}
