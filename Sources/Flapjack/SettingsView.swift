import AVFoundation
import SwiftUI

/// The three panes of the Settings window. Raw values are persisted, so they
/// are part of the defaults contract and must not be renamed.
private enum SettingsTab: String, CaseIterable {
    case general
    case speech
    case alerts
}

/// One pane of the Settings window: a grouped form laid out at its own content
/// height, given a *definite* height of its own so the window can size itself to
/// the selected tab — the standard macOS settings behaviour, and the whole point
/// of the split. A greedy page (a plain `ScrollView`, or a `maxHeight` frame)
/// would make every tab as tall as the tallest one, which is exactly what this
/// window is trying to stop being.
///
/// The height is the form's own, capped: past the cap the page scrolls instead
/// of pushing the window off a short screen. Only the tallest state of the
/// tallest pane (Speech with the better-voice hint showing) reaches it.
private struct SettingsPage<Content: View>: View {
    let width: CGFloat
    let maxHeight: CGFloat
    @ViewBuilder let content: Content

    /// The form's laid-out height, measured rather than assumed: the panes grow
    /// and shrink as conditional hints and pickers appear.
    @State private var contentHeight: CGFloat?

    var body: some View {
        ScrollView {
            Form {
                content
            }
            .formStyle(.grouped)
            // Fixes the form to its content height, so what is measured below is
            // the height it *wants*, not the height the scroll view offered it.
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.size.height, initial: true) { _, height in
                            contentHeight = height
                        }
                }
            )
        }
        // No rubber-banding on the panes that fit, which is most of them.
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: width, height: min(contentHeight ?? maxHeight, maxHeight))
    }
}

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

    /// Shared for the same reason the announcer is: the Preview button below
    /// flies through the very controller the cadence boundary will use, with the
    /// style the boundary would use, so what the user auditions is what they
    /// will get.
    let banner: BannerFlightController

    /// Re-read whenever the window appears, and again when the system reports a
    /// change: a user sent to System Settings by the hint below downloads a
    /// voice and comes straight back, and the picker has to have it by then.
    @State private var voices: [VoiceOption] = []

    /// Which pane the user was last on. Persisted so reopening the window lands
    /// where they left it rather than always resetting to General.
    @AppStorage("settingsTab") private var selectedTab = SettingsTab.general.rawValue

    /// One page's worth of settings never grows past this, no matter how many
    /// conditional hints are showing; past it the page scrolls instead of
    /// pushing the window off small screens. Everything under it sizes the
    /// window to its own content, which is what makes the window height change
    /// as tabs are switched.
    private static let maxPageHeight: CGFloat = 420
    private static let pageWidth: CGFloat = 380

    var body: some View {
        TabView(selection: $selectedTab) {
            page { generalRows }
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general.rawValue)

            page { speechRows }
                .tabItem { Label("Speech", systemImage: "speaker.wave.2") }
                .tag(SettingsTab.speech.rawValue)

            page { alertRows }
                .tabItem { Label("Alerts", systemImage: "bell") }
                .tag(SettingsTab.alerts.rawValue)
        }
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

    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        SettingsPage(width: Self.pageWidth, maxHeight: Self.maxPageHeight, content: content)
    }

    // MARK: - General

    /// When the clock speaks up, and what the face itself shows about it —
    /// everything here is about the schedule rather than any one way of
    /// conveying it, plus the one window-level preference.
    @ViewBuilder
    private var generalRows: some View {
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

        // No explicit Divider: the grouped form already rules between rows,
        // and a manual one renders as a stray empty row beside them.
        Toggle("Always on top (⌘1)", isOn: Binding(
            get: { settings.alwaysOnTop },
            set: { settings.setAlwaysOnTop($0) }
        ))
    }

    // MARK: - Speech

    /// The spoken half of "convey with": whether the cadence speaks, in whose
    /// voice, and what happens to the music while it does. The cadence toggle
    /// leads, since the rows under it are only interesting once something
    /// speaks — though both the Test button and ducking stay live regardless,
    /// because the spacebar speaks whatever the cadence says.
    @ViewBuilder
    private var speechRows: some View {
        Text("Convey with:")
            .font(.callout)
            .foregroundStyle(.secondary)

        Toggle("Voice", isOn: Binding(
            get: { settings.speakOnCadence },
            set: { settings.setSpeakOnCadence($0) }
        ))
        .disabled(settings.announceMode == .off)

        voiceSection

        duckingRows
    }

    // MARK: - Alerts

    /// The two silent ways a boundary can announce itself: a system
    /// notification, and a banner flying across the screen. Both are disabled
    /// with cadence Off, where there is no boundary to convey — the Preview
    /// button excepted, for the same reason the voice Test is.
    @ViewBuilder
    private var alertRows: some View {
        Text("Convey with:")
            .font(.callout)
            .foregroundStyle(.secondary)

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

        bannerRows
    }

    /// The third convey method, plus the choice of who carries it. Its Preview
    /// button is the only trigger for a flight outside the cadence — the same
    /// audition role the voice Test button plays — so it stays enabled even
    /// with cadence Off, where the toggle beside it has nothing to act on.
    @ViewBuilder
    private var bannerRows: some View {
        HStack {
            Toggle("Flying banner", isOn: Binding(
                get: { settings.bannerOnCadence },
                set: { settings.setBannerOnCadence($0) }
            ))
            .disabled(settings.announceMode == .off)

            Spacer()

            Button("Preview") { banner.fly(at: Date(), style: settings.bannerStyle) }
                .help("Send one banner across the screen now")
        }

        // Appears with the toggle rather than sitting permanently disabled
        // beside it, the same way the custom-interval stepper follows its own
        // cadence mode: a style is only a question once there is a banner.
        if settings.bannerOnCadence {
            Picker("Style:", selection: settings.bannerStyleBinding) {
                ForEach(BannerStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
        }

        Text("A little plane — or a cat waving hello — carries the time across your screen.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Sits with the voice rows because it is about the voice being *heard*,
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
