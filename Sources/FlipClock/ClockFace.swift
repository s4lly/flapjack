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
    /// Just wide enough for "AM"/"PM" at 0.16u — slack here shows up as dead
    /// space on the right edge, but too little wraps the label onto two lines.
    static let meridiemWidth: CGFloat = 0.27
    /// hour tens, hour ones, colon, minute tens, minute ones, meridiem.
    private static let elementCount: CGFloat = 6

    /// Total width of the laid-out face, in units.
    static let contentWidth: CGFloat =
        4 * cardWidth + colonWidth + meridiemWidth + (elementCount - 1) * gap

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
                FlipDigit(value: face.minuteOnes, size: unit).id("m2")

                Text(face.meridiem)
                    .font(.system(size: unit * 0.16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: unit * FaceMetrics.meridiemWidth, alignment: .leading)
                    .accessibilityHidden(true)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(face.spokenLabel)
    }
}
