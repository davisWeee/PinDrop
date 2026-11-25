import Foundation

/// Parses GPX 1.0/1.1 (`trk`/`trkseg`/`trkpt`, `rte`/`rtept`, `wpt`) using XMLParser.
enum GPXParser {
    static func parse(_ data: Data) throws -> GPXDocument {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            if delegate.sawRoot == false, delegate.rootName != nil { throw GPXError.notGPX }
            let message = parser.parserError?.localizedDescription ?? "unknown error"
            throw GPXError.invalidXML(message)
        }
        guard delegate.rootName == "gpx" else { throw GPXError.notGPX }
        return delegate.document
    }

    static func parse(_ string: String) throws -> GPXDocument {
        try parse(Data(string.utf8))
    }

    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: trimmed)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var document = GPXDocument()
        var rootName: String?
        var sawRoot: Bool { rootName == "gpx" }

        private var stack: [String] = []
        private var text = ""
        private var currentPoint: GPXPoint?
        private var currentPointKind: String?
        private var currentPath: GPXPath?
        private var currentPathKind: String?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = Self.localName(elementName)
            if rootName == nil {
                rootName = name
                if name != "gpx" { parser.abortParsing() }
            }
            stack.append(name)
            text = ""

            switch name {
            case "trk", "rte":
                currentPath = GPXPath(name: nil, points: [])
                currentPathKind = name
            case "trkpt", "rtept", "wpt":
                currentPointKind = name
                if
                    let lat = attributeDict["lat"].flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }),
                    let lon = attributeDict["lon"].flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }),
                    (-90.0...90.0).contains(lat), (-180.0...180.0).contains(lon)
                {
                    currentPoint = GPXPoint(latitude: lat, longitude: lon)
                } else {
                    currentPoint = nil
                    document.skippedPointCount += 1
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = Self.localName(elementName)
            defer {
                _ = stack.popLast()
                text = ""
            }
            let parent = stack.count >= 2 ? stack[stack.count - 2] : nil
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

            switch name {
            case "ele":
                if currentPoint != nil, let elevation = Double(value) {
                    currentPoint?.elevation = elevation
                }
            case "time":
                if currentPoint != nil {
                    currentPoint?.time = GPXParser.parseDate(value)
                }
            case "name":
                guard !value.isEmpty else { break }
                switch parent {
                case "trkpt", "rtept", "wpt": currentPoint?.name = value
                case "trk", "rte": currentPath?.name = value
                case "metadata": document.name = value
                default: break
                }
            case "trkpt", "rtept":
                if let point = currentPoint, currentPath != nil {
                    currentPath?.points.append(point)
                }
                currentPoint = nil
                currentPointKind = nil
            case "wpt":
                if let point = currentPoint {
                    document.waypoints.append(point)
                }
                currentPoint = nil
                currentPointKind = nil
            case "trk":
                if let path = currentPath { document.tracks.append(path) }
                currentPath = nil
                currentPathKind = nil
            case "rte":
                if let path = currentPath { document.routes.append(path) }
                currentPath = nil
                currentPathKind = nil
            default:
                break
            }
        }

        private static func localName(_ element: String) -> String {
            guard let colon = element.lastIndex(of: ":") else { return element }
            return String(element[element.index(after: colon)...])
        }
    }
}
