import AVFoundation
import Foundation
import OSLog

/// Speaks the time aloud. The synthesizer must be a stored property — a local
/// one deallocates and cuts the utterance off silently.
@MainActor
final class Announcer {

    private let synth = AVSpeechSynthesizer()
    private let log = Logger(subsystem: "com.s4lly.flapjack", category: "speech")

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f
    }()

    private let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h"
        return f
    }()

    /// The user's chosen voice identifier, or `""` for automatic. A closure
    /// rather than a stored value so the announcer stays independent of
    /// `AppSettings` and always reads the *current* choice — the setting can
    /// change between announcements, and so can the set of installed voices.
    var voiceIdentifier: @MainActor () -> String = { "" }

    func announce(_ date: Date) {
        speak(Self.phrase(for: date, time: timeFormatter, hour: hourFormatter))
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        // Resolved per utterance, not cached: voices can be downloaded (or the
        // chosen one removed) while the app runs.
        utterance.voice = VoiceCatalog.resolvedVoice(identifier: voiceIdentifier())
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        log.info("speaking \"\(text, privacy: .public)\" with \(utterance.voice?.identifier ?? "system default", privacy: .public)")
        synth.stopSpeaking(at: .immediate)   // never stack announcements
        synth.speak(utterance)
    }

    /// On the hour some voices garble "10:00 PM", so say "10 o'clock" instead.
    static func phrase(for date: Date, time: DateFormatter, hour: DateFormatter) -> String {
        let minute = Calendar.current.dateComponents([.minute], from: date).minute ?? 0
        if minute == 0 {
            return "It's \(hour.string(from: date)) o'clock"
        }
        return "It's \(time.string(from: date))"
    }
}
