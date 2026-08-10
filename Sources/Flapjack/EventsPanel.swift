import SwiftUI

/// Sizes for the events panel in both of its placements.
///
/// The panel takes its space out of the window *before* the face is measured,
/// so these numbers feed `FaceMetrics.unit(fitting:)` as well as the panel's own
/// frame — keeping the two in one place is what stops the clock from either
/// overlapping the panel or leaving a gap beside it.
///
/// The share itself is the user's: it lives in `AppSettings` and the divider
/// moves it. What lives here is the translation from that fraction into points,
/// plus the floors that keep both halves usable when the window is small enough
/// that the fraction alone would starve one of them.
enum EventsPanelMetrics {

    /// Bounds on the panel's share of the window. The ceiling keeps the face
    /// the larger half of the split; the floor stops a drag from collapsing the
    /// panel into an unreadable sliver.
    static let fractionRange: ClosedRange<CGFloat> = 0.15...0.5

    static func clampFraction(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return fractionRange.lowerBound }
        return min(max(value, fractionRange.lowerBound), fractionRange.upperBound)
    }

    /// The column carries a time axis as well as the event blocks, so its floor
    /// is wider than a plain list would need.
    static let columnMinWidth: CGFloat = 120
    /// The strip has to stack an hour ruler above at least one lane of blocks.
    static let stripMinHeight: CGFloat = 64

    /// What the face keeps no matter where the divider is dragged. Below these
    /// the digits stop being a clock, so the divider simply refuses to go on.
    static let faceMinWidth: CGFloat = 150
    static let faceMinHeight: CGFloat = 50

    /// Layout width of the divider gutter — the visible hairline plus the
    /// slack around it that makes the handle grabbable.
    static let dividerThickness: CGFloat = 9

    static func columnWidth(inWindowWidth width: CGFloat, fraction: CGFloat) -> CGFloat {
        clamp(width * clampFraction(fraction),
              inWindow: width, panelMin: columnMinWidth, faceMin: faceMinWidth)
    }

    static func stripHeight(inWindowHeight height: CGFloat, fraction: CGFloat) -> CGFloat {
        clamp(height * clampFraction(fraction),
              inWindow: height, panelMin: stripMinHeight, faceMin: faceMinHeight)
    }

    /// The inverse, for the divider: the fraction to store so the panel lands as
    /// close to `extent` points as the clamps allow. Running the drag through
    /// the same clamps is what stops the stored value from drifting past the
    /// edge the user can actually see the divider stop at.
    static func columnFraction(forWidth extent: CGFloat, inWindowWidth width: CGFloat) -> CGFloat {
        fraction(for: extent, inWindow: width, panelMin: columnMinWidth, faceMin: faceMinWidth)
    }

    static func stripFraction(forHeight extent: CGFloat, inWindowHeight height: CGFloat) -> CGFloat {
        fraction(for: extent, inWindow: height, panelMin: stripMinHeight, faceMin: faceMinHeight)
    }

    private static func clamp(_ wanted: CGFloat, inWindow total: CGFloat,
                              panelMin: CGFloat, faceMin: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        // The floor yields first when the window is too small to honour both
        // floors at once: a clipped panel beats a face with no room to draw.
        let lower = max(0, min(panelMin, total - dividerThickness))
        let upper = max(lower, min(total * fractionRange.upperBound,
                                   total - faceMin - dividerThickness))
        return min(max(wanted, lower), upper)
    }

    private static func fraction(for extent: CGFloat, inWindow total: CGFloat,
                                 panelMin: CGFloat, faceMin: CGFloat) -> CGFloat {
        guard total > 0 else { return fractionRange.lowerBound }
        let points = clamp(extent, inWindow: total, panelMin: panelMin, faceMin: faceMin)
        return clampFraction(points / total)
    }
}

/// Formatting shared by both layouts. Kept as cached formatters — building a
/// `DateFormatter` per block per redraw is surprisingly expensive.
enum EventTimeFormat {

    static func label(for event: EventItem) -> String {
        event.isAllDay ? "all-day" : clock.string(from: event.start)
    }

    /// "9:00 – 9:45" for the blocks that are tall (or wide) enough to carry it.
    static func range(for event: EventItem) -> String {
        guard !event.isAllDay else { return "all-day" }
        return "\(clock.string(from: event.start))–\(clock.string(from: event.end))"
    }

    /// Ruler label for an hour mark: "9 AM", or "09" where the locale is 24-hour.
    static func hourLabel(_ date: Date) -> String {
        hour.string(from: date)
    }

    /// Locale-aware hour:minute with the AM/PM designator dropped: the panel
    /// only ever shows a single day, so the meridiem is noise on every block —
    /// the hour ruler beside them carries it instead.
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        let template = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current) ?? "h:mm"
        let stripped = template
            .replacingOccurrences(of: "a", with: "")
            .trimmingCharacters(in: .whitespaces)
        f.dateFormat = stripped.isEmpty ? "H:mm" : stripped
        return f
    }()

    private static let hour: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "h a"
        return f
    }()
}

/// Dim-on-black palette matching the clock face's greys.
private enum EventsPalette {
    static let axis = Color(white: 0.44)
    static let title = Color(white: 0.90)
    static let hint = Color(white: 0.42)
    static let gridline = Color.white.opacity(0.08)
    static let hourGridline = Color.white.opacity(0.13)
    /// The "now" marker. Deliberately the one saturated thing in the panel.
    static let now = Color(red: 1.0, green: 0.27, blue: 0.23)
}

// MARK: - Timeline geometry

/// Maps a wall-clock instant onto a position along the day axis.
///
/// The scale is fixed (points per hour) rather than fit-to-panel: the panel is
/// a window onto the day that the user scrolls, so an hour is always the same
/// distance and a block's size reads as its duration.
struct DayTimeline {
    let dayStart: Date
    let pointsPerHour: CGFloat

    /// Shortest span a block is allowed to occupy, in minutes. Also the
    /// granularity the overlap solver works at, so two blocks can never collide
    /// visually just because one of them was rounded up to stay legible.
    static let minimumMinutes: Double = 20

    init(containing date: Date, pointsPerHour: CGFloat, calendar: Calendar = .current) {
        self.dayStart = calendar.startOfDay(for: date)
        self.pointsPerHour = pointsPerHour
    }

    /// Full length of the day, 12 AM to 12 AM.
    var length: CGFloat { 24 * pointsPerHour }

    func offset(for date: Date) -> CGFloat {
        let hours = date.timeIntervalSince(dayStart) / 3600
        return min(max(CGFloat(hours) * pointsPerHour, 0), length)
    }

    func hourMark(_ hour: Int) -> Date {
        dayStart.addingTimeInterval(Double(hour) * 3600)
    }

    /// Start offset and length for an event, with the minimum span applied.
    func span(of event: EventItem) -> (start: CGFloat, length: CGFloat) {
        let start = offset(for: event.start)
        let end = offset(for: max(event.end, event.start.addingTimeInterval(Self.minimumMinutes * 60)))
        return (start, max(end - start, pointsPerHour * CGFloat(Self.minimumMinutes / 60)))
    }
}

/// An event with its column assignment inside the group of events it overlaps.
struct PlacedEvent: Identifiable {
    let event: EventItem
    let lane: Int
    /// How many lanes the overlapping cluster needed — the block's cross-axis
    /// size is the lane area divided by this.
    let laneCount: Int

    var id: String { event.id }
}

enum TimelineLayout {

    /// Greedy column assignment: events are swept in start order, each one
    /// dropped into the first lane whose previous event has finished. A run of
    /// mutually overlapping events forms a cluster that shares a lane count, so
    /// two unrelated pairs elsewhere in the day don't shrink each other.
    static func place(_ events: [EventItem]) -> [PlacedEvent] {
        let timed = events
            .filter { !$0.isAllDay }
            .sorted { $0.start < $1.start }

        var placed: [PlacedEvent] = []
        var cluster: [(event: EventItem, lane: Int)] = []
        var laneEnds: [Date] = []
        var clusterEnd: Date?

        func flush() {
            let count = max(laneEnds.count, 1)
            placed.append(contentsOf: cluster.map {
                PlacedEvent(event: $0.event, lane: $0.lane, laneCount: count)
            })
            cluster.removeAll()
            laneEnds.removeAll()
            clusterEnd = nil
        }

        for event in timed {
            // The visual end, so a 5-minute event still reserves its lane.
            let end = max(event.end, event.start.addingTimeInterval(DayTimeline.minimumMinutes * 60))

            if let current = clusterEnd, event.start >= current { flush() }

            let lane = laneEnds.firstIndex { $0 <= event.start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(end) } else { laneEnds[lane] = end }

            cluster.append((event, lane))
            clusterEnd = max(clusterEnd ?? end, end)
        }
        flush()

        return placed
    }
}

/// Which way the day runs. Both layouts share one implementation; this maps a
/// (position-along-the-day, position-across-the-lanes) pair onto real geometry.
private enum TimelineOrientation {
    /// Day runs top to bottom, lanes left to right (the column).
    case vertical
    /// Day runs left to right, lanes top to bottom (the strip).
    case horizontal

    var scrollAxis: Axis.Set { self == .vertical ? .vertical : .horizontal }

    func size(along: CGFloat, across: CGFloat) -> CGSize {
        self == .vertical ? CGSize(width: across, height: along)
                          : CGSize(width: along, height: across)
    }

    func point(along: CGFloat, across: CGFloat) -> CGPoint {
        self == .vertical ? CGPoint(x: across, y: along)
                          : CGPoint(x: along, y: across)
    }

    /// Where the now-line should land in the visible window on auto-scroll:
    /// a third of the way in, so the immediate future stays on screen.
    var nowAnchor: UnitPoint {
        self == .vertical ? UnitPoint(x: 0, y: 0.32) : UnitPoint(x: 0.28, y: 0)
    }
}

// MARK: - Pieces

/// One event drawn as a block: translucent wash in the calendar's colour with a
/// solid leading edge, which is what keeps it legible against pure black.
private struct EventBlock: View {
    let event: EventItem
    let unit: CGFloat
    let orientation: TimelineOrientation
    let size: CGSize
    let isPast: Bool

    private var showsTime: Bool {
        orientation == .vertical ? size.height >= unit * 2.6
                                 : size.height >= unit * 2.4 && size.width >= unit * 5
    }

    private var edge: CGFloat { max(2, unit * 0.2) }
    private var radius: CGFloat { min(unit * 0.42, 6) }

    var body: some View {
        ZStack(alignment: orientation == .vertical ? .leading : .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(event.calendarColor.opacity(0.24))

            // Leading rail: vertical layouts get it down the left, horizontal
            // ones along the top, so it never eats the (scarce) width.
            Rectangle()
                .fill(event.calendarColor)
                .frame(width: orientation == .vertical ? edge : nil,
                       height: orientation == .vertical ? nil : edge)

            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: unit * 0.86, weight: .medium))
                    .foregroundStyle(EventsPalette.title)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if showsTime {
                    Text(EventTimeFormat.range(for: event))
                        .font(.system(size: unit * 0.72, design: .monospaced))
                        .foregroundStyle(EventsPalette.axis)
                        .lineLimit(1)
                }
            }
            .padding(.leading, orientation == .vertical ? edge + unit * 0.3 : unit * 0.3)
            .padding(.trailing, unit * 0.2)
            .padding(.top, orientation == .vertical ? unit * 0.1 : edge + unit * 0.1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .frame(width: size.width, height: size.height)
        // Finished events stay on the timeline (the day is the point) but step
        // back so the eye lands on what is still ahead.
        .opacity(isPast ? 0.45 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(EventTimeFormat.range(for: event)), \(event.title)")
    }
}

/// All-day events, pinned outside the scrolling timeline: they have no place on
/// an hour axis, and they're the one thing worth seeing without scrolling.
private struct AllDayStrip: View {
    let events: [EventItem]
    let unit: CGFloat
    let orientation: TimelineOrientation
    /// Cross-axis room the strip may take (width when horizontal).
    let extent: CGFloat

    /// Two is all that fits before the timeline itself gets squeezed.
    private var shown: ArraySlice<EventItem> { events.prefix(2) }

    var body: some View {
        let overflow = events.count - shown.count

        VStack(alignment: .leading, spacing: unit * 0.2) {
            ForEach(Array(shown)) { event in
                HStack(spacing: unit * 0.3) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(event.calendarColor)
                        .frame(width: max(2, unit * 0.18))
                    Text(event.title)
                        .font(.system(size: unit * 0.8, weight: .medium))
                        .foregroundStyle(EventsPalette.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, unit * 0.24)
                // Fixed row height: the colour rail is a shape, and shapes grow
                // to whatever they're offered.
                .frame(maxWidth: .infinity, minHeight: unit * 1.4, maxHeight: unit * 1.4,
                       alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: unit * 0.3, style: .continuous)
                        .fill(event.calendarColor.opacity(0.18))
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("All day, \(event.title)")
            }

            if overflow > 0 {
                Text("+\(overflow) more")
                    .font(.system(size: unit * 0.7))
                    .foregroundStyle(EventsPalette.hint)
            }
        }
        .frame(width: orientation == .horizontal ? extent : nil, alignment: .leading)
    }
}

// MARK: - The timeline

/// A scrolling day view: hour ruler, gridlines, event blocks positioned by
/// their span, and the now-line. One implementation drives both placements —
/// the orientation only changes how (along, across) becomes (x, y).
private struct DayTimelineView: View {
    let orientation: TimelineOrientation
    let events: [EventItem]
    let now: Date
    let unit: CGFloat
    let pointsPerHour: CGFloat
    /// Cross-axis room for the hour labels (the gutter / ruler strip).
    let rulerExtent: CGFloat
    /// Cross-axis room left for the event lanes.
    let laneExtent: CGFloat
    /// Shown centred over the axis when the day holds nothing at all.
    let emptyNote: String?

    private static let nowAnchorID = "flapjack.timeline.now"

    private var timeline: DayTimeline {
        DayTimeline(containing: now, pointsPerHour: pointsPerHour)
    }

    private var placements: [PlacedEvent] { TimelineLayout.place(events) }

    private var contentSize: CGSize {
        orientation.size(along: timeline.length, across: rulerExtent + laneExtent)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(orientation.scrollAxis) {
                ZStack(alignment: .topLeading) {
                    hourMarks
                    blocks
                    nowIndicator
                    nowScrollAnchor
                }
                .frame(width: contentSize.width, height: contentSize.height)
            }
            // .never, not .hidden: .hidden still shows a bar when the system
            // "Show scroll bars: Always" preference requests one.
            .scrollIndicators(.never)
            .onAppear { revealNow(proxy) }
            // Placement flips and window resizes both land here; the panel is a
            // glance surface, so it re-centres on "now" rather than preserving
            // a scroll offset the user probably didn't choose.
            .onChange(of: laneExtent) { _, _ in revealNow(proxy) }
            .onChange(of: pointsPerHour) { _, _ in revealNow(proxy) }
            .overlay(alignment: .center) {
                if let emptyNote {
                    Text(emptyNote)
                        .font(.system(size: unit * 0.86))
                        .foregroundStyle(EventsPalette.hint)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// A real 1pt view sitting on the now-line, for `ScrollViewProxy` to aim at.
    ///
    /// It is padded into place rather than `.position`ed: `.position` keeps the
    /// modified view's *layout* frame at full size, and the scroll reader
    /// anchors on the layout frame — which would make every anchor mean "the
    /// whole day".
    @ViewBuilder
    private var nowScrollAnchor: some View {
        let marker = Color.clear.frame(width: 1, height: 1).id(Self.nowAnchorID)
        let lead = max(timeline.offset(for: now) - 0.5, 0)

        switch orientation {
        case .vertical:
            VStack(spacing: 0) {
                Color.clear.frame(width: 1, height: lead)
                marker
                Spacer(minLength: 0)
            }
        case .horizontal:
            HStack(spacing: 0) {
                Color.clear.frame(width: lead, height: 1)
                marker
                Spacer(minLength: 0)
            }
        }
    }

    private func revealNow(_ proxy: ScrollViewProxy) {
        proxy.scrollTo(Self.nowAnchorID, anchor: orientation.nowAnchor)
        // The first pass runs before the content has its final size; a hop
        // through the run loop makes the initial reveal stick.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            proxy.scrollTo(Self.nowAnchorID, anchor: orientation.nowAnchor)
        }
    }

    // MARK: Ruler

    private var hourMarks: some View {
        ForEach(0...24, id: \.self) { hour in
            let along = CGFloat(hour) * pointsPerHour

            Rectangle()
                .fill(hour % 6 == 0 ? EventsPalette.hourGridline : EventsPalette.gridline)
                .frame(width: orientation.size(along: 1, across: laneExtent).width,
                       height: orientation.size(along: 1, across: laneExtent).height)
                .position(orientation.point(along: along, across: rulerExtent + laneExtent / 2))

            if hour < 24 {
                Text(EventTimeFormat.hourLabel(timeline.hourMark(hour)))
                    .font(.system(size: unit * 0.68, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(EventsPalette.axis)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: orientation == .vertical ? rulerExtent - unit * 0.4 : nil,
                           alignment: orientation == .vertical ? .trailing : .leading)
                    // Vertical: sits just under its line, right-aligned in the
                    // gutter. Horizontal: just right of its line, on the ruler.
                    .position(orientation == .vertical
                              ? CGPoint(x: (rulerExtent - unit * 0.4) / 2, y: along + unit * 0.6)
                              : CGPoint(x: along + unit * 1.5, y: rulerExtent / 2))
            }
        }
    }

    // MARK: Blocks

    private var blocks: some View {
        let gap: CGFloat = 2

        return ForEach(placements) { placed in
            let span = timeline.span(of: placed.event)
            let laneSize = (laneExtent - gap * CGFloat(placed.laneCount - 1)) / CGFloat(placed.laneCount)
            let across = rulerExtent + CGFloat(placed.lane) * (laneSize + gap)
            let size = orientation.size(along: max(span.length - 1, 4), across: max(laneSize, 6))

            EventBlock(
                event: placed.event,
                unit: unit,
                orientation: orientation,
                size: size,
                isPast: placed.event.end <= now
            )
            .position(orientation.point(along: span.start + component(.along, of: size) / 2,
                                        across: across + component(.across, of: size) / 2))
        }
    }

    /// Pulls the along/across component back out of a concrete size.
    private enum SizeAxis { case along, across }

    private func component(_ axis: SizeAxis, of size: CGSize) -> CGFloat {
        switch (orientation, axis) {
        case (.vertical, .along), (.horizontal, .across): return size.height
        case (.vertical, .across), (.horizontal, .along): return size.width
        }
    }

    // MARK: Now

    private var nowIndicator: some View {
        let along = timeline.offset(for: now)
        let thickness = max(2, unit * 0.18)
        let bead = max(7, unit * 0.62)
        let line = orientation.size(along: thickness, across: laneExtent)

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(EventsPalette.now)
                .frame(width: line.width, height: line.height)
                .position(orientation.point(along: along, across: rulerExtent + laneExtent / 2))

            Circle()
                .fill(EventsPalette.now)
                .frame(width: bead, height: bead)
                .position(orientation.point(along: along, across: rulerExtent))
        }
        .shadow(color: EventsPalette.now.opacity(0.55), radius: 3)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now")
    }
}

// MARK: - Panel states

/// What the panel says when there is no timeline to show. Shared by both
/// layouts so the wording can't drift between them.
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

    /// Timed + all-day events to draw, and the note (if any) to float over an
    /// otherwise bare axis. `nil` means this state has no timeline at all.
    var timelineContents: (events: [EventItem], note: String?)? {
        switch self {
        case .events(let events): return (events, nil)
        // An empty day still gets its axis and now-line — the panel is a day
        // view, and "nothing scheduled" is information best shown in place.
        case .empty: return ([], message)
        case .denied, .connecting: return nil
        }
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

// MARK: - Placements

/// Vertical day timeline on the trailing edge of the window.
struct EventsColumn: View {
    let state: EventsPanelState
    /// Width already reserved by the layout (see `EventsPanelMetrics`).
    let width: CGFloat
    /// Current minute, from the same tick that drives the face.
    let now: Date

    private var unit: CGFloat { min(max(width * 0.072, 10), 15) }
    /// Wide enough for the longest hour label ("12 AM") plus air.
    private var gutter: CGFloat { unit * 3.1 }
    private var pointsPerHour: CGFloat { unit * 4.2 }

    var body: some View {
        VStack(alignment: .leading, spacing: unit * 0.35) {
            if let contents = state.timelineContents {
                let allDay = contents.events.filter(\.isAllDay)

                if !allDay.isEmpty {
                    AllDayStrip(events: allDay, unit: unit, orientation: .vertical, extent: width)
                        .padding(.leading, gutter - unit * 0.4)
                        .padding(.trailing, unit * 0.9)
                    Divider().overlay(EventsPalette.gridline)
                }

                DayTimelineView(
                    orientation: .vertical,
                    events: contents.events,
                    now: now,
                    unit: unit,
                    pointsPerHour: pointsPerHour,
                    rulerExtent: gutter,
                    laneExtent: max(width - gutter - unit * 0.9, 24),
                    emptyNote: contents.note
                )
            } else {
                EventsMessage(state: state, unit: unit, alignment: .leading)
                    .padding(.horizontal, unit * 0.6)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, unit * 0.5)
        .frame(width: width, alignment: .topLeading)
    }
}

/// Horizontal day timeline beneath the face.
struct EventsStrip: View {
    let state: EventsPanelState
    /// Height already reserved by the layout (see `EventsPanelMetrics`).
    let height: CGFloat
    /// Current minute, from the same tick that drives the face.
    let now: Date

    private var unit: CGFloat { min(max(height * 0.15, 9.5), 14) }
    /// The hour ruler runs along the top of the strip.
    private var ruler: CGFloat { unit * 1.25 }
    private var pointsPerHour: CGFloat { unit * 8 }
    private var allDayWidth: CGFloat { unit * 7 }

    var body: some View {
        Group {
            if let contents = state.timelineContents {
                let allDay = contents.events.filter(\.isAllDay)
                let inset = unit * 0.4

                HStack(spacing: unit * 0.4) {
                    if !allDay.isEmpty {
                        AllDayStrip(events: allDay, unit: unit, orientation: .horizontal,
                                    extent: allDayWidth)
                            .padding(.leading, inset)
                    }

                    DayTimelineView(
                        orientation: .horizontal,
                        events: contents.events,
                        now: now,
                        unit: unit,
                        pointsPerHour: pointsPerHour,
                        rulerExtent: ruler,
                        laneExtent: max(height - ruler - inset * 2, 20),
                        emptyNote: contents.note
                    )
                }
                .padding(.vertical, inset)
            } else {
                EventsMessage(state: state, unit: unit, alignment: .center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, unit)
            }
        }
        .frame(height: height, alignment: .center)
    }
}
