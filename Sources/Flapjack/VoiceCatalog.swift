import AVFoundation
import Foundation

/// How good a voice sounds, worst → best.
///
/// Mirrors `AVSpeechSynthesisVoiceQuality` (`.default`/`.enhanced`/`.premium`)
/// as a plain value so the catalog's filtering and ranking rules can be tested
/// without conjuring real `AVSpeechSynthesisVoice` objects — those can only be
/// obtained from the system, and only for voices that happen to be installed.
///
/// `.standard` is Apple's `.default`: the compact/super-compact voices every Mac
/// ships with. They are the robotic ones; enhanced and premium are downloads.
enum VoiceQuality: Int, Comparable, Sendable {
    case standard
    case enhanced
    case premium

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Suffix shown in the picker. Standard voices get none — labelling the
    /// baseline adds noise, and on a stock Mac every entry would carry it.
    var label: String? {
        switch self {
        case .standard: return nil
        case .enhanced: return "Enhanced"
        case .premium: return "Premium"
        }
    }
}

/// One installed voice, as the settings picker sees it.
struct VoiceOption: Identifiable, Hashable, Sendable {
    /// `AVSpeechSynthesisVoice.identifier`, e.g. `com.apple.voice.compact.en-US.Samantha`.
    let id: String
    let name: String
    /// BCP-47 tag, e.g. `en-US`.
    let language: String
    let quality: VoiceQuality
    /// The system's own `isNoveltyVoice` trait — Bells, Bubbles, Deranged and
    /// friends. Catches joke voices the identifier rules wouldn't, including any
    /// a third-party app installs.
    var isNovelty = false

    /// e.g. "Samantha (Enhanced) · English (US)".
    var displayName: String {
        let localized = Locale.current.localizedString(forIdentifier: language) ?? language
        guard let quality = quality.label else { return "\(name) · \(localized)" }
        return "\(name) (\(quality)) · \(localized)"
    }
}

/// Chooses which installed voices the app offers, and in what order.
///
/// The synthesis API is not the lever on how good the clock sounds — the
/// *installed voices* are. macOS ships only compact voices, so the catalog's job
/// is to surface the good ones when a user has downloaded them, hide the ones
/// that can only ever sound wrong, and let the app tell when nothing better than
/// compact is installed.
enum VoiceCatalog {

    /// Identifier prefixes never offered for announcing the time.
    ///
    /// `com.apple.speech.synthesis.voice.*` is the MacinTalk set — part novelty
    /// (Zarvox, Trinoids, Bubbles) and part 1990s formant voices (Fred, Junior,
    /// Kathy, Ralph) that the novelty trait does *not* flag but that sound just
    /// as wrong reading a clock. `com.apple.eloquence.*` is the DECtalk-lineage
    /// synthesiser: intelligible, unmistakably robotic. A stock Mac carries ~27
    /// of these per language, which would bury the handful of usable entries.
    static let excludedIdentifierPrefixes = [
        "com.apple.speech.synthesis.voice.",
        "com.apple.eloquence."
    ]

    /// How far down `Locale.preferredLanguages` counts as "a language the user
    /// actually uses". macOS seeds that list with ~35 entries covering every
    /// localisation it ships, so honouring all of it would offer a voice in
    /// every language on earth; the leading few are the ones the user ordered.
    static let preferredLanguageDepth = 3

    static func isOfferable(_ voice: VoiceOption) -> Bool {
        !voice.isNovelty && !excludedIdentifierPrefixes.contains { voice.id.hasPrefix($0) }
    }

    /// The voices to offer, best first.
    ///
    /// Kept: anything better than standard quality (its presence means the user
    /// deliberately downloaded it, whatever the language), plus standard voices
    /// in the user's leading preferred languages. English is always included, so
    /// the app never ends up with nothing to say the time in.
    ///
    /// Ordered by quality, then by how high the language ranks for the user,
    /// then compact ahead of super-compact, then by name — so the first entry is
    /// the best available voice, which is exactly what "Automatic" means.
    static func options(
        from voices: [VoiceOption],
        preferredLanguages: [String],
        including selected: String? = nil
    ) -> [VoiceOption] {
        let ranks = LanguageRanks(preferredLanguages: preferredLanguages)
        return voices
            .filter { option in
                guard isOfferable(option) else { return false }
                // A voice the user has already chosen stays listed even if it
                // no longer matches the rules, so the picker can never show a
                // blank selection.
                if option.id == selected { return true }
                return option.quality > .standard || ranks.speaks(option.language)
            }
            .sorted { a, b in
                if a.quality != b.quality { return a.quality > b.quality }
                let (rankA, rankB) = (ranks.rank(of: a.language), ranks.rank(of: b.language))
                if rankA != rankB { return rankA < rankB }
                if compactness(a) != compactness(b) { return compactness(a) < compactness(b) }
                if a.name != b.name { return a.name < b.name }
                return a.id < b.id
            }
    }

    /// Standard quality still comes in two grades: the `compact` bundles sound
    /// noticeably less clipped than the `super-compact` ones every locale ships.
    /// Lower is better.
    private static func compactness(_ voice: VoiceOption) -> Int {
        voice.id.hasPrefix("com.apple.voice.super-compact.") ? 1 : 0
    }

    /// How closely each language matches what the user reads, lower being better.
    ///
    /// Ranked on the full tag first and the bare language second: an en-US user
    /// gets Samantha rather than whichever `en-*` voice happens to sort first by
    /// name, while a French speaker with no fr-CA voice installed still gets
    /// fr-FR ahead of every other language.
    private struct LanguageRanks {
        private var tags: [String: Int] = [:]
        private var codes: [String: Int] = [:]

        init(preferredLanguages: [String]) {
            // English is appended so `en-*` voices always survive the filter —
            // the clock must always have some way to say the time.
            for language in preferredLanguages.prefix(preferredLanguageDepth) + ["en"] {
                let tag = language.lowercased()
                if tags[tag] == nil { tags[tag] = tags.count }
                let code = VoiceCatalog.languageCode(of: language)
                if codes[code] == nil { codes[code] = codes.count }
            }
        }

        func rank(of language: String) -> (Int, Int) {
            (tags[language.lowercased()] ?? .max, codes[VoiceCatalog.languageCode(of: language)] ?? .max)
        }

        /// Whether a voice in this language is worth offering at all.
        func speaks(_ language: String) -> Bool {
            codes[VoiceCatalog.languageCode(of: language)] != nil
        }
    }

    /// `en-US` → `en`, `zh-Hans` → `zh`. Voices are tagged by region but the
    /// user's preference list mixes bare codes and script/region variants.
    private static func languageCode(of language: String) -> String {
        String(language.split(separator: "-").first ?? "").lowercased()
    }
}

// MARK: - Live system voices

extension VoiceCatalog {

    /// Every voice installed right now. Re-read rather than cached: voices can
    /// be downloaded while the app is running.
    static func installedVoices() -> [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices().map(VoiceOption.init)
    }

    /// The picker's contents for the current system state.
    static func availableOptions(including selected: String? = nil) -> [VoiceOption] {
        options(
            from: installedVoices(),
            preferredLanguages: Locale.preferredLanguages,
            including: selected
        )
    }

    /// The voice to speak with. `identifier` empty — or naming a voice that has
    /// since been deleted — falls back to the best installed voice, and finally
    /// to whatever the system will give us for English.
    static func resolvedVoice(identifier: String) -> AVSpeechSynthesisVoice? {
        if !identifier.isEmpty, let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            return chosen
        }
        if let best = availableOptions().first,
           let voice = AVSpeechSynthesisVoice(identifier: best.id) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension VoiceOption {
    init(_ voice: AVSpeechSynthesisVoice) {
        self.init(
            id: voice.identifier,
            name: voice.name,
            language: voice.language,
            quality: VoiceQuality(voice.quality),
            isNovelty: voice.voiceTraits.contains(.isNoveltyVoice)
        )
    }
}

extension VoiceQuality {
    init(_ quality: AVSpeechSynthesisVoiceQuality) {
        switch quality {
        case .enhanced: self = .enhanced
        case .premium: self = .premium
        default: self = .standard
        }
    }
}
