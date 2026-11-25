import Foundation
import Observation

enum DistanceUnit: String, CaseIterable, Identifiable {
    case automatic
    case kilometres
    case miles

    var id: Self { self }

    @MainActor var title: String {
        switch self {
        case .automatic: L10n.tr("Automatic")
        case .kilometres: L10n.tr("Kilometres")
        case .miles: L10n.tr("Miles")
        }
    }
}

enum SpeedUnit: String, CaseIterable, Identifiable {
    case automatic
    case kilometresPerHour
    case milesPerHour

    var id: Self { self }

    @MainActor var title: String {
        switch self {
        case .automatic: L10n.tr("Automatic")
        case .kilometresPerHour: "km/h"
        case .milesPerHour: "mph"
        }
    }
}

/// Route-related user preferences (units and per-mode custom speeds),
/// persisted in `UserDefaults`.
///
/// Kept separate from `AppModel` so route features can read it from anywhere;
/// being `@Observable`, SwiftUI views refresh when a value changes.
@MainActor
@Observable
final class RoutePreferences {
    static let shared = RoutePreferences()

    private static let distanceUnitKey = "routeDistanceUnit"
    private static let speedUnitKey = "routeSpeedUnit"
    private static func speedKey(_ mode: RouteTravelMode) -> String {
        "routeCustomSpeedMetresPerSecond.\(mode.rawValue)"
    }

    static let metresPerMile = 1_609.344
    static let kilometresPerHourPerMetrePerSecond = 3.6
    static let milesPerHourPerMetrePerSecond = 2.236_936_292_054_4

    @ObservationIgnored
    private let defaults: UserDefaults

    private(set) var distanceUnit: DistanceUnit
    private(set) var speedUnit: SpeedUnit
    private var customSpeeds: [RouteTravelMode: Double]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.distanceUnit = .automatic
        self.speedUnit = .automatic
        self.customSpeeds = [:]
        reload()
    }

    /// Re-reads everything from `UserDefaults` (used after "Reset PinDrop").
    func reload() {
        distanceUnit = DistanceUnit(rawValue: defaults.string(forKey: Self.distanceUnitKey) ?? "") ?? .automatic
        speedUnit = SpeedUnit(rawValue: defaults.string(forKey: Self.speedUnitKey) ?? "") ?? .automatic
        var speeds: [RouteTravelMode: Double] = [:]
        for mode in RouteTravelMode.allCases {
            let value = defaults.double(forKey: Self.speedKey(mode))
            if value > 0 {
                speeds[mode] = Self.clamp(value, for: mode)
            }
        }
        customSpeeds = speeds
    }

    // MARK: Units

    var usesImperialByLocale: Bool {
        switch Locale.current.measurementSystem {
        case .us, .uk: true
        default: false
        }
    }

    /// Distance unit with `.automatic` resolved from the locale.
    var resolvedDistanceUnit: DistanceUnit {
        switch distanceUnit {
        case .automatic: usesImperialByLocale ? .miles : .kilometres
        case .kilometres, .miles: distanceUnit
        }
    }

    /// Speed unit with `.automatic` resolved from the locale.
    var resolvedSpeedUnit: SpeedUnit {
        switch speedUnit {
        case .automatic: usesImperialByLocale ? .milesPerHour : .kilometresPerHour
        case .kilometresPerHour, .milesPerHour: speedUnit
        }
    }

    func setDistanceUnit(_ unit: DistanceUnit) {
        distanceUnit = unit
        defaults.set(unit.rawValue, forKey: Self.distanceUnitKey)
    }

    func setSpeedUnit(_ unit: SpeedUnit) {
        speedUnit = unit
        defaults.set(unit.rawValue, forKey: Self.speedUnitKey)
    }

    /// Display-unit value per 1 m/s for the resolved speed unit.
    var displaySpeedFactor: Double {
        switch resolvedSpeedUnit {
        case .milesPerHour: Self.milesPerHourPerMetrePerSecond
        default: Self.kilometresPerHourPerMetrePerSecond
        }
    }

    // MARK: Speeds

    func speedMetresPerSecond(for mode: RouteTravelMode) -> Double {
        customSpeeds[mode] ?? mode.defaultSpeedMetresPerSecond
    }

    func hasCustomSpeed(for mode: RouteTravelMode) -> Bool {
        customSpeeds[mode] != nil
    }

    func setSpeed(_ metresPerSecond: Double, for mode: RouteTravelMode) {
        let clamped = Self.clamp(metresPerSecond, for: mode)
        customSpeeds[mode] = clamped
        defaults.set(clamped, forKey: Self.speedKey(mode))
    }

    func resetSpeed(for mode: RouteTravelMode) {
        customSpeeds[mode] = nil
        defaults.removeObject(forKey: Self.speedKey(mode))
    }

    static func clamp(_ metresPerSecond: Double, for mode: RouteTravelMode) -> Double {
        let range = mode.speedRangeMetresPerSecond
        return min(max(metresPerSecond, range.lowerBound), range.upperBound)
    }
}
