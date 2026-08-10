import AVFoundation
import Foundation
import OSLog

/// Speaks the time aloud. The synthesizer must be a stored property — a local
/// one deallocates and cuts the utterance off silently.
@MainActor
final class Announcer {

    private let synth = AVSpeechSynthesizer()
    private let log = Logger(subsystem: "com.s4lly.flapjack", category: "speech")

    /// The user's chosen voice identifier, or `""` for automatic. A closure
    /// rather than a stored value so the announcer stays independent of
    /// `AppSettings` and always reads the *current* choice — the setting can
    /// change between announcements, and so can the set of installed voices.
    var voiceIdentifier: @MainActor () -> String = { "" }

    /// Wording comes from `TimePhrase`, shared with the notification path, so
    /// the two convey methods can't report different times.
    func announce(_ date: Date) {
        speak(TimePhrase.spoken(for: date))
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
}
