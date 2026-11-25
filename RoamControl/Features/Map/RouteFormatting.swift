import CoreLocation
import Foundation

/// Distance, speed and duration text that follows the user's unit settings.
@MainActor
enum RouteFormat {
    static func distance(
        _ metres: CLLocationDistance,
        preferences: RoutePreferences = .shared
    ) -> String {
        let metres = max(metres, 0)
        switch preferences.resolvedDistanceUnit {
        case .miles:
            if metres < RoutePreferences.metresPerMile * 0.1 {
                let useYards = Locale.current.region?.identifier == "GB"
                let measurement = useYards
                    ? Measurement(value: metres, unit: UnitLength.meters).converted(to: .yards)
                    : Measurement(value: metres, unit: UnitLength.meters).converted(to: .feet)
                return string(measurement, fractionDigits: 0)
            }
            let miles = Measurement(value: metres, unit: UnitLength.meters).converted(to: .miles)
            return string(miles, fractionDigits: miles.value < 100 ? 1 : 0)
        case .kilometres, .automatic:
            if metres < 1_000 {
                return string(Measurement(value: metres, unit: UnitLength.meters), fractionDigits: 0)
            }
            let kilometres = Measurement(value: metres, unit: UnitLength.meters).converted(to: .kilometers)
            return string(kilometres, fractionDigits: kilometres.value < 100 ? 1 : 0)
        }
    }

    static func speed(
        _ metresPerSecond: Double,
        preferences: RoutePreferences = .shared
    ) -> String {
        let base = Measurement(value: metresPerSecond, unit: UnitSpeed.metersPerSecond)
        switch preferences.resolvedSpeedUnit {
        case .milesPerHour:
            return string(base.converted(to: .milesPerHour), fractionDigits: 1)
        case .kilometresPerHour, .automatic:
            return string(base.converted(to: .kilometersPerHour), fractionDigits: 1)
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let seconds = max(seconds, 0)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        if seconds < 60 {
            formatter.allowedUnits = [.second]
            return formatter.string(from: max(seconds.rounded(), 1)) ?? "\(Int(seconds)) s"
        }
        formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : [.hour, .minute]
        // Round to whole minutes so "59.6 min" doesn't show as "59m" next to "1h".
        let rounded = (seconds / 60).rounded() * 60
        return formatter.string(from: rounded) ?? "\(Int(rounded / 60)) min"
    }

    static func arrival(after seconds: TimeInterval) -> String {
        Date.now
            .addingTimeInterval(max(seconds, 0))
            .formatted(date: .omitted, time: .shortened)
    }

    private static func string<U: Dimension>(_ measurement: Measurement<U>, fractionDigits: Int) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = .current
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.minimumFractionDigits = 0
        formatter.numberFormatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: measurement)
    }
}
