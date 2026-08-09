import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var engine: ClockEngine
    @EnvironmentObject private var windows: WindowController

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ClockFaceView(face: ClockFace(date: engine.now))
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

            if settings.alwaysOnTop {
                pinIndicator
            }

            WindowAccessor { window in
                windows.configure(window)
                windows.setFloating(settings.alwaysOnTop)
            }
            .frame(width: 0, height: 0)
        }
        .frame(minWidth: 280, minHeight: 130)
        .onChange(of: settings.alwaysOnTop) { _, on in
            windows.setFloating(on)
        }
    }

    private var pinIndicator: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: "pin.fill")
                    .rotationEffect(.degrees(45))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(white: 0.62))
                    .padding(8)
                    .help("Always on top (⌘1)")
                    .accessibilityLabel("Always on top")
            }
            Spacer()
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
