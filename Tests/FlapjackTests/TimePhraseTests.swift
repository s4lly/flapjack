import Foundation
import Testing

@testable import Flapjack

/// The wording shared by the two convey methods. The point of these is the
/// agreement: whatever the spoken phrase says, the notification title has to
/// name the same time, so a boundary can't announce 10:07 and post 10:08.
///
/// Dates are built in the machine's own zone rather than a pinned UTC one,
/// because `TimePhrase`'s formatters render in the current zone by design — the
/// clock face shows local time, so the phrase has to as well.
@MainActor
@Suite("TimePhrase")
struct TimePhraseTests {

    private func at(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(
            year: 2026, month: 8, day: 9, hour: hour, minute: minute
        ))!
    }

    @Test("Display is a bare 12-hour clock reading")
    func displayIsTwelveHour() {
        #expect(TimePhrase.display(for: at(22, 7)) == "10:07 PM")
        #expect(TimePhrase.display(for: at(9, 5)) == "9:05 AM")
        #expect(TimePhrase.display(for: at(0, 30)) == "12:30 AM")
    }

    @Test("Off the hour, the spoken phrase quotes the displayed time verbatim")
    func spokenMatchesDisplayOffTheHour() {
        let date = at(22, 7)
        #expect(TimePhrase.spoken(for: date) == "It's \(TimePhrase.display(for: date))")
    }

    @Test("On the hour it says o'clock, since voices garble \"10:00 PM\"")
    func onTheHourSaysOClock() {
        #expect(TimePhrase.spoken(for: at(22, 0)) == "It's 10 o'clock")
        #expect(TimePhrase.spoken(for: at(9, 0)) == "It's 9 o'clock")
    }

    @Test("A minute past the hour is back to the full reading")
    func oneMinutePastIsFullReading() {
        #expect(TimePhrase.spoken(for: at(22, 1)) == "It's 10:01 PM")
    }
}
