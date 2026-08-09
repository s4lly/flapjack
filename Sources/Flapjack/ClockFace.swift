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
enum FaceMetrics {
    /// Width of a single flip card (see `HalfCard`).
    static let cardWidth: CGFloat = 0.64
    /// Horizontal gap between adjacent elements.
    static let gap: CGFloat = 0.08
    static let colonWidth: CGFloat = 0.26
    /// hour tens, hour ones, colon, minute tens, minute ones. The meridiem is
    /// drawn as a badge inside the last card, so it claims no column of its own
    /// and costs the layout nothing.
    private static let elementCount: CGFloat = 5

    /// Total width of the laid-out face, in units.
    static let contentWidth: CGFloat =
        4 * cardWidth + colonWidth + (elementCount - 1) * gap

    /// Total height: two half cards plus the sliver of spacing between them.
    static let contentHeight: CGFloat = 1.02

    /// Breathing room left around the face, as a fraction of the smaller
    /// window dimension.
    static let marginFraction: CGFloat = 0.03

    /// The card height that makes the face fill `size` as tightly as the
    /// content's own aspect ratio allows.
    static func unit(fitting size: CGSize) -> CGFloat {
        let margin = min(size.width, size.height) * marginFraction
        let available = CGSize(width: max(0, size.width - 2 * margin),
                               height: max(0, size.height - 2 * margin))
        return min(available.width / contentWidth, available.height / contentHeight)
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

    var body: some View {
        Text(text)
            .font(.system(size: max(9, unit * 0.13), weight: .semibold, design: .rounded))
            .foregroundStyle(Color(white: 0.58))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, unit * 0.038)
            .padding(.vertical, unit * 0.014)
            .background(
                RoundedRectangle(cornerRadius: unit * 0.032, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            // Inset from the card's rounded corner; the digit's glyph sits well
            // above this, so the badge never overlaps it.
            .padding(unit * 0.05)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The clock itself, scaled to whatever space it is given.
struct ClockFaceView: View {
    let face: ClockFace

    var body: some View {
        GeometryReader { geo in
            let unit = FaceMetrics.unit(fitting: geo.size)
            HStack(alignment: .center, spacing: unit * FaceMetrics.gap) {
                FlipDigit(value: face.hourTens, size: unit).id("h1")
                FlipDigit(value: face.hourOnes, size: unit).id("h2")

                Text(":")
                    .font(.system(size: unit * 0.42, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.55))
                    .frame(width: unit * FaceMetrics.colonWidth)

                FlipDigit(value: face.minuteTens, size: unit).id("m1")

                // The badge is layered over the finished card rather than
                // inside it, so it stays put while the halves flip.
                ZStack(alignment: .bottomTrailing) {
                    FlipDigit(value: face.minuteOnes, size: unit).id("m2")
                    MeridiemBadge(text: face.meridiem, unit: unit)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        // `spokenLabel` carries the meridiem, which matters more now that the
        // on-screen indicator is a small in-card badge.
        .accessibilityLabel(face.spokenLabel)
    }
}
