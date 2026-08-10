import AppKit
import Foundation
import OSLog

/// A music player Flapjack knows how to turn down while it speaks.
///
/// Identified twice over, because the two identifiers do different jobs:
/// `bundleID` answers "is it running?" through `NSRunningApplication` without
/// touching the app, and `scriptName` is what goes in the `tell application`
/// line. Both are compile-time constants from the table below — nothing
/// user-supplied ever reaches the script source.
struct DuckablePlayer: Hashable, Sendable {
    let bundleID: String
    /// The name AppleScript addresses the app by.
    let scriptName: String
}

/// Lowers other apps' audio while the clock speaks, then puts it back.
///
/// ## Why this is done with Apple Events rather than audio APIs
///
/// macOS gives a third-party app no way to duck another app's audio directly.
/// Three routes were checked against the macOS 26 SDK and all three are closed:
///
/// - **`AVAudioSession` ducking** (`.duckOthers`) is the iOS answer, and the
///   class is `API_UNAVAILABLE(macos)` — declaration and every member. It
///   exists in the macOS SDK headers only for Catalyst.
/// - **Per-app volume** has no public API. Core Audio's HAL exposes volume on
///   *devices*, not on the process objects it added in macOS 14 — those carry
///   only `PID`, `BundleID`, `Devices` and `IsRunning*`. Utilities like
///   SoundSource achieve it with an installed audio driver, which is a very
///   different kind of product.
/// - **Routing our own speech elsewhere** so the *system* volume could be
///   ducked instead: `AVSpeechUtterance.outputChannels` and
///   `AVSpeechSynthesizer.usesApplicationAudioSession` are both
///   `API_UNAVAILABLE(macos)`. Speech goes out the default output device like
///   everything else, so turning that device down would mute the announcement
///   along with the music — self-defeating.
///
/// What *is* available is that the loud apps are usually scriptable. Spotify
/// and Music both publish a read/write integer `sound volume` (0–100) and a
/// read-only `player state`, so we can ask each one for its own volume and hand
/// it back afterwards. **The limitation is exactly that**: a player with no
/// scripting dictionary — a browser tab, a game, a video call — cannot be
/// ducked, and there is no fallback that would work.
///
/// ## Rules this object follows
///
/// - **Never launch anything.** `tell application "X"` starts X if it isn't
///   running, which would be an outrageous side effect of speaking the time. So
///   every send is gated on `NSRunningApplication`, on the way down *and* on the
///   way back up.
/// - **Only duck what is actually playing.** A paused Spotify is not drowning
///   anything out, and moving its volume would just be meddling.
/// - **Duck, don't cut.** The volume ramps to a quarter over ~0.3 s in four
///   steps, and ramps back the same way. A hard jump reads as a glitch.
/// - **Restore exactly.** The saved number is the one that goes back, not a
///   percentage recomputed from wherever the volume ended up.
///
/// ## Threading
///
/// `NSAppleScript` is blocking and not thread-safe, so all of it runs on one
/// private serial queue — which also gives the ordering guarantee the feature
/// depends on: a restore enqueued while the duck ramp is still running cannot
/// overtake it and read a volume that hasn't been saved yet. Observable state
/// stays on the main actor; only `DuckState` crosses over.
@MainActor
final class AudioDucker: ObservableObject {

    /// The players we know how to turn down. Extending the feature to another
    /// scriptable player is one line here — everything else is generic.
    /// `nonisolated` because the script queue reads it, not the main actor.
    nonisolated static let players: [DuckablePlayer] = [
        DuckablePlayer(bundleID: "com.spotify.client", scriptName: "Spotify"),
        DuckablePlayer(bundleID: "com.apple.Music", scriptName: "Music")
    ]

    /// True once a player has refused us on TCC grounds, so Settings can
    /// explain itself. Cleared as soon as any send succeeds again — the user
    /// can grant permission in System Settings while the app runs, and nothing
    /// tells us when they do.
    @Published private(set) var automationDenied = false

    /// Force-restores if the synthesizer's delegate callbacks never arrive.
    /// Comfortably longer than any time-of-day utterance; this is a safety net
    /// against a stuck duck, not part of normal operation.
    private static let watchdogSeconds = 15.0

    private let queue = DispatchQueue(label: "com.s4lly.flapjack.ducking", qos: .userInitiated)
    private let state = DuckState()
    private let log = Logger(subsystem: "com.s4lly.flapjack", category: "ducking")

    /// Main-actor mirror of "are the players currently turned down", so that a
    /// re-entrant `duck()` is a no-op and the *original* volumes survive.
    private var isDucked = false
    private var watchdog: Task<Void, Never>?

    init() {
        // A quit mid-utterance would otherwise leave the user's music at a
        // quarter volume with nothing left running to put it back.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreBeforeTerminating() }
        }
    }

    /// Turns down every running, playing, known player.
    ///
    /// Idempotent while ducked: speaking again before the previous utterance
    /// finished must not re-read the (already lowered) volumes and save those as
    /// the originals.
    func duck() {
        guard !isDucked else { return }
        isDucked = true
        startWatchdog()

        let state = self.state
        queue.async { [weak self] in
            let outcome = PlayerScript.duckAll(into: state)
            guard let self else { return }
            Task { @MainActor in self.record(outcome) }
        }
    }

    /// Ramps every ducked player back to the volume it had before `duck()`.
    /// A no-op when nothing is ducked, so the announcer can call it
    /// unconditionally from its delegate callbacks.
    func restore() {
        guard isDucked else { return }
        isDucked = false
        watchdog?.cancel()
        watchdog = nil

        let state = self.state
        queue.async { [weak self] in
            let outcome = PlayerScript.restoreAll(from: state)
            guard let self else { return }
            Task { @MainActor in self.record(outcome) }
        }
    }

    // MARK: - Main-actor bookkeeping

    private func record(_ outcome: DuckOutcome) {
        if outcome.succeeded {
            automationDenied = false
        } else if outcome.deniedConsent {
            automationDenied = true
        }
        if !outcome.summary.isEmpty {
            log.info("\(outcome.summary, privacy: .public)")
        }
    }

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.watchdogSeconds))
            guard !Task.isCancelled, let self, self.isDucked else { return }
            self.log.error("speech never reported finishing — force-restoring volumes")
            self.restore()
        }
    }

    /// The one place the queue is used synchronously: at termination there is no
    /// later turn to run the restore on. Blocks for the length of one ramp at
    /// worst, which is the price of not stranding the volume.
    private func restoreBeforeTerminating() {
        guard isDucked else { return }
        isDucked = false
        watchdog?.cancel()
        watchdog = nil
        let state = self.state
        queue.sync { _ = PlayerScript.restoreAll(from: state) }
    }
}

// MARK: - Apple Event work (queue-confined, main-actor free)

/// What one duck or restore pass managed to do, reported back to the main actor.
private struct DuckOutcome: Sendable {
    var succeeded = false
    var deniedConsent = false
    var summary = ""
}

/// The volumes to hand back, remembered between the duck pass and the restore
/// pass.
///
/// Unchecked `Sendable` because its safety comes from confinement rather than
/// from the type: every read and write happens on `AudioDucker.queue`, which is
/// serial, so the passes are strictly ordered and never overlap.
private final class DuckState: @unchecked Sendable {
    var saved: [DuckablePlayer: Int] = [:]
}

/// An AppleScript error, carried by its error number — the only part that means
/// anything here, since `-1743` is the difference between "the user denied us"
/// and "something else went wrong".
private struct ScriptError: Error {
    let code: Int

    /// `errAEEventNotPermitted` — the user said no in the Automation prompt, or
    /// unchecked us later in Privacy & Security.
    static let notPermitted = -1743
    /// `procNotFound` — the target quit between our running-check and the send.
    static let processNotFound = -600
}

/// The Apple Event side of ducking, deliberately outside `AudioDucker`'s
/// main-actor isolation: every function here runs on the script queue.
private enum PlayerScript {

    /// Fraction of its own volume a ducked player is taken down to. A quarter is
    /// audibly out of the way while still leaving the music present — the point
    /// is to speak over it, not to pause it.
    private static let duckFraction = 0.25
    private static let rampSteps = 4
    private static let rampStepSeconds = 0.075
    /// Read-back-and-correct passes after a restore, and how long to let the
    /// player catch up before each one. Two rounds because the first correction
    /// deserves confirming; both happen on the script queue after the speech has
    /// already finished, so the delay costs the user nothing.
    private static let settleRounds = 2
    private static let settlePauseSeconds = 0.25

    static func duckAll(into state: DuckState) -> DuckOutcome {
        state.saved.removeAll()

        var outcome = DuckOutcome()
        var targets: [(player: DuckablePlayer, original: Int)] = []

        for player in AudioDucker.players where isRunning(player) {
            switch runScript(readingSource(for: player)) {
            case .success(let text):
                outcome.succeeded = true
                // Silent or not playing: nothing to duck, and nudging the
                // volume of a paused player would just be meddling.
                guard let reading = PlayerReading(text), reading.isPlaying, reading.volume > 0 else { continue }
                state.saved[player] = reading.volume
                targets.append((player, reading.volume))
            case .failure(let error):
                note(error, for: player, in: &outcome)
            }
        }

        guard !targets.isEmpty else { return outcome }

        // Stepped together rather than one player at a time, so two players
        // ducking at once fade in parallel instead of in series.
        for step in 1...rampSteps {
            for target in targets {
                let end = duckedVolume(for: target.original)
                let value = target.original + (end - target.original) * step / rampSteps
                _ = setVolume(value, for: target.player)
            }
            if step < rampSteps { Thread.sleep(forTimeInterval: rampStepSeconds) }
        }

        outcome.summary = "ducked " + targets
            .map { "\($0.player.scriptName) \($0.original)→\(duckedVolume(for: $0.original))" }
            .joined(separator: ", ")
        return outcome
    }

    static func restoreAll(from state: DuckState) -> DuckOutcome {
        let saved = state.saved
        state.saved.removeAll()
        guard !saved.isEmpty else { return DuckOutcome() }

        var outcome = DuckOutcome()
        // A player that quit while we were speaking is dropped here rather than
        // erroring: sending to it would relaunch it, which is the one thing this
        // object must never do.
        let live = saved.filter { isRunning($0.key) }
        guard !live.isEmpty else {
            outcome.summary = "nothing to restore — players quit during speech"
            return outcome
        }

        for step in 1...rampSteps {
            for (player, original) in live {
                let start = duckedVolume(for: original)
                let value = start + (original - start) * step / rampSteps
                switch setVolume(value, for: player) {
                case .success: outcome.succeeded = true
                case .failure(let error): note(error, for: player, in: &outcome)
                }
            }
            if step < rampSteps { Thread.sleep(forTimeInterval: rampStepSeconds) }
        }

        for (player, original) in live { settle(player, to: original) }

        outcome.summary = "restored " + live.map { "\($0.key.scriptName) \($0.value)" }.joined(separator: ", ")
        return outcome
    }

    /// Reads the player back and, if it didn't land on the saved number,
    /// corrects it with one more send.
    ///
    /// This is not belt-and-braces, it is load-bearing. Spotify quantises the
    /// volume it is given and reads back a point *lower* than the number that
    /// was set — measured: `set 69` reads 68, while `set 70` reads 69. Handing
    /// back the saved value literally would therefore walk the user's volume
    /// down by one on every single announcement, which on an hourly cadence
    /// fades their music out over a day. Aiming the correction by the observed
    /// error lands it exactly, in one extra round trip.
    ///
    /// Corrections larger than a couple of points are left alone: that is not
    /// rounding, that is the user having reached for their own volume control
    /// while we were speaking, and their number wins.
    private static func settle(_ player: DuckablePlayer, to original: Int) {
        for _ in 1...settleRounds {
            // The pause is not politeness, it is correctness. Asked for its
            // volume the instant after being set, Spotify still answers with the
            // *previous* ramp step — measured, and it is what made an
            // uncorrected 68 survive a working correction step: the error came
            // out as 13 rather than 1, over the sanity bound below, so the
            // correction declined to fire. Reading a settled player instead
            // makes the error the real one.
            Thread.sleep(forTimeInterval: settlePauseSeconds)
            guard case .success(let text) = runScript(readingSource(for: player)),
                  let reading = PlayerReading(text) else { return }
            let error = original - reading.volume
            if error == 0 { return }
            guard abs(error) <= 2 else { return }
            _ = setVolume(min(100, max(0, original + error)), for: player)
        }
    }

    private static func note(_ error: ScriptError, for player: DuckablePlayer, in outcome: inout DuckOutcome) {
        switch error.code {
        case ScriptError.notPermitted:
            outcome.deniedConsent = true
            outcome.summary = "\(player.scriptName) refused: automation permission not granted"
        case ScriptError.processNotFound:
            break   // quit under us; expected, and handled by simply skipping it
        default:
            outcome.summary = "\(player.scriptName) script error \(error.code)"
        }
    }

    private static func duckedVolume(for original: Int) -> Int {
        // Floored at 1 rather than 0: a player sitting at literal zero is
        // indistinguishable from muted, and 1 still restores cleanly.
        max(1, Int((Double(original) * duckFraction).rounded()))
    }

    private static func isRunning(_ player: DuckablePlayer) -> Bool {
        // `NSRunningApplication` is documented thread-safe, which is what lets
        // the check live on the script queue right next to the send it guards.
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }

    /// Volume and playing-ness in one round trip, since two sends would double
    /// the Apple Event cost for no benefit. `player state is playing` is written
    /// against the enumerator rather than coerced to text because Spotify and
    /// Music spell their state values differently but share the enumerator name.
    private static func readingSource(for player: DuckablePlayer) -> String {
        """
        tell application "\(player.scriptName)"
            set v to sound volume
            if player state is playing then
                return "playing " & v
            else
                return "other " & v
            end if
        end tell
        """
    }

    private static func setVolume(_ volume: Int, for player: DuckablePlayer) -> Result<String, ScriptError> {
        runScript("tell application \"\(player.scriptName)\" to set sound volume to \(volume)")
    }

    /// Runs a script in-process. `NSAppleScript` rather than shelling out to
    /// `osascript`: no process spawn per step, and the error number comes back
    /// structured instead of having to be parsed out of stderr.
    private static func runScript(_ source: String) -> Result<String, ScriptError> {
        guard let script = NSAppleScript(source: source) else { return .failure(ScriptError(code: 0)) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return .failure(ScriptError(code: error[NSAppleScript.errorNumber] as? Int ?? 0))
        }
        return .success(result.stringValue ?? "")
    }
}

/// One player's answer to `readingSource`, e.g. `"playing 70"`.
private struct PlayerReading {
    let isPlaying: Bool
    let volume: Int

    init?(_ text: String) {
        let parts = text.split(separator: " ")
        guard parts.count == 2, let volume = Int(parts[1]) else { return nil }
        self.isPlaying = parts[0] == "playing"
        self.volume = volume
    }
}
