import AVFoundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    /// Shared with the rest of the app so the Test button auditions through the
    /// same synthesizer that does the announcing.
    let announcer: Announcer

    /// Re-read whenever the window appears, and again when the system reports a
    /// change: a user sent to System Settings by the hint below downloads a
    /// voice and comes straight back, and the picker has to have it by then.
    @State private var voices: [VoiceOption] = []

    var body: some View {
        Form {
            Picker("Announce time:", selection: settings.announceModeBinding) {
                ForEach(AnnounceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.inline)

            if settings.announceMode == .custom {
                Stepper(
                    value: settings.customMinutesBinding,
                    in: AppSettings.customMinutesRange
                ) {
                    Text("Every \(settings.customMinutes) minute\(settings.customMinutes == 1 ? "" : "s")")
                }
                Text("Announced when the minute is a multiple of the interval, anchored to the hour.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Show cadence fill", isOn: Binding(
                get: { settings.showCadenceFill },
                set: { settings.setShowCadenceFill($0) }
            ))
            .disabled(settings.announceMode == .off)

            Text("A lit panel behind the clock that shrinks as the next announcement approaches.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            voiceSection

            // No explicit Divider: the grouped form already rules between rows,
            // and a manual one renders as a stray empty row beside them.
            Toggle("Always on top (⌘1)", isOn: Binding(
                get: { settings.alwaysOnTop },
                set: { settings.setAlwaysOnTop($0) }
            ))
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refreshVoices)
        .onReceive(
            NotificationCenter.default.publisher(
                for: AVSpeechSynthesizer.availableVoicesDidChangeNotification
            )
        ) { _ in refreshVoices() }
    }

    // MARK: - Voice

    @ViewBuilder
    private var voiceSection: some View {
        HStack {
            Picker("Voice:", selection: settings.voiceIdentifierBinding) {
                Text("Automatic (best installed)").tag("")
                ForEach(voices) { voice in
                    Text(voice.displayName).tag(voice.id)
                }
            }
            Button("Test") { announcer.announce(Date()) }
                .help("Speak the current time with this voice")
        }

        if needsBetterVoice {
            Text("Only compact system voices are installed — the robotic-sounding kind. macOS can download far more natural ones (Ava and Zoe are the best for US English) from Accessibility → \(Self.spokenContentPaneName) → System Voice.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open System Settings…", action: openSpokenContentSettings)
                .help("Accessibility → \(Self.spokenContentPaneName) → System Voice → Manage Voices")
        }
    }

    /// macOS 26 renamed the Spoken Content pane to "Read & Speak"; naming the
    /// wrong one sends the user hunting through Accessibility.
    private static var spokenContentPaneName: String {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        ) ? "Read & Speak" : "Spoken Content"
    }

    /// True when nothing better than a stock compact voice is installed — the
    /// exact situation the user hears as "robotic".
    private var needsBetterVoice: Bool {
        (voices.first?.quality ?? .standard) == .standard
    }

    private func refreshVoices() {
        voices = VoiceCatalog.availableOptions(including: settings.voiceIdentifier)
    }

    /// Deep-links to Accessibility → Spoken Content, where the voice downloads
    /// live. The pane became an extension bundle in Ventura but still declares
    /// the old prefPane id as its `legacyBundleIdentifier`, and that alias is
    /// the form that has worked unchanged from Ventura through macOS 26 — the
    /// extension id follows only as a hedge. Both were verified on macOS 26; the
    /// `SpokenContent` anchor is what makes it land on the pane rather than the
    /// Accessibility root.
    private func openSpokenContentSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent",
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}
