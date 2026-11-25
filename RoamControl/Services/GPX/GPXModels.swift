import Foundation

struct GPXPoint: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var elevation: Double?
    var time: Date?
    var name: String?

    var geo: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }
}

struct GPXPath: Equatable, Sendable {
    var name: String?
    var points: [GPXPoint]
}

struct GPXDocument: Equatable, Sendable {
    var name: String?
    var waypoints: [GPXPoint] = []
    var routes: [GPXPath] = []
    /// Each track's segments are concatenated into one path.
    var tracks: [GPXPath] = []
    /// Points dropped because lat/lon were missing or out of range.
    var skippedPointCount = 0

    /// The path PinDrop will simulate: first usable track, else route, else
    /// the waypoints in file order.
    var primaryPath: GPXPath? {
        if let track = tracks.first(where: { $0.points.count >= 2 }) { return track }
        if let route = routes.first(where: { $0.points.count >= 2 }) { return route }
        if waypoints.count >= 2 { return GPXPath(name: name, points: waypoints) }
        return nil
    }
}

enum GPXError: Error, Equatable, LocalizedError {
    case invalidXML(String)
    case notGPX
    case noRoute

    var errorDescription: String? {
        switch self {
        case .invalidXML(let detail):
            return "This file is not valid XML (\(detail))."
        case .notGPX:
            return "This file is not a GPX document."
        case .noRoute:
            return "This GPX file has no route, track or two or more waypoints to follow."
        }
    }
}
