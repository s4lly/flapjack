import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var engine: ClockEngine
    @EnvironmentObject private var windows: WindowController
    @EnvironmentObject private var events: EventsService

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
        .onChange(of: settings.alwaysOnTop) { _, on in
            windows.setFloating(on)
        }
    }

    private func columnWidth(in size: CGSize) -> CGFloat {
        EventsPanelMetrics.columnWidth(inWindowWidth: size.width,
                                       fraction: settings.eventsFraction(for: .column))
    }

    private func stripHeight(in size: CGSize) -> CGFloat {
        EventsPanelMetrics.stripHeight(inWindowHeight: size.height,
                                        fraction: settings.eventsFraction(for: .below))
    }

    /// The face, over the cadence countdown backdrop. The backdrop is a sibling
    /// inside the face's own region, so it never spills onto the events panel or
    /// the divider — whatever space the face is handed is exactly what it fills.
    private var face: some View {
        ZStack {
            if showsCadenceFill {
                CadenceFillView(schedule: settings.cadenceSchedule)
            }
            if StackProtoFlag.isEnabled {   // PROTOTYPE — see StackedFacePrototype.swift
                StackedFacePrototypeView(face: ClockFace(date: engine.now))
            } else {
                ClockFaceView(face: ClockFace(date: engine.now))
            }
        }
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
