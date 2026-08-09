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

    // MARK: - Reads

    var announceMode: AnnounceMode {
        AnnounceMode(rawValue: announceModeRaw) ?? .off
    }

    var customMinutes: Int {
        Self.clampCustomMinutes(customMinutesRaw)
    }

    var alwaysOnTop: Bool { alwaysOnTopRaw }

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

    func toggleAlwaysOnTop() {
        setAlwaysOnTop(!alwaysOnTopRaw)
    }

    // MARK: - Bindings for SwiftUI controls (mutations still funnel through the setters)

    var announceModeBinding: Binding<AnnounceMode> {
        Binding(get: { self.announceMode }, set: { self.setAnnounceMode($0) })
    }

    var customMinutesBinding: Binding<Int> {
        Binding(get: { self.customMinutes }, set: { self.setCustomMinutes($0) })
    }

    // MARK: - Derived behaviour

    /// Whether the clock should speak at this minute boundary.
    /// Custom intervals are anchored to the hour (minute-of-hour modulo N).
    func shouldAnnounce(at date: Date, calendar: Calendar = .current) -> Bool {
        guard let minute = calendar.dateComponents([.minute], from: date).minute else { return false }
        switch announceMode {
        case .off: return false
        case .hourly: return minute == 0
        case .everyQuarter: return minute % 15 == 0
        case .custom:
            let n = customMinutes
            return n > 0 && minute % n == 0
        }
    }

    private static func clampCustomMinutes(_ value: Int) -> Int {
        min(max(value, customMinutesRange.lowerBound), customMinutesRange.upperBound)
    }
}
