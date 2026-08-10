import Foundation

/// How the clock words the time, in the two forms the app needs: one to speak
/// and one to read.
///
/// Both convey methods (voice and notification) go through here so they can
/// never disagree about what time it is — a boundary that speaks "It's 10:07 PM"
/// and posts a banner reading "10:08" would be worse than either alone.
/// The formatters are fixed to `en_US_POSIX` with an explicit pattern rather
/// than a locale-driven style: the spoken phrase is hand-written English, so a
/// 24-hour locale format would produce "It's 22:07" and read badly aloud.
///
/// Main-actor isolated because the two shared `DateFormatter`s are mutable
/// reference types and so not `Sendable`; every caller (the announcer, the
/// notifier, the settings UI) already runs there, so pinning them is free and
/// keeps the formatters out of `nonisolated(unsafe)` territory.
@MainActor
enum TimePhrase {

    /// `10:07 PM`.
    static func display(for date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// What the announcer says. On the hour some voices garble "10:00 PM", so
    /// say "10 o'clock" instead.
    static func spoken(for date: Date, calendar: Calendar = .current) -> String {
        let minute = calendar.dateComponents([.minute], from: date).minute ?? 0
        if minute == 0 {
            return "It's \(hourFormatter.string(from: date)) o'clock"
        }
        return "It's \(display(for: date))"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h"
        return f
    }()
}
