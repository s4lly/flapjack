import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var engine: ClockEngine
    @EnvironmentObject private var windows: WindowController
    @EnvironmentObject private var events: EventsService

    /// The system's light/dark setting, which is what the Auto appearance
    /// follows. Nothing in the app forces an appearance on its own windows, so
    /// this tracks System Settings live and reruns `body` when it flips.
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme {
        settings.appearance.colorway(for: colorScheme).theme
    }

    var body: some View {
        ZStack {
            // Deliberately *without* `.ignoresSafeArea()`. A hidden-title-bar
            // window still keeps a title-bar-height safe area at the top, and a
            // ground painted straight through it covers the window's own
            // background colour — which is the bezel's top run. Held back to the
            // safe area, the strip shows the bezel instead and the frame closes.
            theme.ground.color

            // The countdown is the window's own backdrop rather than a panel in
            // the face's region: one plane draining behind the face, the divider
            // and the events panel alike. It takes the same safe-area treatment
            // as the ground, so the bezel — an overlay that *does* ignore the
            // safe area — still closes over its edges on all four sides.
            if showsCadenceFill {
                CadenceFillView(schedule: settings.cadenceSchedule,
                                isVisible: windows.isVisible)
            }

            // The panel claims its space first; whatever is left (less the
            // divider gutter) is handed to the face, which sizes its own slim
            // margin from that. With the panel off the face gets the whole
            // window, exactly as before. The share comes from the user's stored
            // fraction, which the divider moves live.
            GeometryReader { geo in
                switch settings.eventsPlacement {
                case .off:
                    face
                case .column:
                    let width = columnWidth(in: geo.size)
                    HStack(spacing: 0) {
                        face.frame(width: max(0, geo.size.width - width - EventsPanelMetrics.dividerThickness))
                        SplitDivider(seam: .vertical) {
                            columnWidth(in: geo.size)
                        } onMove: { wanted in
                            settings.setEventsFraction(
                                EventsPanelMetrics.columnFraction(forWidth: wanted,
                                                                  inWindowWidth: geo.size.width),
                                for: .column)
                        }
                        EventsColumn(state: panelState, width: width, now: engine.now)
                    }
                case .below:
                    let height = stripHeight(in: geo.size)
                    VStack(spacing: 0) {
                        face.frame(height: max(0, geo.size.height - height - EventsPanelMetrics.dividerThickness))
                        SplitDivider(seam: .horizontal) {
                            stripHeight(in: geo.size)
                        } onMove: { wanted in
                            settings.setEventsFraction(
                                EventsPanelMetrics.stripFraction(forHeight: wanted,
                                                                 inWindowHeight: geo.size.height),
                                for: .below)
                        }
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
        .environment(\.theme, theme)
        .overlay(WindowBezel(color: theme.bezel))
        .onChange(of: settings.alwaysOnTop) { _, on in
            windows.setFloating(on)
        }
        // The window's background colour is the bezel's top run, and it lives in
        // AppKit rather than in the view tree — so it has to be pushed, both at
        // launch and whenever the resolved colourway changes (the user picking
        // another appearance, or the system flipping light/dark under Auto).
        .onAppear { windows.setChrome(NSColor(theme.bezel)) }
        .onChange(of: theme) { _, new in windows.setChrome(NSColor(new.bezel)) }
    }

    private func columnWidth(in size: CGSize) -> CGFloat {
        EventsPanelMetrics.columnWidth(inWindowWidth: size.width,
                                       fraction: settings.eventsFraction(for: .column))
    }

    private func stripHeight(in size: CGSize) -> CGFloat {
        EventsPanelMetrics.stripHeight(inWindowHeight: size.height,
                                        fraction: settings.eventsFraction(for: .below))
    }

    /// Just the clock. The countdown lives at the window root above, since it is
    /// the window's backdrop rather than the face's.
    private var face: some View {
        ClockFaceView(face: ClockFace(date: engine.now))
    }

    /// Nothing to count down to with the cadence off, and the user can switch
    /// the backdrop off outright.
    private var showsCadenceFill: Bool {
        settings.showCadenceFill && settings.announceMode != .off
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
                    .foregroundStyle(theme.accent)
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
