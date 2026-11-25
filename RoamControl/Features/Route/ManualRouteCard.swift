import CoreLocation
import SwiftUI

/// Bottom card for the manual route workflow: editing (tap / freehand) and the
/// prepared-route preview with simulation controls.
struct ManualRouteCard: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let builder: ManualRouteBuilder
    let simulation: WalkingSimulationController
    let isPaired: Bool

    @State private var isConfirmingStop = false

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.vertical, showsIndicators: false) { content }
                    .frame(maxHeight: 460)
            } else {
                content
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 18, y: 8)
        .confirmationDialog(
            "Stop and restore your real location?",
            isPresented: $isConfirmingStop,
            titleVisibility: .visible
        ) {
            Button("Stop & Restore", role: .destructive) {
                simulation.stop(using: appModel.deviceSession)
            }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Your route progress will be reset.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if builder.isEditing {
            editor
        } else if let route = builder.prepared {
            preview(route)
        }
    }

    // MARK: Editing

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "pencil.and.scribble")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Draw a route")
                        .font(.headline)
                    Text(editorHint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    builder.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel route drawing")
            }

            Picker("Drawing mode", selection: Binding(get: { builder.mode }, set: { builder.mode = $0 })) {
                Text("Tap points").tag(ManualRouteBuilder.Mode.tap)
                Text("Freehand").tag(ManualRouteBuilder.Mode.freehand)
            }
            .pickerStyle(.segmented)

            metrics(
                distance: builder.distance,
                duration: duration(for: builder.distance),
                third: ("Points", "\(builder.points.count)", "mappin.and.ellipse")
            )

            pacePicker

            HStack(spacing: 10) {
                Button {
                    builder.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!builder.canUndo)

                Button(role: .destructive) {
                    builder.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .disabled(builder.points.isEmpty)

                Button {
                    builder.isShowingImporter = true
                } label: {
                    Label("GPX", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .labelStyle(.titleAndIcon)

            HStack(spacing: 10) {
                Button {
                    builder.finish(simulation: simulation)
                } label: {
                    Label("Preview Route", systemImage: "figure.walk")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(builder.points.count < 2)

                exportButton
                    .disabled(builder.points.count < 2)
            }

            if let message = builder.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var editorHint: String {
        switch builder.mode {
        case .tap:
            L10n.tr("Tap the map to add points. Drag a point to move it.")
        case .freehand:
            L10n.tr("Draw a path with your finger. Switch to Tap points to pan or zoom the map.")
        }
    }

    // MARK: Prepared route

    private func preview(_ route: ManualRoute) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: phaseSymbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(phaseColour)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(phaseTitle)
                        .font(.headline)
                    Text(phaseSubtitle(route))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if canEdit {
                    Button {
                        builder.discard(simulation: simulation)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close route")
                }
            }

            if showsProgress {
                ProgressView(value: simulation.progress)
                    .tint(simulation.phase == .arrived ? .green : .blue)
            }

            metrics(
                distance: showsProgress ? simulation.remainingDistance : simulation.totalDistance,
                duration: simulation.phase == .arrived ? nil : simulation.remainingDuration,
                third: nil
            )

            if canEdit {
                pacePicker
            }

            controls
            footer
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch simulation.phase {
        case .idle, .failed:
            Button {
                Task { await simulation.start(using: appModel) }
            } label: {
                Label(simulation.phase == .idle ? "Start Route" : "Try Again", systemImage: "figure.walk.motion")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isPaired)

            HStack(spacing: 10) {
                Button {
                    builder.edit(simulation: simulation)
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                exportButton
            }

        case .preparing:
            HStack(spacing: 10) {
                ProgressView()
                Text("Starting location session…")
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)

        case .walking, .paused:
            HStack(spacing: 10) {
                Button {
                    simulation.togglePause()
                } label: {
                    Label(
                        simulation.phase == .paused ? "Resume" : "Pause",
                        systemImage: simulation.phase == .paused ? "play.fill" : "pause.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(role: .destructive) {
                    isConfirmingStop = true
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Stop and restore real location")
            }

        case .arrived:
            Button {
                if simulation.prepareReturnTrip() != nil {
                    builder.reversePrepared()
                }
            } label: {
                Label("Run Route Back", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 10) {
                Button {
                    builder.discard(simulation: simulation)
                    builder.startEditing()
                } label: {
                    Label("New Route", systemImage: "pencil.and.scribble")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(role: .destructive) {
                    isConfirmingStop = true
                } label: {
                    Image(systemName: "location.slash.fill")
                        .frame(width: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Stop and restore real location")
            }

        case .stopping:
            HStack(spacing: 10) {
                ProgressView()
                Text("Restoring real location…")
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch simulation.phase {
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .center)
        case .idle:
            Text(isPaired
                 ? L10n.tr("Your location will move along this route at the selected pace.")
                 : L10n.tr("Pair this iPhone before starting a route."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        case .walking:
            Text("Keep PinDrop running. You can use other apps while the route continues.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        case .paused:
            Text("Your location is held here until you resume.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        case .arrived:
            Text("The end point stays active until you stop and restore your real location.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        case .preparing, .stopping:
            EmptyView()
        }
    }

    // MARK: Shared pieces

    private var exportButton: some View {
        Group {
            if let file = builder.exportFile(metresPerSecond: simulation.speed) {
                ShareLink(
                    item: file,
                    preview: SharePreview(file.name)
                ) {
                    Label("Export GPX", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
            } else {
                Label("Export GPX", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var pacePicker: some View {
        let mode = simulation.mode
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
                Spacer(minLength: 8)
                Text(RouteFormat.speed(simulation.speed)).monospacedDigit()
            }
        }
    }

    private func metrics(
        distance: Double,
        duration: TimeInterval?,
        third: (title: String, value: String, symbol: String)?
    ) -> some View {
        let items: [RouteCardMetric] = {
            var list = [
                RouteCardMetric(
                    title: showsProgress ? "Remaining" : "Distance",
                    value: ManualRouteFormat.distance(distance),
                    symbol: "point.topleft.down.to.point.bottomright.curvepath"
                ),
                RouteCardMetric(
                    title: duration == nil ? "Status" : "Time",
                    value: duration.map(ManualRouteFormat.duration) ?? L10n.tr("Complete"),
                    symbol: duration == nil ? "checkmark.circle" : "clock"
                ),
            ]
            if let third {
                list.append(RouteCardMetric(title: third.title, value: third.value, symbol: third.symbol))
            } else if let duration {
                list.append(RouteCardMetric(
                    title: "Arrive",
                    value: Date.now.addingTimeInterval(duration).formatted(date: .omitted, time: .shortened),
                    symbol: "flag.checkered"
                ))
            }
            return list
        }()

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { ForEach(items) { $0 } }
            } else {
                HStack(spacing: 10) { ForEach(items) { $0 } }
            }
        }
    }

    private func duration(for distance: Double) -> TimeInterval {
        distance / max(simulation.speed, 0.1)
    }

    private var canEdit: Bool {
        switch simulation.phase {
        case .idle, .failed: true
        case .preparing, .walking, .paused, .arrived, .stopping: false
        }
    }

    private var showsProgress: Bool {
        switch simulation.phase {
        case .walking, .paused, .arrived: true
        case .idle, .preparing, .stopping, .failed: false
        }
    }

    private var phaseTitle: String {
        switch simulation.phase {
        case .idle: L10n.tr("Custom route")
        case .preparing: L10n.tr("Preparing route")
        case .walking: L10n.tr("On route")
        case .paused: L10n.tr("Route paused")
        case .arrived: L10n.tr("Route finished")
        case .stopping: L10n.tr("Ending route")
        case .failed: L10n.tr("Route unavailable")
        }
    }

    private func phaseSubtitle(_ route: ManualRoute) -> String {
        switch simulation.phase {
        case .walking, .paused:
            "\(route.name) · \(Int((simulation.progress * 100).rounded()))%"
        case .stopping:
            L10n.tr("Restoring this iPhone's real location")
        case .idle, .preparing, .arrived, .failed:
            route.source == .gpx
                ? L10n.tr("\(route.name) · GPX import")
                : L10n.tr("\(route.name) · drawn")
        }
    }

    private var phaseSymbol: String {
        switch simulation.phase {
        case .idle, .preparing, .walking: "point.topleft.down.to.point.bottomright.curvepath"
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
        case .idle, .preparing, .walking, .paused, .stopping: .orange
        }
    }
}

private struct RouteCardMetric: View, Identifiable {
    let title: String
    let value: String
    let symbol: String

    var id: String { title }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(L10n.lookup(title), systemImage: symbol)
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
        .accessibilityLabel("\(L10n.lookup(title)), \(value)")
    }
}

@MainActor
enum ManualRouteFormat {
    static func distance(_ metres: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = .current
        formatter.unitOptions = .naturalScale
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: Measurement(value: metres, unit: UnitLength.meters))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        guard minutes >= 1 else { return L10n.tr("< 1 min") }
        guard minutes >= 60 else { return L10n.tr("\(minutes) min") }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0
            ? L10n.tr("\(hours) hr")
            : L10n.tr("\(hours) hr \(remainingMinutes) min")
    }
}
