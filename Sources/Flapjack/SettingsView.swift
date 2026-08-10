import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

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

            // No explicit Divider: the grouped form already rules between rows,
            // and a manual one renders as a stray empty row beside them.
            Toggle("Always on top (⌘1)", isOn: Binding(
                get: { settings.alwaysOnTop },
                set: { settings.setAlwaysOnTop($0) }
            ))

            Text("Tip: install an enhanced voice in System Settings → Accessibility → Spoken Content for much better audio.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}
