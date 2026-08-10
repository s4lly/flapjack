import Foundation
import OSLog
import UserNotifications

/// Where the app stands with the user on posting notifications.
///
/// Collapses `UNAuthorizationStatus` to the three states the UI actually
/// branches on: `provisional` counts as authorized (notifications do post, just
/// quietly), and `ephemeral` — an App Clip state that can't occur here — is
/// folded in with it rather than given a case nothing would ever read.
enum NotificationAuthorization: Sendable {
    case notDetermined
    case authorized
    case denied

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized, .provisional, .ephemeral: self = .authorized
        case .denied: self = .denied
        @unknown default: self = .denied
        }
    }
}

/// Posts the time as a macOS user notification — the second way the clock can
/// convey a cadence boundary, alongside speaking it.
///
/// The sibling of `Announcer`, and deliberately shaped like it: same lifetime,
/// same main-actor isolation, same `TimePhrase` wording, so voice and banner
/// always agree about what time it is.
///
/// Two things distinguish it from the announcer. It needs the user's
/// permission, which is requested when the setting is switched on rather than
/// at launch — an app that asks before the user has expressed any interest gets
/// a reflexive "Don't Allow", and that answer is sticky. And each new time
/// check withdraws the last, so they never stack: a cadence of 15 minutes would
/// otherwise leave 96 entries a day piled up in Notification Center, every one
/// of them stale the minute after it arrived.
///
/// Requires a real app bundle: `UNUserNotificationCenter.current()` traps when
/// the process has no bundle identifier, so this is reachable only from
/// `dist/Flapjack.app`, never from a bare `swift run`.
///
/// It is also the center's delegate, and has to be: macOS suppresses banners
/// for the app that is currently frontmost unless the delegate asks for them.
/// A clock the user is looking at is very often exactly that app, and silently
/// filing the time check straight into Notification Center is the one failure
/// mode this feature cannot afford — verified empirically, the notification did
/// arrive but never appeared.
@MainActor
final class NotificationAnnouncer: NSObject, ObservableObject {

    /// Last known authorization state, for the UI to explain itself with.
    /// Starts `notDetermined` and is corrected by `refreshAuthorization()`.
    @Published private(set) var authorization: NotificationAuthorization = .notDetermined

    private let center = UNUserNotificationCenter.current()
    private let log = Logger(subsystem: "com.s4lly.flapjack", category: "notifications")

    override init() {
        super.init()
        center.delegate = self
    }

    /// Re-reads the system's answer. Worth calling whenever Settings appears:
    /// the user can revoke (or grant) permission in System Settings while the
    /// app runs, and nothing tells us when they do.
    func refreshAuthorization() {
        Task {
            let status = await center.notificationSettings().authorizationStatus
            authorization = NotificationAuthorization(status)
        }
    }

    /// Asks for permission, but only while the answer is still open — once the
    /// user has decided, `requestAuthorization` just replays that decision, and
    /// a denial can only be reversed in System Settings.
    func requestAuthorizationIfNeeded() {
        Task {
            let status = await center.notificationSettings().authorizationStatus
            guard status == .notDetermined else {
                authorization = NotificationAuthorization(status)
                return
            }
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                authorization = granted ? .authorized : .denied
                log.info("notification authorization granted=\(granted, privacy: .public)")
            } catch {
                // A failed request is not a denial — leave the state as the
                // system reports it rather than guessing.
                log.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
                refreshAuthorization()
            }
        }
    }

    /// Posts the time as a notification, immediately.
    ///
    /// `trigger: nil` means "deliver now"; a time-interval trigger would be the
    /// wrong tool, since the boundary has already arrived by the time we're
    /// called.
    ///
    /// The withdraw-then-post shape is deliberate, and the obvious alternative
    /// does not work: posting every time check under one fixed identifier does
    /// keep Notification Center to a single entry, but the system treats the
    /// repeat as an *edit* of the notification already delivered and updates it
    /// in place — silently, with no banner. Verified on macOS 26: the entry's
    /// time changed each cadence tick and nothing ever appeared on screen. So
    /// each post gets a fresh identifier, which the system alerts for, and the
    /// previously delivered ones are withdrawn first.
    ///
    /// Withdrawing *everything* delivered is right rather than merely sweeping:
    /// the time check is the only notification Flapjack posts, so anything
    /// sitting there is a stale one — including leftovers from a previous run,
    /// which a remembered identifier would miss. The removal is awaited before
    /// the add so the new notification can't be caught by its own sweep.
    func notify(_ date: Date) {
        let content = UNMutableNotificationContent()
        content.title = TimePhrase.display(for: date)
        content.subtitle = "Flapjack time check"
        // Suppressed by the system's own alert-style setting if the user has
        // muted the app; requesting it here just means "sound if allowed".
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        Task {
            let stale = await center.deliveredNotifications().map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: stale)
            do {
                try await center.add(request)
                log.info("posted notification \"\(content.title, privacy: .public)\"")
            } catch {
                log.error("notification post failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension NotificationAnnouncer: UNUserNotificationCenterDelegate {

    /// Show the time check even while Flapjack is the frontmost app, which is
    /// the default state for a clock sitting on the desktop. Without this the
    /// system files it straight into Notification Center with nothing on
    /// screen. `.list` keeps it in the Center as well, so a boundary missed
    /// while away from the desk is still there to find.
    ///
    /// Whether the banner then lingers or fades is not ours to decide: that is
    /// the user's per-app alert style in System Settings → Notifications.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
