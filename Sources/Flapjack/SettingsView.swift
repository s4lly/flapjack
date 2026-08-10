import AVFoundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    /// Shared with the rest of the app so the Test button auditions through the
    /// same synthesizer that does the announcing.
    let announcer: Announcer

    /// Shared for the same reason: the toggle below has to request permission
    /// through the same object that will later do the posting, so the
    /// authorization state the UI shows is the one the boundary will act on.
    @ObservedObject var notifier: NotificationAnnouncer

    /// Shared for the same reason again: whether the user allowed us to control
    /// their music player is something only the ducker learns, and only by
    /// trying — so the hint below has to read the state of the very object the
    /// announcer ducks with.
    @ObservedObject var ducker: AudioDucker

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

            conveySection

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
        .onAppear {
            refreshVoices()
            // The user can revoke notification permission in System Settings
            // while the app runs, and nothing tells us when they do — so the
            // state is re-read every time this window comes up.
            notifier.refreshAuthorization()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AVSpeechSynthesizer.availableVoicesDidChangeNotification
            )
        ) { _ in refreshVoices() }
    }

    // MARK: - Convey with

    /// How a cadence boundary is delivered. Both toggles are independent, and
    /// both are disabled with cadence Off, where there is no boundary to
    /// convey — the spacebar's on-demand speech is deliberately outside this
    /// group and ignores both.
    @ViewBuilder
    private var conveySection: some View {
        Text("Convey with:")
            .font(.callout)
            .foregroundStyle(.secondary)

        Toggle("Voice", isOn: Binding(
            get: { settings.speakOnCadence },
            set: { settings.setSpeakOnCadence($0) }
        ))
        .disabled(settings.announceMode == .off)

        Toggle("Notification", isOn: Binding(
            get: { settings.notifyOnCadence },
            set: { setNotifyOnCadence($0) }
        ))
        .disabled(settings.announceMode == .off)

        if notifier.authorization == .denied {
            Text("Notifications are turned off for Flapjack. Allow them in System Settings → Notifications → Flapjack.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Notification Settings…", action: openNotificationSettings)
                .help("System Settings → Notifications → Flapjack")
        } else {
            // The single most common surprise about this feature: the banner
            // vanishing after a few seconds is the user's own alert style, not
            // something the app chose or can override.
            Text("Notifications stay on screen only if you set Flapjack's alert style to \"\(Self.persistentAlertStyleName)\" in System Settings → Notifications → Flapjack; with \"\(Self.temporaryAlertStyleName)\" they fade after a few seconds.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        duckingRows
    }

    /// Sits with the convey toggles because it is about the voice being *heard*,
    /// but deliberately isn't disabled with cadence Off: the spacebar speaks
    /// regardless of the cadence, and it is the trigger most likely to land in
    /// the middle of a loud track.
    @ViewBuilder
    private var duckingRows: some View {
        Toggle("Lower other apps' audio while speaking", isOn: Binding(
            get: { settings.duckOtherAudio },
            set: { settings.setDuckOtherAudio($0) }
        ))

        Text("Works with music players macOS can script — Spotify and Music. Their volume drops while the time is spoken and goes straight back. macOS asks your permission to control each player the first time, and audio from apps that can't be scripted (browsers, games, calls) can't be lowered.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        // Shown only after a player has actually refused us, which is the only
        // state the user has to leave the app to fix — the same rule the
        // notification and voice hints follow.
        if ducker.automationDenied {
            Text("Flapjack isn't allowed to control your music player. Switch it on in System Settings → Privacy & Security → Automation → Flapjack.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Automation Settings…", action: openAutomationSettings)
                .help("System Settings → Privacy & Security → Automation")
        }
    }

    /// Deep-links to Privacy & Security → Automation. The `Privacy_Automation`
    /// anchor on the old security prefPane id is the form that has worked
    /// unchanged since Mojave introduced the pane, and still lands correctly on
    /// macOS 26; the Ventura-era extension bundle id follows as a hedge.
    private func openAutomationSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    /// macOS 26 renamed the per-app alert styles from "Alerts"/"Banners" to
    /// "Persistent"/"Temporary" — verified in the pane the button below opens.
    /// Naming the wrong pair sends the user looking for a control that isn't
    /// there, so the copy branches the same way the voice hint does.
    private static var persistentAlertStyleName: String {
        isMacOS26OrLater ? "Persistent" : "Alerts"
    }

    private static var temporaryAlertStyleName: String {
        isMacOS26OrLater ? "Temporary" : "Banners"
    }

    private static var isMacOS26OrLater: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        )
    }

    /// Switching the toggle on is what asks for permission — never launch, and
    /// never merely opening this window. Mirrors how the events panel treats
    /// calendar access.
    private func setNotifyOnCadence(_ on: Bool) {
        settings.setNotifyOnCadence(on)
        guard on else { return }
        notifier.requestAuthorizationIfNeeded()
    }

    /// Deep-links to Notifications in System Settings. The per-app row can be
    /// addressed directly on macOS 26 by passing the bundle identifier as the
    /// anchor; the bare pane follows as a fallback, since that form is the one
    /// that has worked unchanged since Ventura.
    private func openNotificationSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.s4lly.flapjack",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
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
