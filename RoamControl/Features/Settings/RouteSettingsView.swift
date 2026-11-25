import SwiftUI

/// Units (km/mi, km/h/mph) and per-mode custom speeds for route simulation.
struct RouteSettingsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let preferences = RoutePreferences.shared

    var body: some View {
        Form {
            Section {
                Picker("Distance", selection: distanceBinding) {
                    ForEach(DistanceUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }

                Picker("Speed", selection: speedUnitBinding) {
                    ForEach(SpeedUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
            } header: {
                Text("Units")
            } footer: {
                Text("Automatic follows your region: miles and mph in the US and UK, kilometres and km/h elsewhere.")
            }

            Section {
                ForEach(RouteTravelMode.allCases) { mode in
                    speedRow(for: mode)
                }
            } header: {
                Text("Travel speeds")
            } footer: {
                Text("Speed used when a route starts. You can still change it for a single trip before pressing Start.")
            }
        }
        .navigationTitle("Speeds & Units")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func speedRow(for mode: RouteTravelMode) -> some View {
        let factor = preferences.displaySpeedFactor
        let range = mode.speedRangeMetresPerSecond
        let current = preferences.speedMetresPerSecond(for: mode)

        return VStack(alignment: .leading, spacing: 6) {
            Stepper(
                value: Binding(
                    get: { preferences.speedMetresPerSecond(for: mode) * factor },
                    set: { preferences.setSpeed($0 / factor, for: mode) }
                ),
                in: (range.lowerBound * factor)...(range.upperBound * factor),
                step: mode.speedStep
            ) {
                HStack {
                    Label(mode.title, systemImage: mode.symbol)
                    Spacer(minLength: 8)
                    Text(RouteFormat.speed(current))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityLabel("\(mode.title) speed")
            .accessibilityValue(RouteFormat.speed(current))

            if preferences.hasCustomSpeed(for: mode) {
                Button("Reset to \(RouteFormat.speed(mode.defaultSpeedMetresPerSecond))") {
                    preferences.resetSpeed(for: mode)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private var distanceBinding: Binding<DistanceUnit> {
        Binding(
            get: { preferences.distanceUnit },
            set: { preferences.setDistanceUnit($0) }
        )
    }

    private var speedUnitBinding: Binding<SpeedUnit> {
        Binding(
            get: { preferences.speedUnit },
            set: { preferences.setSpeedUnit($0) }
        )
    }
}

#Preview {
    NavigationStack { RouteSettingsView() }
}
