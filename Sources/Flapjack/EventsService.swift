import EventKit
import Foundation
import OSLog
import SwiftUI

/// Calendar access as the app cares about it, decoupled from `EKAuthorizationStatus`.
enum EventsAuthorization {
    case notDetermined
    /// Full read access — the only state in which events can be listed.
    case granted
    /// Denied, restricted, or write-only: nothing readable, so the UI shows a hint.
    case denied
}

/// One calendar event, flattened for display.
///
/// Deliberately free of EventKit types: views bind to this shape only, so a
/// future backend-brokered event source can populate the same struct without
/// touching the UI layer.
struct EventItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarColor: Color
    let calendarTitle: String
}

/// Reads today's remaining events from the macOS calendar store.
///
/// The `EKEventStore` is held for the app's lifetime (recreating it drops the
/// change notifications) and never leaves the main actor — it isn't `Sendable`.
@MainActor
final class EventsService: ObservableObject {

    @Published private(set) var authorization: EventsAuthorization
    @Published private(set) var todaysEvents: [EventItem] = []

    private let store = EKEventStore()
    private let log = Logger(subsystem: "com.s4lly.flapjack", category: "events")
    private var changeObserver: NSObjectProtocol?

    init() {
        // Reading the status never prompts; the system dialog only comes from
        // `requestAccessIfNeeded()`.
        authorization = Self.currentAuthorization()

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.log.debug("EKEventStoreChanged — refreshing")
                self.refresh(now: Date())
            }
        }
    }

    // MARK: - Authorization

    /// Prompts for calendar access, but only the first time. Already-decided
    /// states just re-sync the published value (the user may have flipped the
    /// switch in System Settings since launch).
    func requestAccessIfNeeded() {
        let status = Self.currentAuthorization()
        guard status == .notDetermined else {
            authorization = status
            if status == .granted { refresh(now: Date()) }
            return
        }

        store.requestFullAccessToEvents { [weak self] granted, error in
            // The callback arrives off the main thread.
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.log.error("calendar access request failed: \(error.localizedDescription, privacy: .public)")
                }
                self.authorization = granted ? .granted : .denied
                if granted { self.refresh(now: Date()) }
            }
        }
    }

    private static func currentAuthorization() -> EventsAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        // Write-only can't read events, so it's indistinguishable from denied here.
        case .denied, .restricted, .writeOnly: return .denied
        @unknown default: return .denied
        }
    }

    // MARK: - Fetching

    /// Reloads the whole of `now`'s day, midnight to midnight.
    ///
    /// The panel draws a day timeline, so events that have already finished are
    /// still part of the picture — the user scrolls back to them. (Fetching
    /// from `now` would have kept in-progress events, since the predicate
    /// matches on overlap, but it dropped the earlier part of the day.)
    /// A no-op unless access has been granted.
    func refresh(now: Date, calendar: Calendar = .current) {
        guard authorization == .granted else {
            if !todaysEvents.isEmpty { todaysEvents = [] }
            return
        }

        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let items = store.events(matching: predicate)
            .sorted { lhs, rhs in
                // All-day events head the list; the rest run in start order.
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
            .compactMap(Self.item(from:))

        // Assigning unconditionally would republish (and redraw) every minute.
        guard items != todaysEvents else { return }
        log.debug("today's events: \(items.count, privacy: .public)")
        todaysEvents = items
    }

    private static func item(from event: EKEvent) -> EventItem? {
        guard let start = event.startDate else { return nil }
        return EventItem(
            id: event.eventIdentifier ?? "\(ObjectIdentifier(event))",
            title: event.title ?? "(No title)",
            start: start,
            end: event.endDate ?? start,
            isAllDay: event.isAllDay,
            calendarColor: event.calendar.map { Color(nsColor: $0.color) } ?? .accentColor,
            calendarTitle: event.calendar?.title ?? ""
        )
    }

    isolated deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }
}
