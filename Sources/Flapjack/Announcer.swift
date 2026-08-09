import AVFoundation
import Foundation

/// Speaks the time aloud. The synthesizer must be a stored property — a local
/// one deallocates and cuts the utterance off silently.
@MainActor
final class Announcer {

    private let synth = AVSpeechSynthesizer()

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

    /// Highest-quality installed en-US voice, falling back to the system default.
    private lazy var voice: AVSpeechSynthesisVoice? = {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en-US") }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    func announce(_ date: Date) {
        speak(Self.phrase(for: date, time: timeFormatter, hour: hourFormatter))
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
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
