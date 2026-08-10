import Foundation
import SwiftUI

/// How often the clock speaks the time.
enum AnnounceMode: String, CaseIterable, Identifiable {
    case off
    case hourly
    case everyQuarter
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .hourly: return "Every hour"
        case .everyQuarter: return "Every 15 minutes"
        case .custom: return "Custom interval"
        }
    }
}

/// Where today's calendar events sit relative to the clock face.
/// `off` is the default: the events panel is opt-in, since showing it at all
/// requires calendar permission.
enum EventsPlacement: String, CaseIterable, Identifiable {
    case off
    case column
    case below

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Hidden"
        case .column: return "Beside the clock"
        case .below: return "Below the clock"
        }
    }
}

/// The app's model layer.
///
/// Every settings/state mutation goes through this object rather than being
/// scattered across views, so a future sync backend only has to observe and
/// replay these methods. Storage is `@AppStorage` (UserDefaults) for v1.
@MainActor
final class AppSettings: ObservableObject {

    /// Valid range for the custom announcement interval, in minutes.
    static let customMinutesRange = 1...60

    @AppStorage("announceMode") private var announceModeRaw = AnnounceMode.off.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("customMinutes") private var customMinutesRaw = 30 {
        willSet { objectWillChange.send() }
    }
    @AppStorage("alwaysOnTop") private var alwaysOnTopRaw = false {
        willSet { objectWillChange.send() }
    }
    @AppStorage("eventsPlacement") private var eventsPlacementRaw = EventsPlacement.off.rawValue {
        willSet { objectWillChange.send() }
    }
    /// Where the user has parked the divider, one fraction per placement: the
    /// two layouts split different axes, so a single number would jump the panel
    /// every time the placement changed. Defaults match the fixed shares the
    /// panel shipped with before the divider existed.
    @AppStorage("eventsColumnFraction") private var eventsColumnFractionRaw = 0.34 {
        willSet { objectWillChange.send() }
    }
    @AppStorage("eventsBelowFraction") private var eventsBelowFractionRaw = 0.30 {
        willSet { objectWillChange.send() }
    }
    /// The countdown-to-next-announcement backdrop. On by default: it only ever
    /// appears when a cadence is set, so it costs nothing for the default (off)
    /// cadence, and a user who wants a bare black face can switch it off.
    @AppStorage("showCadenceFill") private var showCadenceFillRaw = true {
        willSet { objectWillChange.send() }
    }
    /// `AVSpeechSynthesisVoice.identifier` of the voice to announce with. Empty
    /// means automatic — the best installed voice, recomputed each time we
    /// speak. Stored as the identifier rather than an index so that installing
    /// or removing voices can't silently repoint the choice at another voice.
    @AppStorage("voiceIdentifier") private var voiceIdentifierRaw = "" {
        willSet { objectWillChange.send() }
    }

    // MARK: - Reads

    var announceMode: AnnounceMode {
        AnnounceMode(rawValue: announceModeRaw) ?? .off
    }

    var customMinutes: Int {
        Self.clampCustomMinutes(customMinutesRaw)
    }

    var alwaysOnTop: Bool { alwaysOnTopRaw }

    var showCadenceFill: Bool { showCadenceFillRaw }

    var voiceIdentifier: String { voiceIdentifierRaw }

    /// The announcement timetable implied by the current settings. Recomputed on
    /// read, so a cadence change retargets the countdown on the very next tick.
    var cadenceSchedule: CadenceSchedule {
        CadenceSchedule(mode: announceMode, customMinutes: customMinutes)
    }

    var eventsPlacement: EventsPlacement {
        EventsPlacement(rawValue: eventsPlacementRaw) ?? .off
    }

    /// The panel's share of the window for the placement given. `.off` has no
    /// divider, so it reports the column default rather than a special case.
    func eventsFraction(for placement: EventsPlacement) -> CGFloat {
        switch placement {
        case .below: return EventsPanelMetrics.clampFraction(CGFloat(eventsBelowFractionRaw))
        case .column, .off: return EventsPanelMetrics.clampFraction(CGFloat(eventsColumnFractionRaw))
        }
    }

    // MARK: - Mutations

    func setAnnounceMode(_ mode: AnnounceMode) {
        announceModeRaw = mode.rawValue
    }

    func setCustomMinutes(_ minutes: Int) {
        customMinutesRaw = Self.clampCustomMinutes(minutes)
    }

    func setAlwaysOnTop(_ on: Bool) {
        alwaysOnTopRaw = on
    }

    func setShowCadenceFill(_ on: Bool) {
        showCadenceFillRaw = on
    }

    /// `""` restores automatic voice selection.
    func setVoiceIdentifier(_ identifier: String) {
        voiceIdentifierRaw = identifier
    }

    func toggleAlwaysOnTop() {
        setAlwaysOnTop(!alwaysOnTopRaw)
    }

    func setEventsPlacement(_ placement: EventsPlacement) {
        eventsPlacementRaw = placement.rawValue
    }

    /// Parks the divider at `fraction` of the window for the placement given.
    /// Called continuously while the divider is dragged — `@AppStorage` writes
    /// are cheap, and writing through means an unexpected quit keeps the split.
    func setEventsFraction(_ fraction: CGFloat, for placement: EventsPlacement) {
        let clamped = Double(EventsPanelMetrics.clampFraction(fraction))
        switch placement {
        case .below: eventsBelowFractionRaw = clamped
        case .column: eventsColumnFractionRaw = clamped
        case .off: break
        }
    }

    /// Advances off → column → below → off.
    /// Requesting calendar access is the caller's job — this object stays pure state.
    func cycleEventsPlacement() {
        switch eventsPlacement {
        case .off: setEventsPlacement(.column)
        case .column: setEventsPlacement(.below)
        case .below: setEventsPlacement(.off)
        }
    }

    // MARK: - Bindings for SwiftUI controls (mutations still funnel through the setters)

    var announceModeBinding: Binding<AnnounceMode> {
        Binding(get: { self.announceMode }, set: { self.setAnnounceMode($0) })
    }

    var customMinutesBinding: Binding<Int> {
        Binding(get: { self.customMinutes }, set: { self.setCustomMinutes($0) })
    }

    var eventsPlacementBinding: Binding<EventsPlacement> {
        Binding(get: { self.eventsPlacement }, set: { self.setEventsPlacement($0) })
    }

    var voiceIdentifierBinding: Binding<String> {
        Binding(get: { self.voiceIdentifier }, set: { self.setVoiceIdentifier($0) })
    }

    // MARK: - Derived behaviour

    /// Whether the clock should speak at this minute boundary.
    /// Custom intervals are anchored to the hour (minute-of-hour modulo N) —
    /// `CadenceSchedule` owns that rule so the countdown visual and the spoken
    /// announcement can never disagree about where a boundary is.
    func shouldAnnounce(at date: Date, calendar: Calendar = .current) -> Bool {
        guard let minute = calendar.dateComponents([.minute], from: date).minute else { return false }
        return cadenceSchedule.isBoundary(minuteOfHour: minute)
    }

    /// Fraction of the wait to the next announcement still ahead, 0…1, or `nil`
    /// when no cadence is set.
    func cadenceFractionRemaining(at date: Date, calendar: Calendar = .current) -> Double? {
        cadenceSchedule.fractionRemaining(at: date, calendar: calendar)
    }

    private static func clampCustomMinutes(_ value: Int) -> Int {
        min(max(value, customMinutesRange.lowerBound), customMinutesRange.upperBound)
    }
}
