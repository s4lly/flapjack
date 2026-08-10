import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var engine: ClockEngine
    @EnvironmentObject private var windows: WindowController
    @EnvironmentObject private var events: EventsService

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // The panel claims its space first; whatever is left is handed to
            // the face, which sizes its own slim margin from that. With the
            // panel off the face gets the whole window, exactly as before.
            GeometryReader { geo in
                switch settings.eventsPlacement {
                case .off:
                    face
                case .column:
                    let width = EventsPanelMetrics.columnWidth(inWindowWidth: geo.size.width)
                    HStack(spacing: 0) {
                        face.frame(width: max(0, geo.size.width - width))
                        EventsColumn(state: panelState, width: width, now: engine.now)
                    }
                case .below:
                    let height = EventsPanelMetrics.stripHeight(inWindowHeight: geo.size.height)
                    VStack(spacing: 0) {
                        face.frame(height: max(0, geo.size.height - height))
                        EventsStrip(state: panelState, height: height, now: engine.now)
                    }
                }
            }

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

    private var face: some View {
        ClockFaceView(face: ClockFace(date: engine.now))
    }

    private var panelState: EventsPanelState {
        EventsPanelState(authorization: events.authorization, events: events.todaysEvents)
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
