import Foundation

struct SessionRecoveryRecord: Codable, Equatable {
    enum Kind: String, Codable {
        case fixedLocation
        case walkingRoute
    }

    var kind: Kind
    var lastReportedLocation: LocationTarget
    var destination: LocationTarget?
    var walkingPaceMetresPerSecond: Double?
    /// Raw `RouteTravelMode`; nil in records written before driving/cycling existed.
    var travelModeRawValue: String?
    let startedAt: Date
    var updatedAt: Date

    var travelMode: RouteTravelMode {
        travelModeRawValue.flatMap(RouteTravelMode.init(rawValue:)) ?? .walking
    }

    var isWalkingRoute: Bool {
        kind == .walkingRoute && destination != nil
    }

    static func fixed(at target: LocationTarget) -> SessionRecoveryRecord {
        SessionRecoveryRecord(
            kind: .fixedLocation,
            lastReportedLocation: target,
            destination: nil,
            walkingPaceMetresPerSecond: nil,
            travelModeRawValue: nil,
            startedAt: .now,
            updatedAt: .now
        )
    }

    static func walking(
        from start: LocationTarget,
        to destination: LocationTarget,
        paceMetresPerSecond: Double,
        mode: RouteTravelMode = .walking
    ) -> SessionRecoveryRecord {
        SessionRecoveryRecord(
            kind: .walkingRoute,
            lastReportedLocation: start,
            destination: destination,
            walkingPaceMetresPerSecond: paceMetresPerSecond,
            travelModeRawValue: mode.rawValue,
            startedAt: .now,
            updatedAt: .now
        )
    }
}
