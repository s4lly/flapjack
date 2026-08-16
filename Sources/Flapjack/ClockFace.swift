import Foundation
import SwiftUI

/// The digits shown on the face, derived from a date. Pure value type so the
/// display logic is testable and view-independent.
struct ClockFace: Equatable {
    let hourTens: String
    let hourOnes: String
    let minuteTens: String
    let minuteOnes: String
    let meridiem: String

    init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour24 = parts.hour ?? 0
        let minute = parts.minute ?? 0
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 }

        hourTens = String(hour12 / 10)
        hourOnes = String(hour12 % 10)
        minuteTens = String(minute / 10)
        minuteOnes = String(minute % 10)
        meridiem = hour24 < 12 ? "AM" : "PM"
    }

    var spokenLabel: String {
        let hours = hourTens == "0" ? hourOnes : hourTens + hourOnes
        return "\(hours):\(minuteTens)\(minuteOnes) \(meridiem)"
    }
}

/// Layout proportions of the face, all expressed as multiples of `unit` (the
/// height of one flip card). They are declared here rather than inlined so the
/// scale calculation can be derived from the same numbers the views draw with —
/// otherwise the face silently underfills whenever the two drift apart.
///
/// There are two arrangements of the same four cards — `horizontal` (`HH:MM` on
/// one row) and `stacked` (`HH` over `MM`) — and each derives its own unit from
/// its own content aspect, so the choice between them is simply "whichever draws
/// the digits bigger in this region".
struct FaceMetrics {
    /// Width of a single flip card (see `HalfCard`).
    var cardWidth: CGFloat = 0.64
    /// Horizontal gap between adjacent elements.
    var gap: CGFloat = 0.08
    var colonWidth: CGFloat = 0.26
    /// Gutter between the hour row and the minute row; the horizontal layout
    /// has no second row, so it is zero there.
    var rowGap: CGFloat = 0
    var rows: CGFloat = 1

    /// Height of one card: two half cards plus the sliver of spacing between
    /// them.
    static let cardHeight: CGFloat = 1.02

    /// Breathing room left around the face, as a fraction of the smaller
    /// region dimension.
    static let marginFraction: CGFloat = 0.03

    /// `HH:MM` across one row.
    static let horizontal = FaceMetrics()

    /// `HH` over `MM`, with the colon's two dots turned on their side into the
    /// gutter. The gutter is wide enough that the dots crowd neither row.
    static let stacked = FaceMetrics(rowGap: 0.26, rows: 2)

    var isStacked: Bool { rows > 1 }

    /// Horizontal: four cards plus the colon, with four gaps. Stacked: two
    /// cards and one gap. The meridiem is drawn as a badge inside the last card
    /// either way, so it claims no column of its own and costs nothing.
    var contentWidth: CGFloat {
        isStacked ? 2 * cardWidth + gap : 4 * cardWidth + colonWidth + 4 * gap
    }

    var contentHeight: CGFloat { rows * Self.cardHeight + (rows - 1) * rowGap }

    /// The card height that makes this arrangement fill `size` as tightly as
    /// its own aspect ratio allows.
    func unit(fitting size: CGSize) -> CGFloat {
        let margin = min(size.width, size.height) * Self.marginFraction
        let available = CGSize(width: max(0, size.width - 2 * margin),
                               height: max(0, size.height - 2 * margin))
        return min(available.width / contentWidth, available.height / contentHeight)
    }

    /// The arrangement that makes the digits largest in `size`. Comparing units
    /// rather than testing the region's aspect against a threshold is what makes
    /// this correct everywhere: the crossover (~1.47 for these proportions) falls
    /// out of the comparison, and the degenerate bands — where both layouts are
    /// bound by the same dimension — resolve on their own.
    static func best(fitting size: CGSize) -> FaceMetrics {
        stacked.unit(fitting: size) > horizontal.unit(fitting: size) ? stacked : horizontal
    }

    /// The unit the face will actually be drawn at in `size`.
    static func unit(fitting size: CGSize) -> CGFloat {
        best(fitting: size).unit(fitting: size)
    }
}

/// The AM/PM indicator, tucked into the bottom-right corner of the last minute
/// card. It deliberately claims no layout width of its own: that horizontal
/// space is reserved for future features, and giving it back to the cards makes
/// the digits noticeably larger.
///
/// Everything scales with `unit` so the badge keeps its proportions at any
/// window size, with a small absolute floor on the type size so it stays
/// readable when the window is near its minimum.
struct MeridiemBadge: View {
    let text: String
    let unit: CGFloat

    // PROTOTYPE — see FaceStylePrototype.swift.
    @Environment(\.faceRenderStyle) private var protoStyle

    var body: some View {
        Text(text)
            .font(.system(size: max(9, unit * 0.13), weight: .semibold, design: .rounded))
            .foregroundStyle(protoStyle?.theme.badgeText ?? Color(white: 0.58))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, unit * 0.038)
            .padding(.vertical, unit * 0.014)
            .background(
                RoundedRectangle(cornerRadius: unit * 0.032, style: .continuous)
                    .fill(protoStyle?.theme.badgeFill ?? Color.white.opacity(0.07))
            )
            // Inset from the card's rounded corner; the digit's glyph sits well
            // above this, so the badge never overlaps it.
            .padding(unit * 0.05)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The clock itself, scaled to whatever space it is given, and arranged the way
/// that space suits: `HH:MM` across when the region is wide, `HH` over `MM` when
/// it is tall or narrow. The switch is pure geometry, so it happens live as the
/// window resizes or the events divider is dragged, with or without the panel.
struct ClockFaceView: View {
    let face: ClockFace

    // PROTOTYPE — see FaceStylePrototype.swift.
    @Environment(\.faceRenderStyle) private var protoStyle

    /// The colon and the stacked layout's dots.
    private var accentColor: Color { protoStyle?.theme.accent ?? Color(white: 0.55) }

    var body: some View {
        GeometryReader { geo in
            let metrics = FaceMetrics.best(fitting: geo.size)
            let unit = metrics.unit(fitting: geo.size)

            Group {
                if metrics.isStacked {
                    stacked(unit: unit, metrics: metrics)
                } else {
                    across(unit: unit, metrics: metrics)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        // `spokenLabel` carries the meridiem, which matters more now that the
        // on-screen indicator is a small in-card badge.
        .accessibilityLabel(face.spokenLabel)
    }

    private func across(unit: CGFloat, metrics: FaceMetrics) -> some View {
        HStack(alignment: .center, spacing: unit * metrics.gap) {
            hours(unit: unit)

            Text(":")
                .font(.system(size: unit * 0.42, weight: .bold, design: .monospaced))
                .foregroundStyle(accentColor)
                .frame(width: unit * metrics.colonWidth)

            minutes(unit: unit)
        }
    }

    private func stacked(unit: CGFloat, metrics: FaceMetrics) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: unit * metrics.gap) { hours(unit: unit) }
            dots(unit: unit, metrics: metrics)
            HStack(spacing: unit * metrics.gap) { minutes(unit: unit) }
        }
    }

    /// The colon's two dots, turned on their side into the row gutter — the
    /// stacked rows read as two pairs on their own, but the dots keep the face
    /// recognisably a clock rather than a pair of numbers.
    private func dots(unit: CGFloat, metrics: FaceMetrics) -> some View {
        HStack(spacing: unit * 0.09) {
            Circle().frame(width: unit * 0.055, height: unit * 0.055)
            Circle().frame(width: unit * 0.055, height: unit * 0.055)
        }
        .foregroundStyle(accentColor)
        .frame(height: unit * metrics.rowGap)
    }

    @ViewBuilder
    private func hours(unit: CGFloat) -> some View {
        FlipDigit(value: face.hourTens, size: unit).id("h1")
        FlipDigit(value: face.hourOnes, size: unit).id("h2")
    }

    @ViewBuilder
    private func minutes(unit: CGFloat) -> some View {
        FlipDigit(value: face.minuteTens, size: unit).id("m1")

        // The badge is layered over the finished card rather than inside it, so
        // it stays put while the halves flip. It rides the last minute card in
        // both layouts — bottom-right of the bottom row when stacked.
        ZStack(alignment: .bottomTrailing) {
            FlipDigit(value: face.minuteOnes, size: unit).id("m2")
            MeridiemBadge(text: face.meridiem, unit: unit)
        }
    }
}
