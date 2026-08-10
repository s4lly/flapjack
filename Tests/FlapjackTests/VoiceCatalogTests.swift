import Foundation
import Testing

@testable import Flapjack

private func voice(
    _ id: String,
    _ name: String,
    _ language: String,
    _ quality: VoiceQuality = .standard
) -> VoiceOption {
    VoiceOption(id: id, name: name, language: language, quality: quality)
}

private let samantha = voice("com.apple.voice.compact.en-US.Samantha", "Samantha", "en-US")
private let ava = voice("com.apple.voice.premium.en-US.Ava", "Ava", "en-US", .premium)
private let daniel = voice("com.apple.voice.enhanced.en-GB.Daniel", "Daniel", "en-GB", .enhanced)
private let thomas = voice("com.apple.voice.super-compact.fr-FR.Thomas", "Thomas", "fr-FR")
private let kyoko = voice("com.apple.voice.super-compact.ja-JP.Kyoko", "Kyoko", "ja-JP")
private let zarvox = voice("com.apple.speech.synthesis.voice.Zarvox", "Zarvox", "en-US")
private let eloquence = voice("com.apple.eloquence.en-US.Rocko", "Rocko", "en-US")

private let english = ["en-US", "en"]

@Suite("VoiceCatalog")
struct VoiceCatalogTests {

    // MARK: - Filtering

    @Test("MacinTalk and Eloquence voices are never offered")
    func excludesLegacyVoices() {
        #expect(VoiceCatalog.isOfferable(samantha))
        #expect(!VoiceCatalog.isOfferable(zarvox))
        #expect(!VoiceCatalog.isOfferable(eloquence))

        let options = VoiceCatalog.options(
            from: [zarvox, eloquence, samantha],
            preferredLanguages: english
        )
        #expect(options == [samantha])
    }

    @Test("A voice the system flags as novelty is never offered")
    func excludesNoveltyTrait() {
        var joke = voice("com.example.voice.Kazoo", "Kazoo", "en-US", .premium)
        joke.isNovelty = true
        #expect(!VoiceCatalog.isOfferable(joke))
        #expect(VoiceCatalog.options(from: [joke, samantha], preferredLanguages: english) == [samantha])
    }

    @Test("An exact locale match outranks a mere language match")
    func prefersTheExactLocale() {
        // Both are en, so without tag-level ranking "Daniel" would beat
        // "Samantha" on name alone and an en-US user would get a British clock.
        let daniel = voice("com.apple.voice.compact.en-GB.Daniel", "Daniel", "en-GB")
        let options = VoiceCatalog.options(from: [daniel, samantha], preferredLanguages: english)
        #expect(options == [samantha, daniel])
    }

    @Test("Compact voices rank above super-compact ones")
    func prefersCompactOverSuperCompact() {
        let karen = voice("com.apple.voice.super-compact.en-AU.Karen", "Karen", "en-AU")
        let options = VoiceCatalog.options(from: [karen, samantha], preferredLanguages: english)
        #expect(options == [samantha, karen])
    }

    @Test("Standard voices outside the preferred languages are dropped")
    func dropsUnrelatedLanguages() {
        let options = VoiceCatalog.options(
            from: [samantha, thomas, kyoko],
            preferredLanguages: english
        )
        #expect(options == [samantha])
    }

    @Test("Standard voices in a preferred language are kept")
    func keepsPreferredLanguages() {
        let options = VoiceCatalog.options(
            from: [samantha, thomas, kyoko],
            preferredLanguages: ["fr-FR", "en-US"]
        )
        #expect(options == [thomas, samantha])
    }

    @Test("Only the leading preferred languages count")
    func ignoresTheTailOfTheSystemLanguageList() {
        // macOS seeds preferredLanguages with every localisation it ships, so a
        // language buried at the end is not evidence the user speaks it.
        let padding = Array(repeating: "de-DE", count: VoiceCatalog.preferredLanguageDepth)
        let options = VoiceCatalog.options(
            from: [samantha, kyoko],
            preferredLanguages: padding + ["ja-JP"]
        )
        #expect(options == [samantha])
    }

    @Test("A downloaded voice is kept whatever its language")
    func keepsDownloadedVoicesInAnyLanguage() {
        let premiumJapanese = voice("com.apple.voice.premium.ja-JP.O-ren", "O-ren", "ja-JP", .premium)
        let options = VoiceCatalog.options(
            from: [samantha, premiumJapanese],
            preferredLanguages: english
        )
        #expect(options == [premiumJapanese, samantha])
    }

    @Test("English survives even when it is not a preferred language")
    func alwaysKeepsEnglish() {
        let options = VoiceCatalog.options(
            from: [samantha, thomas],
            preferredLanguages: ["fr-FR"]
        )
        #expect(options == [thomas, samantha])
    }

    // MARK: - Ordering

    @Test("Best quality first, then language preference, then name")
    func ordersByQualityThenPreference() {
        let options = VoiceCatalog.options(
            from: [samantha, daniel, ava, thomas],
            preferredLanguages: ["en-US", "fr-FR"]
        )
        #expect(options.map(\.id) == [ava.id, daniel.id, samantha.id, thomas.id])
    }

    @Test("The first option is the automatic choice")
    func automaticIsTheBestInstalledVoice() {
        let options = VoiceCatalog.options(from: [samantha, ava], preferredLanguages: english)
        #expect(options.first == ava)
    }

    // MARK: - Selection

    @Test("The selected voice stays listed even when the rules would drop it")
    func keepsTheSelectedVoice() {
        let options = VoiceCatalog.options(
            from: [samantha, kyoko],
            preferredLanguages: english,
            including: kyoko.id
        )
        #expect(options.contains(kyoko))
    }

    @Test("A selection that is no longer installed simply disappears")
    func forgetsAnUninstalledSelection() {
        let options = VoiceCatalog.options(
            from: [samantha],
            preferredLanguages: english,
            including: ava.id
        )
        #expect(options == [samantha])
    }

    // MARK: - Quality

    @Test("Quality ranks premium above enhanced above standard")
    func qualityOrdering() {
        #expect(VoiceQuality.premium > .enhanced)
        #expect(VoiceQuality.enhanced > .standard)
        #expect(VoiceQuality.standard.label == nil)
    }

    @Test("Display names carry the quality and language")
    func displayNames() {
        #expect(samantha.displayName.hasPrefix("Samantha · "))
        #expect(ava.displayName.hasPrefix("Ava (Premium) · "))
        #expect(daniel.displayName.hasPrefix("Daniel (Enhanced) · "))
    }
}
