import CoreLocation
import Foundation
import Observation

/// Top speed (at full stick deflection) per movement mode, in metres per second.
enum JoystickSpeedMode: String, CaseIterable, Identifiable {
    case walk
    case run
    case cycle
    case drive

    var id: Self { self }

    var maxMetresPerSecond: Double {
        switch self {
        case .walk: 1.7
        case .run: 3.5
        case .cycle: 6.0
        case .drive: 16.7
        }
    }

    var systemImage: String {
        switch self {
        case .walk: "figure.walk"
        case .run: "figure.run"
        case .cycle: "bicycle"
        case .drive: "car.fill"
        }
    }
}

enum JoystickPhase: Equatable {
    case idle
    case preparing
    case active
    case stopping
    case failed(String)
}

/// Free movement: a virtual stick moves the simulated position continuously.
/// Position updates flow through the same `LocalDeviceSessionCoordinator` pipeline as
/// fixed locations and walking routes (via `AppModel.startLocationSession` / `updateLocation`).
@MainActor
@Observable
final class JoystickController {
    static let tickInterval: Double = 1.0
    static let deadZone: Double = 0.12
    private static let modeKey = "joystickSpeedMode"

    private(set) var phase: JoystickPhase = .idle
    private(set) var currentCoordinate: CLLocationCoordinate2D?
    /// Degrees clockwise from true north.
    private(set) var heading: Double = 0
    private(set) var currentSpeed: Double = 0
    private(set) var distanceTravelled: CLLocationDistance = 0
    /// Increments each time the position changes (drives camera follow).
    private(set) var moveCount = 0
    private(set) var mode: JoystickSpeedMode
    var followsPosition = true

    @ObservationIgnored
    private var deflection: Double = 0
    @ObservationIgnored
    private var bearing: Double = 0
    @ObservationIgnored
    private var movementTask: Task<Void, Never>?
    @ObservationIgnored
    private let preferences: UserDefaults

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        mode = JoystickSpeedMode(rawValue: preferences.string(forKey: Self.modeKey) ?? "") ?? .walk
    }

    var isEngaged: Bool {
        switch phase {
        case .preparing, .active, .stopping: true
        case .idle, .failed: false
        }
    }

    var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    func setMode(_ newMode: JoystickSpeedMode) {
        mode = newMode
        preferences.set(newMode.rawValue, forKey: Self.modeKey)
    }

    /// Feed the stick position. `vector` is in -1...1 per axis, screen orientation (y grows downwards);
    /// "up" on the stick means "up on the map", so `mapHeading` rotates it to a compass bearing.
    func setStick(_ vector: CGVector, mapHeading: Double) {
        let magnitude = min(hypot(vector.dx, vector.dy), 1)
        deflection = magnitude
        guard magnitude > Self.deadZone else { return }
        let stickAngle = atan2(vector.dx, -vector.dy) * 180 / .pi
        bearing = Self.normalised(degrees: mapHeading + stickAngle)
    }

    func start(at origin: CLLocationCoordinate2D, using appModel: AppModel) async {
        guard phase == .idle || isFailed else { return }
        guard case .paired = appModel.pairingStatus else {
            phase = .failed(L10n.tr("Pair this iPhone before using the joystick."))
            return
        }

        movementTask?.cancel()
        currentCoordinate = origin
        distanceTravelled = 0
        currentSpeed = 0
        deflection = 0
        phase = .preparing

        await appModel.startLocationSession(at: target(at: origin))

        if case .idle = appModel.deviceSession.phase, phase == .preparing {
            phase = .failed(L10n.tr("PinDrop could not start the joystick session."))
        }
    }

    func stop(using appModel: AppModel) {
        guard isEngaged || isFailed else { return }
        movementTask?.cancel()
        movementTask = nil
        deflection = 0
        currentSpeed = 0

        if case .idle = appModel.deviceSession.phase {
            reset()
            return
        }

        phase = .stopping
        appModel.stopLocationSession()
    }

    func reset() {
        movementTask?.cancel()
        movementTask = nil
        deflection = 0
        currentSpeed = 0
        currentCoordinate = nil
        distanceTravelled = 0
        phase = .idle
    }

    func handleDeviceSessionPhase(
        _ devicePhase: DeviceSessionPhase,
        deviceSession: LocalDeviceSessionCoordinator
    ) {
        switch devicePhase {
        case .active:
            guard phase == .preparing else { return }
            phase = .active
            beginMovement(using: deviceSession)

        case .stopping:
            guard isEngaged else { return }
            movementTask?.cancel()
            movementTask = nil
            phase = .stopping

        case .idle:
            // Either our own stop finished, or the session ended elsewhere.
            guard phase == .stopping || phase == .active else { return }
            reset()

        case .failed(let message):
            guard isEngaged else { return }
            movementTask?.cancel()
            movementTask = nil
            currentCoordinate = nil
            currentSpeed = 0
            phase = .failed(message)

        case .openingLocalDevVPN, .discovering, .connecting:
            break
        }
    }

    // MARK: - Movement

    private func beginMovement(using deviceSession: LocalDeviceSessionCoordinator) {
        movementTask?.cancel()
        movementTask = Task { @MainActor [weak self, weak deviceSession] in
            var lastTick = Date.now

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.tickInterval))
                guard !Task.isCancelled, let self, let deviceSession else { return }

                let now = Date.now
                let elapsed = min(now.timeIntervalSince(lastTick), 3)
                lastTick = now

                guard self.phase == .active, let origin = self.currentCoordinate else { return }

                let speed = self.effectiveSpeed()
                self.currentSpeed = speed
                var coordinate = origin
                if speed > 0 {
                    let distance = speed * elapsed
                    coordinate = Self.destination(from: origin, bearing: self.bearing, distance: distance)
                    self.currentCoordinate = coordinate
                    self.heading = self.bearing
                    self.distanceTravelled += distance
                    self.moveCount += 1
                }

                guard deviceSession.updateLocation(self.target(at: coordinate)) == .updated else {
                    self.phase = .failed(L10n.tr("The active location session ended unexpectedly."))
                    return
                }
            }
        }
    }

    private func effectiveSpeed() -> Double {
        guard deflection > Self.deadZone else { return 0 }
        let scaled = (deflection - Self.deadZone) / (1 - Self.deadZone)
        return mode.maxMetresPerSecond * min(max(scaled, 0), 1)
    }

    private func target(at coordinate: CLLocationCoordinate2D) -> LocationTarget {
        LocationTarget(
            name: L10n.tr("Joystick location"),
            subtitle: String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    // MARK: - Geodesy (great-circle destination point on a spherical Earth)

    static func destination(
        from origin: CLLocationCoordinate2D,
        bearing bearingDegrees: Double,
        distance: CLLocationDistance
    ) -> CLLocationCoordinate2D {
        let radius = 6_371_008.8
        let angular = distance / radius
        let theta = bearingDegrees * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180

        let sinLat2 = sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(theta)
        let lat2 = asin(min(max(sinLat2, -1), 1))
        let lon2 = lon1 + atan2(
            sin(theta) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sinLat2
        )

        let latitude = min(max(lat2 * 180 / .pi, -85), 85)
        var longitude = lon2 * 180 / .pi
        longitude = (longitude + 540).truncatingRemainder(dividingBy: 360) - 180
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func normalised(degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }
}
