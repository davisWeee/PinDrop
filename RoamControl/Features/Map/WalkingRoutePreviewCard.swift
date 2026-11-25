import MapKit
import SwiftUI

struct WalkingRoutePreviewCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let route: MKRoute
    let destination: LocationTarget
    let simulation: WalkingSimulationController
    let isPaired: Bool
    let isApproximated: Bool
    let onChangeMode: (RouteTravelMode) -> Void
    let onStart: () -> Void
    let onTogglePause: () -> Void
    let onWalkBack: () -> Void
    let onChooseNewLocation: () -> Void
    let onStop: () -> Void
    let onDone: () -> Void

    @State private var isConfirmingStop = false

    private var mode: RouteTravelMode { simulation.mode }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.vertical, showsIndicators: false) {
                    cardContent
                }
                .frame(maxHeight: 460)
            } else {
                cardContent
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 18, y: 8)
        .confirmationDialog(
            "Stop \(mode.lowercasedTitle) and restore your real location?",
            isPresented: $isConfirmingStop,
            titleVisibility: .visible
        ) {
            Button("Stop & Restore", role: .destructive, action: onStop)
            Button("Keep \(mode.title)", role: .cancel) {}
        } message: {
            Text("Your route progress will be reset.")
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: phaseSymbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(phaseColour)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: phaseTitle)
                        .font(.headline)

                    Text(phaseSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                }

                Spacer(minLength: 0)

                if canClose {
                    Button(action: onDone) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close \(mode.lowercasedTitle) route")
                }
            }

            if showsProgress {
                ProgressView(value: simulation.progress)
                    .tint(simulation.phase == .arrived ? .green : .blue)
            }

            routeMetrics

            if canChoosePace {
                modePicker
                speedStepper
            }

            controls
            footer
        }
    }

    @ViewBuilder
    private var modePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Travel mode", selection: modeBinding) {
                ForEach(RouteTravelMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.menu)
        } else {
            Picker("Travel mode", selection: modeBinding) {
                ForEach(RouteTravelMode.allCases) { mode in
                    Label(mode.shortTitle, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var speedStepper: some View {
        let factor = RoutePreferences.shared.displaySpeedFactor
        let range = mode.speedRangeMetresPerSecond
        return Stepper(
            value: Binding(
                get: { simulation.speed * factor },
                set: { simulation.speed = RoutePreferences.clamp($0 / factor, for: mode) }
            ),
            in: (range.lowerBound * factor)...(range.upperBound * factor),
            step: mode.speedStep
        ) {
            HStack {
                Label("Speed", systemImage: "speedometer")
                    .font(.subheadline)
                Spacer(minLength: 8)
                Text(RouteFormat.speed(simulation.speed))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel("\(mode.title) speed")
        .accessibilityValue(RouteFormat.speed(simulation.speed))
    }

    @ViewBuilder
    private var routeMetrics: some View {
        let distance = RouteMetric(
            title: L10n.tr(showsProgress ? "Remaining" : "Distance"),
            value: distanceText,
            symbol: "point.topleft.down.to.point.bottomright.curvepath"
        )
        let duration = RouteMetric(
            title: simulation.phase == .arrived ? "Status" : mode.title,
            value: durationText,
            symbol: simulation.phase == .arrived ? "checkmark.circle" : "clock"
        )
        let arrival = RouteMetric(
            title: L10n.tr("Arrive"),
            value: arrivalText,
            symbol: "flag.checkered"
        )

        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                distance
                duration
                arrival
            }
        } else {
            HStack(spacing: 10) {
                distance
                duration
                arrival
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch simulation.phase {
        case .idle:
            Button(action: onStart) {
                Label("Start \(mode.title)", systemImage: mode.startSymbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isPaired)

        case .preparing:
            HStack(spacing: 10) {
                ProgressView()
                Text("Starting \(mode.lowercasedTitle) session…")
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)

        case .walking, .paused:
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) {
                        pauseButton
                        stopWalkingButton(showTitle: true)
                    }
                } else {
                    HStack(spacing: 10) {
                        pauseButton
                        stopWalkingButton(showTitle: false)
                    }
                }
            }

        case .arrived:
            Button(action: onWalkBack) {
                Label("\(mode.shortTitle) Route Back", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) {
                        newLocationButton
                        stopAtArrivalButton(showTitle: true)
                    }
                } else {
                    HStack(spacing: 10) {
                        newLocationButton
                        stopAtArrivalButton(showTitle: false)
                    }
                }
            }

        case .stopping:
            HStack(spacing: 10) {
                ProgressView()
                Text("Restoring real location…")
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)

        case .failed:
            Button(action: onStart) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isPaired)
        }
    }

    private var pauseButton: some View {
                Button(action: onTogglePause) {
                    Label(
                        simulation.phase == .paused ? LocalizedStringKey("Resume") : LocalizedStringKey("Pause"),
                        systemImage: simulation.phase == .paused ? "play.fill" : "pause.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
    }

    @ViewBuilder
    private func stopWalkingButton(showTitle: Bool) -> some View {
                Button(role: .destructive) {
                    isConfirmingStop = true
                } label: {
            if showTitle {
                Label("Stop & Restore", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            } else {
                Image(systemName: "stop.fill")
                    .frame(width: 28)
            }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Stop \(mode.lowercasedTitle) and restore real location")
    }

    private var newLocationButton: some View {
        Button(action: onChooseNewLocation) {
            Label("New Location", systemImage: "mappin.and.ellipse")
                    .frame(maxWidth: .infinity)
            }
        .buttonStyle(.bordered)
            .controlSize(.large)
    }

    @ViewBuilder
    private func stopAtArrivalButton(showTitle: Bool) -> some View {
                Button(role: .destructive) {
                    isConfirmingStop = true
                } label: {
            if showTitle {
                Label("Stop & Restore", systemImage: "location.slash.fill")
                    .frame(maxWidth: .infinity)
            } else {
                Image(systemName: "location.slash.fill")
                    .frame(width: 28)
            }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Stop and restore real location")
    }

    @ViewBuilder
    private var footer: some View {
        switch simulation.phase {
        case .idle:
            Text(isPaired
                 ? (isApproximated
                    ? "Cycling directions aren't available here, so your location follows the walking path at cycling speed."
                    : "Your location will move along this route at the selected speed.")
                 : "Pair this iPhone before starting a \(mode.lowercasedTitle) session.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)

        case .preparing:
            Text("Follow the mobile-data guidance if it appears.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)

        case .walking:
            Text("Keep PinDrop running. You can use other apps while the trip continues.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)

        case .paused:
            Text("Your spoofed location is being held here until you resume.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)

        case .arrived:
            Text("The destination remains active until you stop and restore your real location.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)

        case .stopping:
            EmptyView()

        case .failed(let message):
            Text(message.localizedMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var canClose: Bool {
        switch simulation.phase {
        case .idle, .failed:
            true
        case .preparing, .walking, .paused, .arrived, .stopping:
            false
        }
    }

    private var canChoosePace: Bool {
        switch simulation.phase {
        case .idle, .failed:
            true
        case .preparing, .walking, .paused, .arrived, .stopping:
            false
        }
    }

    private var showsProgress: Bool {
        switch simulation.phase {
        case .walking, .paused, .arrived:
            true
        case .idle, .preparing, .stopping, .failed:
            false
        }
    }

    private var phaseTitle: String {
        switch simulation.phase {
        case .idle: L10n.tr("\(mode.title) route")
        case .preparing: L10n.tr("Preparing \(mode.lowercasedTitle)")
        case .walking: mode.title
        case .paused: L10n.tr("\(mode.title) paused")
        case .arrived: L10n.tr("Arrived")
        case .stopping: L10n.tr("Ending \(mode.lowercasedTitle)")
        case .failed: L10n.tr("\(mode.title) unavailable")
        }
    }

    private var phaseSubtitle: String {
        switch simulation.phase {
        case .idle, .preparing, .failed:
            L10n.tr("Current Location to \(destination.name)")
        case .walking, .paused:
            L10n.tr("Heading to \(destination.name) · \(Int((simulation.progress * 100).rounded()))%")
        case .arrived:
            L10n.tr("Location active at \(destination.name)")
        case .stopping:
            L10n.tr("Restoring this iPhone's real location")
        }
    }

    private var phaseSymbol: String {
        switch simulation.phase {
        case .idle, .preparing, .walking: mode.symbol
        case .paused: "pause.circle.fill"
        case .arrived: "checkmark.circle.fill"
        case .stopping: "location.slash.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var phaseColour: Color {
        switch simulation.phase {
        case .arrived: .green
        case .failed: .red
        case .idle, .preparing, .walking, .paused, .stopping: .blue
        }
    }

    private var modeBinding: Binding<RouteTravelMode> {
        Binding(
            get: { mode },
            set: { newMode in
                guard newMode != mode else { return }
                onChangeMode(newMode)
            }
        )
    }

    /// Distance along the simulated path (more precise than `route.distance`).
    private var distanceText: String {
        if showsProgress { return RouteFormat.distance(simulation.remainingDistance) }
        return RouteFormat.distance(
            simulation.totalDistance > 0 ? simulation.totalDistance : route.distance
        )
    }

    /// ETA from the chosen speed over the remaining path.
    private var remainingSeconds: TimeInterval {
        simulation.totalDistance > 0 ? simulation.remainingDuration : route.expectedTravelTime
    }

    private var durationText: String {
        guard simulation.phase != .arrived else { return "Complete" }
        return RouteFormat.duration(remainingSeconds)
    }

    private var arrivalText: String {
        guard simulation.phase != .arrived else { return "Now" }
        return RouteFormat.arrival(after: remainingSeconds)
    }
}

private struct RouteMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }
}
