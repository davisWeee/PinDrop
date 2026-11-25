import Foundation

/// A plain latitude/longitude pair. Foundation-only so the route maths can be
/// unit-checked without MapKit or CoreLocation.
struct GeoPoint: Equatable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
}

enum RouteGeometry {
    static let earthRadius: Double = 6_371_008.8

    /// Great-circle distance in metres.
    static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    static func length(of points: [GeoPoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for index in 1..<points.count {
            total += distance(points[index - 1], points[index])
        }
        return total
    }

    /// Cumulative distance at every vertex (first value is 0).
    static func cumulativeDistances(of points: [GeoPoint]) -> [Double] {
        guard !points.isEmpty else { return [] }
        var values = [0.0]
        values.reserveCapacity(points.count)
        for index in 1..<points.count {
            values.append(values[index - 1] + distance(points[index - 1], points[index]))
        }
        return values
    }

    /// Drops consecutive vertices closer together than `minimumSpacing` metres.
    /// The first and last vertices are always kept.
    static func removingCloseVertices(_ points: [GeoPoint], minimumSpacing: Double) -> [GeoPoint] {
        guard points.count > 2 else { return points }
        var result = [points[0]]
        for point in points.dropFirst().dropLast() {
            if let last = result.last, distance(last, point) >= minimumSpacing {
                result.append(point)
            }
        }
        if let last = points.last {
            if result.count > 1, let previous = result.last, distance(previous, last) < minimumSpacing / 2 {
                result.removeLast()
            }
            result.append(last)
        }
        return result
    }

    /// Ramer–Douglas–Peucker line simplification. `tolerance` is in metres.
    /// Iterative (no recursion) so long GPS traces cannot overflow the stack.
    static func simplify(_ points: [GeoPoint], tolerance: Double) -> [GeoPoint] {
        guard points.count > 2, tolerance > 0 else { return points }

        let referenceLatitude = points.reduce(0.0) { $0 + $1.latitude } / Double(points.count)
        let cosLat = cos(referenceLatitude * .pi / 180)
        let projected: [(x: Double, y: Double)] = points.map {
            (
                x: $0.longitude * .pi / 180 * earthRadius * cosLat,
                y: $0.latitude * .pi / 180 * earthRadius
            )
        }

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (first, last) = stack.popLast() {
            guard last - first > 1 else { continue }

            var maxDistance = 0.0
            var maxIndex = first
            for index in (first + 1)..<last {
                let d = perpendicularDistance(
                    projected[index], from: projected[first], to: projected[last]
                )
                if d > maxDistance {
                    maxDistance = d
                    maxIndex = index
                }
            }

            if maxDistance > tolerance {
                keep[maxIndex] = true
                stack.append((first, maxIndex))
                stack.append((maxIndex, last))
            }
        }

        var result: [GeoPoint] = []
        for index in 0..<points.count where keep[index] {
            result.append(points[index])
        }
        return result
    }

    /// Timestamps for each vertex assuming constant speed from `start`.
    static func timestamps(
        for points: [GeoPoint],
        start: Date,
        metresPerSecond: Double
    ) -> [Date] {
        guard metresPerSecond > 0 else { return points.map { _ in start } }
        return cumulativeDistances(of: points).map {
            start.addingTimeInterval($0 / metresPerSecond)
        }
    }

    private static func perpendicularDistance(
        _ p: (x: Double, y: Double),
        from a: (x: Double, y: Double),
        to b: (x: Double, y: Double)
    ) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
