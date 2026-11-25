import CoreLocation
import MapKit
import Observation

@MainActor
@Observable
final class WalkingRoutePlanner {
    private(set) var route: MKRoute?
    private(set) var destination: LocationTarget?
    private(set) var isLoading = false
    /// Mode of the route currently shown (or being planned).
    private(set) var mode: RouteTravelMode = .walking
    /// True when MapKit had no route for `mode` and a walking path is being
    /// followed at this mode's speed instead (only possible for cycling).
    private(set) var isApproximated = false
    private(set) var errorMessage: String?

    @ObservationIgnored
    private var directions: MKDirections?
    @ObservationIgnored
    private var requestID = 0

    func preview(
        to target: LocationTarget,
        from source: LocationTarget? = nil,
        mode: RouteTravelMode = .walking
    ) async -> MKRoute? {
        directions?.cancel()
        route = nil
        destination = target
        self.mode = mode
        isApproximated = false
        errorMessage = nil
        isLoading = true
        requestID += 1
        let id = requestID

        defer {
            if id == requestID { isLoading = false }
        }

        var outcome = await calculate(to: target, from: source, transportType: mode.transportType)

        // MapKit only offers cycling directions in some regions. Rather than
        // failing, follow the walking path at cycling speed and say so.
        if mode == .cycling, case .failed = outcome {
            let walking = await calculate(to: target, from: source, transportType: .walking)
            if case .found = walking {
                outcome = walking
                isApproximated = true
            }
        }

        guard id == requestID else { return nil }
        switch outcome {
        case .found(let found):
            route = found
            return found
        case .cancelled:
            return nil
        case .failed(let message):
            errorMessage = message
            return nil
        }
    }

    private enum Outcome {
        case found(MKRoute)
        case cancelled
        case failed(String)
    }

    private func calculate(
        to target: LocationTarget,
        from source: LocationTarget?,
        transportType: MKDirectionsTransportType
    ) async -> Outcome {
        let request = MKDirections.Request()
        if let source {
            request.source = MKMapItem(
                location: CLLocation(latitude: source.latitude, longitude: source.longitude),
                address: nil
            )
        } else {
            request.source = .forCurrentLocation()
        }
        request.destination = MKMapItem(
            location: CLLocation(latitude: target.latitude, longitude: target.longitude),
            address: nil
        )
        request.transportType = transportType
        request.requestsAlternateRoutes = false

        let calculation = MKDirections(request: request)
        directions = calculation
        defer {
            if directions === calculation { directions = nil }
        }

        let name = mode.lowercasedTitle
        do {
            let response = try await calculation.calculate()
            guard directions === calculation else { return .cancelled }
            guard let preferredRoute = response.routes.first else {
                return .failed("No \(name) route was found for this destination.")
            }
            return .found(preferredRoute)
        } catch is CancellationError {
            return .cancelled
        } catch {
            guard directions === calculation else { return .cancelled }
            return .failed("\(mode.title) directions are unavailable. Check Location access and your internet connection, then try again.")
        }
    }

    func clear() {
        requestID += 1
        directions?.cancel()
        directions = nil
        route = nil
        destination = nil
        isLoading = false
        isApproximated = false
        errorMessage = nil
    }

    func retargetExistingRoute(to target: LocationTarget) {
        guard route != nil else { return }
        destination = target
        errorMessage = nil
    }
}
