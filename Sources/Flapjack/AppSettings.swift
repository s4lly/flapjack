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

/// Who carries the time across the screen when the banner flies.
///
/// The banner itself — wording, path, timing, teardown — is identical either
/// way; only the character drawn at the front of it changes, which is why this
/// is a separate setting from the on/off toggle rather than a third state of it.
enum BannerStyle: String, CaseIterable, Identifiable {
    case airplane
    case cat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .airplane: return "Airplane"
        case .cat: return "Waving cat"
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
    /// The three ways a cadence boundary can be conveyed, independently
    /// switchable. Voice defaults on (it is what the cadence has always meant)
    /// and notification defaults off, since turning it on is what triggers the
    /// system permission prompt — an app that asks unbidden gets a reflexive
    /// "Don't Allow". All off is allowed: the cadence fill still counts down,
    /// and nothing fires at the boundary.
    @AppStorage("speakOnCadence") private var speakOnCadenceRaw = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("notifyOnCadence") private var notifyOnCadenceRaw = false {
        willSet { objectWillChange.send() }
    }
    /// The flying banner. Defaults off for the plainest of reasons: it draws
    /// over every app on screen, and that is not something to start doing
    /// unasked. It needs no permission, so it is off by taste, not by prompt.
    ///
    /// The stored key is still `planeOnCadence`: the property was renamed when
    /// the banner grew a second character, but renaming the key too would have
    /// silently switched the feature off for everyone already using it.
    @AppStorage("planeOnCadence") private var bannerOnCadenceRaw = false {
        willSet { objectWillChange.send() }
    }
    /// Which character flies it. Airplane is the default because it is what the
    /// banner has always been.
    @AppStorage("bannerStyle") private var bannerStyleRaw = BannerStyle.airplane.rawValue {
        willSet { objectWillChange.send() }
    }
    /// Turn other apps' music down for the length of a spoken time check.
    /// Defaults off for the same reason notifications do: the first duck sends
    /// an Apple Event to a music player, and *that* is what raises the system's
    /// Automation permission prompt. An app that provokes it unasked earns a
    /// "Don't Allow", and only System Settings can reverse that.
    @AppStorage("duckOtherAudio") private var duckOtherAudioRaw = false {
        willSet { objectWillChange.send() }
    }
    /// `AVSpeechSynthesisVoice.identifier` of the voice to announce with. Empty
    /// means automatic — the best installed voice, recomputed each time we
    /// speak. Stored as the identifier rather than an index so that installing
    /// or removing voices can't silently repoint the choice at another voice.
    @AppStorage("voiceIdentifier") private var voiceIdentifierRaw = "" {
        willSet { objectWillChange.send() }
    }
    /// The colourway, or the rule that picks one. Defaults to `auto`, which
    /// follows the system's light/dark setting — a desk clock that stays black
    /// while everything around it goes light is the one thing this setting
    /// exists to stop.
    @AppStorage("appearance") private var appearanceRaw = Appearance.auto.rawValue {
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

    var speakOnCadence: Bool { speakOnCadenceRaw }

    var notifyOnCadence: Bool { notifyOnCadenceRaw }

    var bannerOnCadence: Bool { bannerOnCadenceRaw }

    var bannerStyle: BannerStyle {
        BannerStyle(rawValue: bannerStyleRaw) ?? .airplane
    }

    var duckOtherAudio: Bool { duckOtherAudioRaw }

    var appearance: Appearance {
        Appearance(rawValue: appearanceRaw) ?? .auto
    }

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

    func setSpeakOnCadence(_ on: Bool) {
        speakOnCadenceRaw = on
    }

    /// Requesting notification permission is the caller's job — this object
    /// stays pure state, exactly as it does for the calendar panel.
    func setNotifyOnCadence(_ on: Bool) {
        notifyOnCadenceRaw = on
    }

    func setBannerOnCadence(_ on: Bool) {
        bannerOnCadenceRaw = on
    }

    func setBannerStyle(_ style: BannerStyle) {
        bannerStyleRaw = style.rawValue
    }

    /// Ducking asks the system for nothing here — the permission prompt comes
    /// from the first Apple Event, when the clock next speaks. This object stays
    /// pure state, as it does for notifications and the calendar.
    func setDuckOtherAudio(_ on: Bool) {
        duckOtherAudioRaw = on
    }

    /// `""` restores automatic voice selection.
    func setVoiceIdentifier(_ identifier: String) {
        voiceIdentifierRaw = identifier
    }

    func setAppearance(_ appearance: Appearance) {
        appearanceRaw = appearance.rawValue
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

    var bannerStyleBinding: Binding<BannerStyle> {
        Binding(get: { self.bannerStyle }, set: { self.setBannerStyle($0) })
    }

    var voiceIdentifierBinding: Binding<String> {
        Binding(get: { self.voiceIdentifier }, set: { self.setVoiceIdentifier($0) })
    }

    var appearanceBinding: Binding<Appearance> {
        Binding(get: { self.appearance }, set: { self.setAppearance($0) })
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
