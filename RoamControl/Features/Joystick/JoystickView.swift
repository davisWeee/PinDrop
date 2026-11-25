import SwiftUI

/// Draggable virtual stick. Reports a vector in -1...1 per axis (screen orientation) and
/// springs back to centre on release.
struct JoystickPad: View {
    var size: CGFloat = 150
    var isEnabled: Bool
    var onChange: (CGVector) -> Void

    @State private var offset: CGSize = .zero

    private let knobDiameter: CGFloat = 58

    var body: some View {
        let travel = (size - knobDiameter) / 2

        ZStack {
            Circle()
                .fill(.thinMaterial)
            Circle()
                .strokeBorder(.primary.opacity(0.18), lineWidth: 1.5)
            Image(systemName: "chevron.up").offset(y: -size / 2 + 14)
            Image(systemName: "chevron.down").offset(y: size / 2 - 14)
            Image(systemName: "chevron.left").offset(x: -size / 2 + 14)
            Image(systemName: "chevron.right").offset(x: size / 2 - 14)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .frame(width: size, height: size)
        .overlay {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .frame(width: knobDiameter, height: knobDiameter)
                .offset(offset)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    var dx = value.location.x - size / 2
                    var dy = value.location.y - size / 2
                    let distance = hypot(dx, dy)
                    if distance > travel {
                        dx *= travel / distance
                        dy *= travel / distance
                    }
                    offset = CGSize(width: dx, height: dy)
                    onChange(CGVector(dx: dx / travel, dy: dy / travel))
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        offset = .zero
                    }
                    onChange(.zero)
                }
        )
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
        // The stick geometry is physical; never mirror it for right-to-left languages.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel("Joystick")
        .accessibilityHint("Drag to move the simulated location")
    }
}

/// Bottom card shown while joystick mode is open.
struct JoystickPanel: View {
    let controller: JoystickController
    let startName: String?
    let isPaired: Bool
    let onStick: (CGVector) -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Joystick", systemImage: "gamecontroller.fill")
                    .font(.headline)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(controller.isEngaged)
                .accessibilityLabel("Close joystick")
            }

            Picker("Movement mode", selection: modeBinding) {
                ForEach(JoystickSpeedMode.allCases) { mode in
                    Label {
                        modeTitle(mode)
                    } icon: {
                        Image(systemName: mode.systemImage)
                    }
                    .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 16) {
                JoystickPad(isEnabled: controller.phase == .active, onChange: onStick)

                VStack(alignment: .leading, spacing: 8) {
                    statusView

                    Toggle("Follow on map", isOn: followBinding)
                        .font(.subheadline)

                    actionButton
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    @ViewBuilder
    private var statusView: some View {
        switch controller.phase {
        case .idle:
            if !isPaired {
                Text("Pair this iPhone before using the joystick.")
                    .foregroundStyle(.secondary)
            } else if let startName {
                Text("Starts at \(startName)")
                    .foregroundStyle(.secondary)
            } else {
                Text("Choose a starting point on the map.")
                    .foregroundStyle(.secondary)
            }
        case .preparing:
            Text("Connecting…")
                .foregroundStyle(.secondary)
        case .active:
            VStack(alignment: .leading, spacing: 2) {
                Text("Speed: \(speedText) km/h")
                Text("Heading: \(headingText)°")
                if let coordinate = controller.currentCoordinate {
                    Text(verbatim: String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
        case .stopping:
            Text("Stopping…")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch controller.phase {
        case .idle, .failed:
            Button(action: onStart) {
                Label("Start", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isPaired || startName == nil)
        case .preparing, .active:
            Button(role: .destructive, action: onStop) {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        case .stopping:
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func modeTitle(_ mode: JoystickSpeedMode) -> some View {
        switch mode {
        case .walk: Text("Walk")
        case .run: Text("Run")
        case .cycle: Text("Cycle")
        case .drive: Text("Drive")
        }
    }

    private var modeBinding: Binding<JoystickSpeedMode> {
        Binding(get: { controller.mode }, set: { controller.setMode($0) })
    }

    private var followBinding: Binding<Bool> {
        Binding(get: { controller.followsPosition }, set: { controller.followsPosition = $0 })
    }

    private var speedText: String {
        String(format: "%.1f", controller.currentSpeed * 3.6)
    }

    private var headingText: String {
        String(Int(controller.heading.rounded()) % 360)
    }
}

/// Map marker for the joystick-controlled position, rotated to the travel heading.
struct JoystickMapMarker: View {
    let heading: Double
    let mapHeading: Double

    var body: some View {
        Image(systemName: "location.north.circle.fill")
            .font(.title.weight(.semibold))
            .foregroundStyle(.white, .indigo)
            .rotationEffect(.degrees(heading - mapHeading))
            .padding(4)
            .background(.regularMaterial, in: Circle())
            .shadow(color: .black.opacity(0.22), radius: 7, y: 3)
    }
}
