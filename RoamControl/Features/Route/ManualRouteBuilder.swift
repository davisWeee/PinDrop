import CoreLocation
import MapKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

extension GeoPoint {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// A finished route (drawn by hand or imported from GPX) handed to the walking simulation.
struct ManualRoute: Equatable {
    enum Source: Equatable {
        case drawn
        case gpx
    }

    var name: String
    var points: [GeoPoint]
    var source: Source
}

/// Editable waypoint shown as a draggable handle on the map.
struct ManualRouteHandle: Identifiable {
    enum Role {
        case start, middle, end
    }

    let id: Int
    let point: GeoPoint
    let role: Role
}

/// State for the manual route editor: tap-to-add waypoints, freehand strokes,
/// drag/undo/clear, GPX import. Pure drawing state — movement itself is delegated
/// to `WalkingSimulationController` once the route is finished.
@MainActor
@Observable
final class ManualRouteBuilder {
    enum Mode: String, CaseIterable, Identifiable {
        case tap
        case freehand

        var id: Self { self }
    }

    /// Above this many vertices we stop drawing per-vertex drag handles.
    static let maximumHandleCount = 150
    static let maximumImportBytes = 25 * 1_024 * 1_024

    private(set) var isEditing = false
    var mode: Mode = .tap
    private(set) var points: [GeoPoint] = []
    private(set) var strokeBuffer: [GeoPoint] = []
    private(set) var prepared: ManualRoute?
    private(set) var undoStack: [[GeoPoint]] = []
    private(set) var distance: Double = 0
    private(set) var exportStart = Date()
    var isShowingImporter = false
    var message: String?
    private(set) var fitToken = 0
    private(set) var fitRect: MKMapRect = .null

    var isActive: Bool { isEditing || prepared != nil }
    var canUndo: Bool { !undoStack.isEmpty }

    /// Everything currently drawn, including a stroke still under the finger.
    var displayPoints: [GeoPoint] {
        if let prepared { return prepared.points }
        return points + strokeBuffer
    }

    var showsHandles: Bool {
        isEditing && mode == .tap && points.count <= Self.maximumHandleCount
    }

    var handles: [ManualRouteHandle] {
        points.enumerated().map { index, point in
            let role: ManualRouteHandle.Role
            if index == 0 {
                role = .start
            } else if index == points.count - 1 {
                role = .end
            } else {
                role = .middle
            }
            return ManualRouteHandle(id: index, point: point, role: role)
        }
    }

    // MARK: Editing

    func startEditing() {
        points = []
        strokeBuffer = []
        undoStack = []
        prepared = nil
        mode = .tap
        message = nil
        isEditing = true
        refreshDistance()
    }

    func cancel() {
        isEditing = false
        points = []
        strokeBuffer = []
        undoStack = []
        prepared = nil
        message = nil
        refreshDistance()
    }

    /// Returns true when the tap was used by the route layer (so the map should not drop a pin).
    func consumeMapTap(_ coordinate: CLLocationCoordinate2D) -> Bool {
        if isEditing {
            if mode == .tap { addPoint(coordinate) }
            return true
        }
        return prepared != nil
    }

    func addPoint(_ coordinate: CLLocationCoordinate2D) {
        guard isEditing else { return }
        pushUndo()
        points.append(GeoPoint(coordinate))
        refreshDistance()
    }

    func beginDrag() {
        pushUndo()
    }

    func movePoint(at index: Int, to coordinate: CLLocationCoordinate2D) {
        guard isEditing, points.indices.contains(index) else { return }
        points[index] = GeoPoint(coordinate)
        refreshDistance()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        points = previous
        strokeBuffer = []
        refreshDistance()
    }

    func clear() {
        guard !points.isEmpty else { return }
        pushUndo()
        points = []
        strokeBuffer = []
        refreshDistance()
    }

    // MARK: Freehand

    func beginStroke() {
        guard isEditing else { return }
        pushUndo()
        strokeBuffer = []
    }

    func appendStrokePoint(_ coordinate: CLLocationCoordinate2D, minimumSpacing: Double) {
        guard isEditing else { return }
        let point = GeoPoint(coordinate)
        if let last = strokeBuffer.last {
            guard RouteGeometry.distance(last, point) >= minimumSpacing else { return }
        }
        strokeBuffer.append(point)
        refreshDistance()
    }

    /// Finishes the stroke: Douglas–Peucker simplifies the raw finger path and appends it.
    func endStroke(tolerance: Double) {
        defer {
            strokeBuffer = []
            refreshDistance()
        }
        guard isEditing, !strokeBuffer.isEmpty else {
            _ = undoStack.popLast()
            return
        }
        let simplified = RouteGeometry.simplify(strokeBuffer, tolerance: tolerance)
        for point in simplified where points.last != point {
            points.append(point)
        }
    }

    // MARK: Finishing

    /// Hands the drawn path to the walking simulation. Returns false if it is too short.
    @discardableResult
    func finish(simulation: WalkingSimulationController) -> Bool {
        let cleaned = RouteGeometry.removingCloseVertices(points, minimumSpacing: 0.5)
        guard cleaned.count >= 2 else {
            message = "Add at least two points to make a route."
            return false
        }
        let name = "Route " + Date.now.formatted(date: .abbreviated, time: .shortened)
        install(ManualRoute(name: name, points: cleaned, source: .drawn), simulation: simulation)
        return true
    }

    /// Re-opens a prepared route for editing.
    func edit(simulation: WalkingSimulationController) {
        guard let prepared, !simulation.locksDestination else { return }
        simulation.reset()
        points = prepared.points
        strokeBuffer = []
        undoStack = []
        self.prepared = nil
        mode = .tap
        isEditing = true
        refreshDistance()
    }

    func discard(simulation: WalkingSimulationController) {
        simulation.reset()
        cancel()
    }

    /// Keeps the on-screen polyline in step after "Walk Route Back" reverses the simulation.
    func reversePrepared() {
        guard var route = prepared else { return }
        route.points.reverse()
        prepared = route
        exportStart = Date()
    }

    func requestFit() {
        let rect = boundingRect(of: displayPoints)
        guard !rect.isNull, !rect.isEmpty else { return }
        fitRect = rect
        fitToken += 1
    }

    // MARK: GPX

    static var gpxContentTypes: [UTType] {
        var types: [UTType] = []
        if let gpx = UTType(filenameExtension: "gpx") { types.append(gpx) }
        types.append(.xml)
        types.append(.data)
        return types
    }

    func importGPX(_ result: Result<URL, any Error>, simulation: WalkingSimulationController) {
        switch result {
        case .failure(let error):
            message = error.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                guard data.count <= Self.maximumImportBytes else {
                    message = "This GPX file is too large (over 25 MB)."
                    return
                }
                let document = try GPXParser.parse(data)
                guard let path = document.primaryPath else { throw GPXError.noRoute }
                let cleaned = RouteGeometry.removingCloseVertices(
                    path.points.map(\.geo), minimumSpacing: 0.5
                )
                guard cleaned.count >= 2 else { throw GPXError.noRoute }

                let fallback = url.deletingPathExtension().lastPathComponent
                let name = path.name ?? document.name ?? fallback
                isEditing = false
                undoStack = []
                points = []
                install(ManualRoute(name: name, points: cleaned, source: .gpx), simulation: simulation)
            } catch {
                message = error.localizedDescription
            }
        }
    }

    /// Lazily-encoded GPX for the share sheet, with timestamps spaced at `metresPerSecond`.
    func exportFile(metresPerSecond: Double) -> GPXExportFile? {
        let exported = displayPoints
        guard exported.count >= 2 else { return nil }
        return GPXExportFile(
            name: prepared?.name ?? "PinDrop route",
            points: exported,
            start: exportStart,
            metresPerSecond: metresPerSecond
        )
    }

    // MARK: Private

    private func install(_ route: ManualRoute, simulation: WalkingSimulationController) {
        guard let last = route.points.last else { return }
        let destination = LocationTarget(
            name: route.name,
            subtitle: "Custom route",
            latitude: last.latitude,
            longitude: last.longitude
        )
        simulation.prepare(coordinates: route.points.map(\.coordinate), destination: destination)
        prepared = route
        isEditing = false
        strokeBuffer = []
        exportStart = Date()
        message = nil
        refreshDistance()
        requestFit()
    }

    private func pushUndo() {
        undoStack.append(points)
        if undoStack.count > 100 { undoStack.removeFirst() }
    }

    private func refreshDistance() {
        distance = RouteGeometry.length(of: displayPoints)
    }

    private func boundingRect(of geoPoints: [GeoPoint]) -> MKMapRect {
        var rect = MKMapRect.null
        for geo in geoPoints {
            let point = MKMapPoint(geo.coordinate)
            rect = rect.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        guard !rect.isNull else { return rect }
        let horizontal = max(rect.size.width * 0.24, 1_200)
        let vertical = max(rect.size.height * 0.30, 1_200)
        return rect.insetBy(dx: -horizontal, dy: -vertical)
    }
}

/// Transferable GPX payload; the XML is only generated when the share sheet asks for it.
struct GPXExportFile: Transferable, Sendable {
    let name: String
    let points: [GeoPoint]
    let start: Date
    let metresPerSecond: Double

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .xml) { item in
            let xml = GPXWriter.timedTrack(
                name: item.name,
                coordinates: item.points,
                start: item.start,
                metresPerSecond: item.metresPerSecond
            )
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
            let safeName = String(
                item.name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
            ).trimmingCharacters(in: .whitespaces)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(safeName.isEmpty ? "PinDrop-route" : safeName)
                .appendingPathExtension("gpx")
            try xml.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
