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

/// The clock itself, scaled to whatever space it is given.
struct ClockFaceView: View {
    let face: ClockFace

    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width / 4.6, geo.size.height / 1.15)
            HStack(alignment: .center, spacing: unit * 0.08) {
                FlipDigit(value: face.hourTens, size: unit).id("h1")
                FlipDigit(value: face.hourOnes, size: unit).id("h2")

                Text(":")
                    .font(.system(size: unit * 0.42, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.55))
                    .frame(width: unit * 0.22)

                FlipDigit(value: face.minuteTens, size: unit).id("m1")
                FlipDigit(value: face.minuteOnes, size: unit).id("m2")

                Text(face.meridiem)
                    .font(.system(size: unit * 0.16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.55))
                    .frame(width: unit * 0.30, alignment: .leading)
                    .accessibilityHidden(true)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(face.spokenLabel)
    }
}
