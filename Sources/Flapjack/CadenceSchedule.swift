import Foundation

/// When the clock speaks, expressed as a pure value so both the announcement
/// decision and the countdown visual read from the same rules.
///
/// Every mode's boundaries are anchored to the top of the hour, exactly as
/// `AppSettings.shouldAnnounce` has always been: a minute-of-hour is a boundary
/// when it is a multiple of `stepMinutes`. That makes the top of every hour a
/// boundary in all modes, which matters when the step does not divide 60 — with
/// N = 7 the boundaries are :00, :07 … :56 and then :00 of the *next* hour, so
/// the last gap of the hour is a short one (4 minutes rather than 7). The
/// countdown therefore measures against the actual gap between the surrounding
/// boundaries rather than against a nominal N, so the fill always starts full
/// and always reaches empty.
struct CadenceSchedule: Equatable {
    let mode: AnnounceMode
    let customMinutes: Int

    init(mode: AnnounceMode, customMinutes: Int) {
        self.mode = mode
        self.customMinutes = customMinutes
    }

    /// Spacing between boundaries within the hour, in minutes. `nil` when the
    /// clock never speaks on a cadence, which is the "no schedule" signal every
    /// query below propagates.
    var stepMinutes: Int? {
        switch mode {
        case .off: return nil
        case .hourly: return 60
        case .everyQuarter: return 15
        case .custom: return customMinutes > 0 ? customMinutes : nil
        }
    }

    /// Whether the given minute-of-hour is an announcement boundary.
    func isBoundary(minuteOfHour minute: Int) -> Bool {
        guard let step = stepMinutes else { return false }
        return minute % step == 0
    }

    /// The first boundary strictly after `date` — so a date sitting exactly on a
    /// boundary reports the *following* one, which is what a countdown wants.
    func nextAnnouncement(after date: Date, calendar: Calendar = .current) -> Date? {
        guard let step = stepMinutes, let hourStart = Self.hourStart(of: date, calendar: calendar) else {
            return nil
        }
        let minute = Self.minutesElapsed(from: hourStart, to: date)
        let next = (Int(minute.rounded(.down)) / step + 1) * step
        if next < 60 {
            return hourStart.addingTimeInterval(TimeInterval(next) * 60)
        }
        // Past the last in-hour boundary: the top of the next hour. Added via
        // the calendar rather than +3600 so a DST transition lands correctly.
        return calendar.date(byAdding: .hour, value: 1, to: hourStart)
    }

    /// The most recent boundary at or before `date`.
    func previousAnnouncement(onOrBefore date: Date, calendar: Calendar = .current) -> Date? {
        guard let step = stepMinutes, let hourStart = Self.hourStart(of: date, calendar: calendar) else {
            return nil
        }
        let minute = Self.minutesElapsed(from: hourStart, to: date)
        let previous = (Int(minute.rounded(.down)) / step) * step
        return hourStart.addingTimeInterval(TimeInterval(previous) * 60)
    }

    /// How much of the current gap between boundaries is still ahead, in 0…1.
    /// 1 exactly on a boundary (the fill has just been topped up) falling to ~0
    /// as the next one arrives. `nil` when there is no cadence.
    func fractionRemaining(at date: Date, calendar: Calendar = .current) -> Double? {
        guard let next = nextAnnouncement(after: date, calendar: calendar),
              let previous = previousAnnouncement(onOrBefore: date, calendar: calendar)
        else { return nil }
        let span = next.timeIntervalSince(previous)
        guard span > 0 else { return nil }
        let remaining = next.timeIntervalSince(date) / span
        return min(1, max(0, remaining))
    }

    private static func hourStart(of date: Date, calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .hour, for: date)?.start
    }

    private static func minutesElapsed(from hourStart: Date, to date: Date) -> Double {
        max(0, date.timeIntervalSince(hourStart) / 60)
    }
}
