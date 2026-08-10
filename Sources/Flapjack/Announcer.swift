import AVFoundation
import Foundation
import OSLog

/// Speaks the time aloud. The synthesizer must be a stored property — a local
/// one deallocates and cuts the utterance off silently.
///
/// This is the app's single speech path: cadence boundaries, the spacebar, the
/// menu command and the Settings Test button all arrive here, which is what lets
/// the ducking below be wired in one place and cover every one of them.
@MainActor
final class Announcer: NSObject {

    private let synth = AVSpeechSynthesizer()
    private let log = Logger(subsystem: "com.s4lly.flapjack", category: "speech")

    /// The user's chosen voice identifier, or `""` for automatic. A closure
    /// rather than a stored value so the announcer stays independent of
    /// `AppSettings` and always reads the *current* choice — the setting can
    /// change between announcements, and so can the set of installed voices.
    var voiceIdentifier: @MainActor () -> String = { "" }

    /// Turns other apps' music down for the length of an utterance. Optional and
    /// set at bootstrap; `nil` simply means the app never ducks.
    var ducker: AudioDucker?

    /// Read per utterance for the same reason as the voice: the setting can be
    /// switched off between announcements. Switching it off *during* one still
    /// restores, because the restore is driven by the ducker's own state rather
    /// than by this closure.
    var duckOtherAudio: @MainActor () -> Bool = { false }

    /// The utterance whose ending is allowed to lift the duck.
    ///
    /// Rapid re-triggers are the whole reason this exists. `speak` cancels
    /// whatever is in flight, and that cancellation arrives as a delegate
    /// callback for the *outgoing* utterance — which must not be read as "the
    /// speech is over, put the music back", because the replacement is about to
    /// start. Tracking identity means only the last utterance's ending counts,
    /// so a double tap ducks once and restores once. Held as an
    /// `ObjectIdentifier` rather than the utterance so the nonisolated delegate
    /// callbacks can hand it across to the main actor.
    private var currentUtterance: ObjectIdentifier?

    override init() {
        super.init()
        synth.delegate = self
    }

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

        // Ducking first, and before the cancel below: the ramp is a few tenths
        // of a second and runs off the main thread, so it overlaps the start of
        // the utterance rather than delaying it. A duck already in progress is
        // left alone, keeping the volumes saved by the first trigger.
        if duckOtherAudio() { ducker?.duck() }

        // Claim the utterance *before* stopping the old one. `stopSpeaking` can
        // deliver `didCancel` synchronously, and by then this must already be
        // the current utterance so that callback is recognised as stale.
        currentUtterance = ObjectIdentifier(utterance)
        synth.stopSpeaking(at: .immediate)   // never stack announcements
        synth.speak(utterance)
    }

    /// Called for whichever of finish/cancel arrives; only the utterance that is
    /// still current lifts the duck.
    private func utteranceEnded(_ utterance: ObjectIdentifier) {
        guard currentUtterance == utterance else { return }
        currentUtterance = nil
        ducker?.restore()
    }
}

extension Announcer: AVSpeechSynthesizerDelegate {

    /// Both endings route to the same place. The delegate is not declared
    /// main-actor by AVFoundation, so the utterance — which isn't `Sendable` —
    /// is reduced to its identity here, on whatever thread the callback lands
    /// on, and only that value crosses to the main actor.
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor in utteranceEnded(identity) }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor in utteranceEnded(identity) }
    }
}
