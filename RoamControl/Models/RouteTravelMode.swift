import Foundation
import MapKit

/// How the simulated location travels along a planned route.
enum RouteTravelMode: String, CaseIterable, Identifiable, Codable {
    case walking
    case driving
    case cycling

    var id: Self { self }

    /// Capitalised activity name, e.g. "Walking".
    var title: String {
        switch self {
        case .walking: "Walking"
        case .driving: "Driving"
        case .cycling: "Cycling"
        }
    }

    /// Short verb for compact buttons.
    var shortTitle: String {
        switch self {
        case .walking: "Walk"
        case .driving: "Drive"
        case .cycling: "Cycle"
        }
    }

    var lowercasedTitle: String { title.lowercased() }

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
