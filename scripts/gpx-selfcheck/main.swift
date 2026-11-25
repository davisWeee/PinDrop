// Pure-Swift self-check for GPX + route geometry. No XCTest needed.
// Run: scripts/gpx-selfcheck/run.sh
import Foundation

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() {
        print("PASS  \(message)")
    } else {
        failures += 1
        print("FAIL  \(message) (line \(line))")
    }
}
func near(_ a: Double, _ b: Double, _ eps: Double) -> Bool { abs(a - b) <= eps }

// MARK: geometry
let oneDegreeLat = RouteGeometry.distance(GeoPoint(latitude: 0, longitude: 0), GeoPoint(latitude: 1, longitude: 0))
check(near(oneDegreeLat, 111_195, 50), "1° latitude ≈ 111.2 km (got \(oneDegreeLat))")

// A straight north-south line with ±1 m sideways jitter collapses to its endpoints at 5 m tolerance.
var noisy: [GeoPoint] = []
for i in 0...200 {
    let jitter = (i % 2 == 0 ? 1.0 : -1.0) * 1.0 / 111_320.0   // ~1 m of longitude at the equator
    noisy.append(GeoPoint(latitude: Double(i) * 0.00002, longitude: jitter))
}
let simplified = RouteGeometry.simplify(noisy, tolerance: 5)
check(simplified.count == 2, "DP collapses jittery straight line to 2 points (got \(simplified.count))")
check(simplified.first == noisy.first && simplified.last == noisy.last, "DP keeps endpoints")

// An L-shape keeps its corner.
let l = [GeoPoint(latitude: 0, longitude: 0), GeoPoint(latitude: 0.001, longitude: 0), GeoPoint(latitude: 0.002, longitude: 0),
         GeoPoint(latitude: 0.002, longitude: 0.001), GeoPoint(latitude: 0.002, longitude: 0.002)]
let lSimple = RouteGeometry.simplify(l, tolerance: 3)
check(lSimple.count == 3 && lSimple[1] == GeoPoint(latitude: 0.002, longitude: 0), "DP keeps the L corner (got \(lSimple.count) pts)")

// 50k-point trace does not overflow the stack and is fast.
var long: [GeoPoint] = []
for i in 0..<50_000 { long.append(GeoPoint(latitude: 51 + Double(i) * 1e-6, longitude: sin(Double(i) / 500) * 1e-3)) }
let t0 = Date()
let longSimple = RouteGeometry.simplify(long, tolerance: 2)
check(longSimple.count < long.count && longSimple.count > 10, "DP handles 50k points → \(longSimple.count) in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")

let spaced = RouteGeometry.removingCloseVertices(noisy, minimumSpacing: 50)
check(spaced.count < noisy.count && spaced.first == noisy.first && spaced.last == noisy.last, "close-vertex filter keeps ends (\(spaced.count) pts)")

let times = RouteGeometry.timestamps(for: [GeoPoint(latitude: 0, longitude: 0), GeoPoint(latitude: 0.001, longitude: 0)],
                                     start: Date(timeIntervalSince1970: 0), metresPerSecond: 1.4)
check(near(times[1].timeIntervalSince1970, RouteGeometry.distance(GeoPoint(latitude: 0, longitude: 0), GeoPoint(latitude: 0.001, longitude: 0)) / 1.4, 0.001), "timestamps follow distance / speed")

// MARK: parser
let sample = """
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="x" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>Morning loop</name></metadata>
  <wpt lat="51.5" lon="-0.12"><name>Start &amp; cafe</name></wpt>
  <rte><name>Planned</name>
    <rtept lat="51.5" lon="-0.12"/><rtept lat="51.51" lon="-0.13"/></rte>
  <trk><name>Run</name>
    <trkseg>
      <trkpt lat="51.5000" lon="-0.1200"><ele>12.5</ele><time>2026-01-01T08:00:00Z</time></trkpt>
      <trkpt lat="51.5010" lon="-0.1210"><time>2026-01-01T08:00:10.500Z</time></trkpt>
    </trkseg>
    <trkseg>
      <trkpt lat="51.5020" lon="-0.1220"/>
      <trkpt lat="999" lon="0"/>
      <trkpt lon="1"/>
    </trkseg>
  </trk>
</gpx>
"""
do {
    let doc = try GPXParser.parse(sample)
    check(doc.name == "Morning loop", "metadata name")
    check(doc.waypoints.count == 1 && doc.waypoints[0].name == "Start & cafe", "wpt with escaped name")
    check(doc.routes.count == 1 && doc.routes[0].points.count == 2 && doc.routes[0].name == "Planned", "rte parsed")
    check(doc.tracks.count == 1 && doc.tracks[0].points.count == 3, "trk segments concatenated, bad points skipped (\(doc.tracks[0].points.count))")
    check(doc.skippedPointCount == 2, "2 invalid points counted (got \(doc.skippedPointCount))")
    check(doc.tracks[0].points[0].elevation == 12.5, "elevation")
    check(doc.tracks[0].points[0].time == Date(timeIntervalSince1970: 1_767_254_400), "time parsed (\(String(describing: doc.tracks[0].points[0].time)))")
    check(near(doc.tracks[0].points[1].time!.timeIntervalSince(doc.tracks[0].points[0].time!), 10.5, 0.001), "fractional-seconds time")
    check(doc.primaryPath?.name == "Run", "primary path prefers track")
} catch {
    failures += 1; print("FAIL  sample parse threw \(error)")
}

do {
    let wptOnly = try GPXParser.parse("<gpx version=\"1.1\"><wpt lat=\"1\" lon=\"2\"/><wpt lat=\"1.1\" lon=\"2.1\"/></gpx>")
    check(wptOnly.primaryPath?.points.count == 2, "waypoint-only file becomes a path")
    let ns = try GPXParser.parse("<g:gpx xmlns:g=\"http://www.topografix.com/GPX/1/1\"><g:trk><g:trkseg><g:trkpt lat=\"1\" lon=\"2\"/><g:trkpt lat=\"1\" lon=\"2.1\"/></g:trkseg></g:trk></g:gpx>")
    check(ns.primaryPath?.points.count == 2, "namespace-prefixed elements")
    let empty = try GPXParser.parse("<gpx version=\"1.1\"/>")
    check(empty.primaryPath == nil, "empty gpx has no primary path")
} catch {
    failures += 1; print("FAIL  extra parse threw \(error)")
}

do { _ = try GPXParser.parse("<kml/>"); failures += 1; print("FAIL  kml accepted") }
catch GPXError.notGPX { print("PASS  non-GPX root rejected") }
catch { failures += 1; print("FAIL  wrong error \(error)") }

do { _ = try GPXParser.parse("<gpx><trk>"); failures += 1; print("FAIL  truncated xml accepted") }
catch GPXError.invalidXML { print("PASS  malformed XML rejected") }
catch { failures += 1; print("FAIL  wrong error \(error)") }

// MARK: writer round-trip
let route = [GeoPoint(latitude: 51.5, longitude: -0.12), GeoPoint(latitude: 51.5009, longitude: -0.1195), GeoPoint(latitude: 51.5018, longitude: -0.119)]
let start = Date(timeIntervalSince1970: 1_800_000_000)
let xml = GPXWriter.timedTrack(name: "A <b> & \"c\"", coordinates: route, start: start, metresPerSecond: 1.4)
check(xml.contains("version=\"1.1\"") && xml.contains("xmlns=\"http://www.topografix.com/GPX/1/1\""), "writer emits GPX 1.1 header")
check(xml.contains("A &lt;b&gt; &amp; &quot;c&quot;"), "writer escapes XML")
do {
    let back = try GPXParser.parse(xml)
    let path = back.primaryPath
    check(path?.name == "A <b> & \"c\"", "round-trip name")
    check(path?.points.count == 3, "round-trip point count")
    check(path.map { zip($0.points, route).allSatisfy { near($0.latitude, $1.latitude, 1e-7) && near($0.longitude, $1.longitude, 1e-7) } } == true, "round-trip coordinates")
    let expectedEnd = start.addingTimeInterval(RouteGeometry.length(of: route) / 1.4)
    check(path?.points.last?.time.map { near($0.timeIntervalSince(expectedEnd), 0, 1) } == true, "round-trip end time ≈ distance/speed")
    check(path?.points.first?.time == start, "round-trip start time")
} catch {
    failures += 1; print("FAIL  round-trip threw \(error)")
}

print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
