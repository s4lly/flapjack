import SwiftUI

/// Sizes for the events panel in both of its placements.
///
/// The panel takes its space out of the window *before* the face is measured,
/// so these numbers feed `FaceMetrics.unit(fitting:)` as well as the panel's own
/// frame — keeping the two in one place is what stops the clock from either
/// overlapping the panel or leaving a gap beside it.
enum EventsPanelMetrics {

    /// Share of the window width the column would like, and the point bounds it
    /// is clamped to so it stays readable on a huge display and doesn't swallow
    /// the clock on a tiny one.
    static let columnFraction: CGFloat = 0.30
    static let columnMinWidth: CGFloat = 140
    static let columnMaxWidth: CGFloat = 280
    /// Hard ceiling relative to the window: the face always keeps the majority.
    private static let columnMaxFraction: CGFloat = 0.42

    static let stripFraction: CGFloat = 0.22
    static let stripMinHeight: CGFloat = 42
    static let stripMaxHeight: CGFloat = 84
    private static let stripMaxFraction: CGFloat = 0.34

    static func columnWidth(inWindowWidth width: CGFloat) -> CGFloat {
        let wanted = min(max(width * columnFraction, columnMinWidth), columnMaxWidth)
        return max(0, min(wanted, width * columnMaxFraction))
    }

    static func stripHeight(inWindowHeight height: CGFloat) -> CGFloat {
        let wanted = min(max(height * stripFraction, stripMinHeight), stripMaxHeight)
        return max(0, min(wanted, height * stripMaxFraction))
    }
}

/// Formatting shared by both layouts. Kept as one cached formatter — building a
/// `DateFormatter` per row per redraw is surprisingly expensive.
enum EventTimeFormat {

    static func label(for event: EventItem) -> String {
        event.isAllDay ? "all-day" : formatter.string(from: event.start)
    }

    /// Locale-aware hour:minute with the AM/PM designator dropped: the panel
    /// only ever shows the rest of *today*, so the meridiem is noise, and the
    /// narrow column needs the width more than the disambiguation.
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        let template = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current) ?? "h:mm"
        let stripped = template
            .replacingOccurrences(of: "a", with: "")
            .trimmingCharacters(in: .whitespaces)
        f.dateFormat = stripped.isEmpty ? "H:mm" : stripped
        return f
    }()
}

/// Dim-on-black palette matching the clock face's greys.
private enum EventsPalette {
    static let time = Color(white: 0.52)
    static let title = Color(white: 0.78)
    static let hint = Color(white: 0.42)
    static let chipFill = Color.white.opacity(0.05)
}

/// One event: a per-calendar colour dot, the start time, and the title.
/// Everything is a single truncating line — the panel is a glance, not a reader.
struct EventRow: View {
    let event: EventItem
    /// Base text size in points; every other size is a multiple of it.
    let unit: CGFloat

    var body: some View {
        HStack(spacing: unit * 0.4) {
            Circle()
                .fill(event.calendarColor)
                .frame(width: unit * 0.42, height: unit * 0.42)

            Text(EventTimeFormat.label(for: event))
                .font(.system(size: unit, weight: .medium, design: .monospaced))
                .foregroundStyle(EventsPalette.time)
                .lineLimit(1)
                .fixedSize()

            Text(event.title)
                .font(.system(size: unit, weight: .regular))
                .foregroundStyle(EventsPalette.title)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(EventTimeFormat.label(for: event)), \(event.title)")
    }
}

/// The same row compressed into a pill for the horizontal strip.
struct EventChip: View {
    let event: EventItem
    let unit: CGFloat

    var body: some View {
        HStack(spacing: unit * 0.34) {
            Circle()
                .fill(event.calendarColor)
                .frame(width: unit * 0.42, height: unit * 0.42)

            Text(EventTimeFormat.label(for: event))
                .font(.system(size: unit, weight: .medium, design: .monospaced))
                .foregroundStyle(EventsPalette.time)

            Text(event.title)
                .font(.system(size: unit, weight: .regular))
                .foregroundStyle(EventsPalette.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: unit * 14, alignment: .leading)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, unit * 0.6)
        .padding(.vertical, unit * 0.34)
        .background(
            RoundedRectangle(cornerRadius: unit * 0.5, style: .continuous)
                .fill(EventsPalette.chipFill)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(EventTimeFormat.label(for: event)), \(event.title)")
    }
}

/// What the panel says when there is no list to show. Shared by both layouts so
/// the wording can't drift between them.
enum EventsPanelState {
    case events([EventItem])
    case empty
    case denied
    case connecting

    init(authorization: EventsAuthorization, events: [EventItem]) {
        switch authorization {
        case .notDetermined: self = .connecting
        case .denied: self = .denied
        case .granted: self = events.isEmpty ? .empty : .events(events)
        }
    }

    var message: String? {
        switch self {
        case .events: return nil
        case .empty: return "No more events today"
        case .denied: return "Calendar access needed — grant in System Settings → Privacy & Security → Calendars"
        case .connecting: return "Connecting…"
        }
    }

    /// The denied hint is a sentence, not a label, so it gets a smaller size and
    /// is allowed to wrap.
    var messageIsLong: Bool {
        if case .denied = self { return true }
        return false
    }
}

private struct EventsMessage: View {
    let state: EventsPanelState
    let unit: CGFloat
    let alignment: TextAlignment

    var body: some View {
        if let message = state.message {
            Text(message)
                .font(.system(size: state.messageIsLong ? unit * 0.82 : unit))
                .foregroundStyle(EventsPalette.hint)
                .multilineTextAlignment(alignment)
                .lineLimit(state.messageIsLong ? 4 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Vertical list on the trailing edge of the window.
struct EventsColumn: View {
    let state: EventsPanelState
    /// Width already reserved by the layout (see `EventsPanelMetrics`).
    let width: CGFloat

    private var unit: CGFloat { min(max(width * 0.078, 10), 15) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch state {
            case .events(let events):
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: unit * 0.55) {
                        ForEach(events) { EventRow(event: $0, unit: unit) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            default:
                EventsMessage(state: state, unit: unit, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, unit)
        .padding(.trailing, unit)
        .frame(width: width, alignment: .topLeading)
    }
}

/// Horizontal strip of chips beneath the face.
struct EventsStrip: View {
    let state: EventsPanelState
    /// Height already reserved by the layout (see `EventsPanelMetrics`).
    let height: CGFloat

    private var unit: CGFloat { min(max(height * 0.24, 10), 14) }

    var body: some View {
        Group {
            switch state {
            case .events(let events):
                ScrollView(.horizontal) {
                    HStack(spacing: unit * 0.5) {
                        ForEach(events) { EventChip(event: $0, unit: unit) }
                    }
                    .padding(.horizontal, unit)
                }
                .scrollIndicators(.hidden)
            default:
                EventsMessage(state: state, unit: unit, alignment: .center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, unit)
            }
        }
        .frame(height: height, alignment: .center)
    }
}
