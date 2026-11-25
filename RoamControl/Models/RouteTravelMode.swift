import Foundation
import MapKit

/// How the simulated location travels along a planned route.
enum RouteTravelMode: String, CaseIterable, Identifiable, Codable {
    case walking
    case driving
    case cycling

    var id: Self { self }

    /// Capitalised activity name, e.g. "Walking".
    @MainActor var title: String {
        switch self {
        case .walking: L10n.tr("Walking")
        case .driving: L10n.tr("Driving")
        case .cycling: L10n.tr("Cycling")
        }
    }

    /// Short verb for compact buttons.
    @MainActor var shortTitle: String {
        switch self {
        case .walking: L10n.tr("Walk")
        case .driving: L10n.tr("Drive")
        case .cycling: L10n.tr("Cycle")
        }
    }

    /// Lower-case form used inside sentences ("walking" / "on foot"); has its own translations
    /// because simply lower-casing the localized title is wrong in several languages.
    @MainActor var lowercasedTitle: String {
        switch self {
        case .walking: L10n.tr("walking")
        case .driving: L10n.tr("driving")
        case .cycling: L10n.tr("cycling")
        }
    }

    /// Symbol for buttons and labels.
    var symbol: String {
        switch self {
        case .walking: "figure.walk"
        case .driving: "car.fill"
        case .cycling: "bicycle"
        }
    }

    /// Symbol for the moving marker on the map.
    var markerSymbol: String {
        switch self {
        case .walking: "figure.walk.circle.fill"
        case .driving: "car.circle.fill"
        case .cycling: "bicycle.circle.fill"
        }
    }

    var startSymbol: String {
        switch self {
        case .walking: "figure.walk.motion"
        case .driving: "car.fill"
        case .cycling: "bicycle"
        }
    }

    var transportType: MKDirectionsTransportType {
        switch self {
        case .walking: .walking
        case .driving: .automobile
        case .cycling: .cycling
        }
    }

    /// Default cruising speed in km/h when the user has not customised it.
    var defaultSpeedKilometresPerHour: Double {
        switch self {
        case .walking: 5
        case .driving: 50
        case .cycling: 15
        }
    }

    /// Allowed custom speed range in km/h.
    var speedRangeKilometresPerHour: ClosedRange<Double> {
        switch self {
        case .walking: 1...15
        case .driving: 5...200
        case .cycling: 3...50
        }
    }

    var defaultSpeedMetresPerSecond: Double {
        defaultSpeedKilometresPerHour / 3.6
    }

    var speedRangeMetresPerSecond: ClosedRange<Double> {
        let range = speedRangeKilometresPerHour
        return (range.lowerBound / 3.6)...(range.upperBound / 3.6)
    }

    /// Increment used by speed steppers, in the display unit.
    var speedStep: Double {
        switch self {
        case .walking: 0.5
        case .cycling: 1
        case .driving: 5
        }
    }
}
