import Foundation
import Testing

@testable import Flapjack

/// A fixed calendar so the boundary maths never depends on the machine's zone.
private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    utc.date(from: DateComponents(
        timeZone: TimeZone(identifier: "UTC"),
        year: 2026, month: 8, day: 9, hour: hour, minute: minute, second: second
    ))!
}

@Suite("CadenceSchedule")
struct CadenceScheduleTests {

    // MARK: - Off

    @Test("Off has no schedule at all")
    func offHasNoSchedule() {
        let schedule = CadenceSchedule(mode: .off, customMinutes: 30)
        #expect(schedule.stepMinutes == nil)
        #expect(schedule.nextAnnouncement(after: at(10, 7), calendar: utc) == nil)
        #expect(schedule.previousAnnouncement(onOrBefore: at(10, 7), calendar: utc) == nil)
        #expect(schedule.fractionRemaining(at: at(10, 7), calendar: utc) == nil)
        #expect(schedule.isBoundary(minuteOfHour: 0) == false)
    }

    // MARK: - Hourly / quarter

    @Test("Hourly targets the top of the next hour")
    func hourly() {
        let schedule = CadenceSchedule(mode: .hourly, customMinutes: 7)
        #expect(schedule.nextAnnouncement(after: at(10, 7), calendar: utc) == at(11, 0))
        #expect(schedule.previousAnnouncement(onOrBefore: at(10, 7), calendar: utc) == at(10, 0))
        // Exactly on the hour: the *next* one, so a fresh interval begins.
        #expect(schedule.nextAnnouncement(after: at(10, 0), calendar: utc) == at(11, 0))
        #expect(schedule.previousAnnouncement(onOrBefore: at(10, 0), calendar: utc) == at(10, 0))
    }

    @Test("Every 15 lands on :00 :15 :30 :45")
    func quarters() {
        let schedule = CadenceSchedule(mode: .everyQuarter, customMinutes: 7)
        #expect(schedule.nextAnnouncement(after: at(10, 0), calendar: utc) == at(10, 15))
        #expect(schedule.nextAnnouncement(after: at(10, 14, 59), calendar: utc) == at(10, 15))
        #expect(schedule.nextAnnouncement(after: at(10, 15), calendar: utc) == at(10, 30))
        #expect(schedule.nextAnnouncement(after: at(10, 46), calendar: utc) == at(11, 0))
        for minute in [0, 15, 30, 45] {
            #expect(schedule.isBoundary(minuteOfHour: minute))
        }
        #expect(schedule.isBoundary(minuteOfHour: 14) == false)
    }

    // MARK: - Custom intervals

    @Test("A custom interval that divides 60 spaces evenly")
    func customDividingSixty() {
        let schedule = CadenceSchedule(mode: .custom, customMinutes: 2)
        #expect(schedule.nextAnnouncement(after: at(10, 0), calendar: utc) == at(10, 2))
        #expect(schedule.nextAnnouncement(after: at(10, 1, 30), calendar: utc) == at(10, 2))
        #expect(schedule.nextAnnouncement(after: at(10, 58), calendar: utc) == at(11, 0))
        #expect(schedule.previousAnnouncement(onOrBefore: at(10, 59, 59), calendar: utc) == at(10, 58))
    }

    /// The interesting case: 7 does not divide 60, so the run of boundaries
    /// stops at :56 and the top of the hour cuts the last interval short.
    @Test("A custom interval that does not divide 60 ends the hour on a short gap")
    func customNotDividingSixty() {
        let schedule = CadenceSchedule(mode: .custom, customMinutes: 7)
        let expected = [0, 7, 14, 21, 28, 35, 42, 49, 56]
        for minute in expected {
            #expect(schedule.isBoundary(minuteOfHour: minute))
        }
        #expect(schedule.nextAnnouncement(after: at(10, 49), calendar: utc) == at(10, 56))
        // …:56 wraps to the next hour rather than to :63.
        #expect(schedule.nextAnnouncement(after: at(10, 56), calendar: utc) == at(11, 0))
        #expect(schedule.nextAnnouncement(after: at(10, 59, 59), calendar: utc) == at(11, 0))
        #expect(schedule.previousAnnouncement(onOrBefore: at(10, 59), calendar: utc) == at(10, 56))
        #expect(schedule.previousAnnouncement(onOrBefore: at(11, 0), calendar: utc) == at(11, 0))
    }

    @Test("The short end-of-hour gap still runs a full 1 → 0")
    func shortGapUsesItsOwnSpan() {
        let schedule = CadenceSchedule(mode: .custom, customMinutes: 7)
        // The :56 → :00 gap is 4 minutes, not 7 — halfway through it is :58.
        #expect(schedule.fractionRemaining(at: at(10, 56), calendar: utc) == 1)
        #expect(schedule.fractionRemaining(at: at(10, 58), calendar: utc) == 0.5)
        let sliver = schedule.fractionRemaining(at: at(10, 59, 59), calendar: utc)!
        #expect(sliver > 0 && sliver < 0.01)
        #expect(schedule.fractionRemaining(at: at(11, 0), calendar: utc) == 1)
    }

    @Test("A zero or negative custom interval is treated as no schedule")
    func degenerateCustomInterval() {
        let schedule = CadenceSchedule(mode: .custom, customMinutes: 0)
        #expect(schedule.stepMinutes == nil)
        #expect(schedule.fractionRemaining(at: at(10, 7), calendar: utc) == nil)
    }

    // MARK: - Fraction shape

    @Test("The fraction falls linearly across an interval")
    func fractionIsLinear() {
        let schedule = CadenceSchedule(mode: .everyQuarter, customMinutes: 7)
        #expect(schedule.fractionRemaining(at: at(10, 0), calendar: utc) == 1)
        #expect(schedule.fractionRemaining(at: at(10, 5), calendar: utc)! == 2.0 / 3.0)
        #expect(schedule.fractionRemaining(at: at(10, 7, 30), calendar: utc) == 0.5)
        #expect(schedule.fractionRemaining(at: at(10, 10), calendar: utc)! == 1.0 / 3.0)
        #expect(schedule.fractionRemaining(at: at(10, 15), calendar: utc) == 1)
    }

    @Test("The fraction never leaves 0…1 across a whole hour")
    func fractionStaysBounded() {
        for minutes in [1, 2, 5, 7, 13, 15, 30, 45, 60] {
            let schedule = CadenceSchedule(mode: .custom, customMinutes: minutes)
            for second in stride(from: 0, to: 3600, by: 17) {
                let date = at(10, 0).addingTimeInterval(TimeInterval(second))
                let fraction = schedule.fractionRemaining(at: date, calendar: utc)!
                #expect(fraction > 0 && fraction <= 1)
            }
        }
    }

    // MARK: - Agreement with the spoken announcement

    @Test("Every boundary the schedule reports is a minute the clock speaks on")
    func boundariesMatchAnnouncements() {
        for minutes in [1, 3, 7, 15, 30, 60] {
            let schedule = CadenceSchedule(mode: .custom, customMinutes: minutes)
            var cursor = at(10, 0)
            let end = at(12, 0)
            while let next = schedule.nextAnnouncement(after: cursor, calendar: utc), next <= end {
                let minute = utc.component(.minute, from: next)
                #expect(utc.component(.second, from: next) == 0)
                #expect(minute % minutes == 0)
                cursor = next
            }
        }
    }
}
