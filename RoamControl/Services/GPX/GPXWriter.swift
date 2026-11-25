import Foundation

/// Writes GPX 1.1 documents.
enum GPXWriter {
    /// A single track (`trk`/`trkseg`) — carries `time` on each point when present.
    static func track(
        name: String,
        points: [GPXPoint],
        creator: String = "PinDrop",
        generatedAt: Date = Date()
    ) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="\(escape(creator))" xmlns="http://www.topografix.com/GPX/1/1" \
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" \
        xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
          <metadata>
            <name>\(escape(name))</name>
            <time>\(format(generatedAt))</time>
          </metadata>
          <trk>
            <name>\(escape(name))</name>
            <trkseg>

        """
        for point in points {
            xml += "      <trkpt lat=\"\(number(point.latitude))\" lon=\"\(number(point.longitude))\">"
            if let elevation = point.elevation {
                xml += "<ele>\(String(format: "%.2f", elevation))</ele>"
            }
            if let time = point.time {
                xml += "<time>\(format(time))</time>"
            }
            xml += "</trkpt>\n"
        }
        xml += """
            </trkseg>
          </trk>
        </gpx>

        """
        return xml
    }

    /// Builds a timestamped track assuming constant speed from `start`.
    static func timedTrack(
        name: String,
        coordinates: [GeoPoint],
        start: Date,
        metresPerSecond: Double
    ) -> String {
        let times = RouteGeometry.timestamps(for: coordinates, start: start, metresPerSecond: metresPerSecond)
        let points = zip(coordinates, times).map {
            GPXPoint(latitude: $0.latitude, longitude: $0.longitude, elevation: nil, time: $1, name: nil)
        }
        return track(name: name, points: points, generatedAt: start)
    }

    static func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(character)
            }
        }
        return result
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.7f", value)
    }

    private static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
