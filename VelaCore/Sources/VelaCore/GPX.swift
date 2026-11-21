import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct GPXPoint: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var elevationMeters: Double?
    public var time: Date?

    public init(latitude: Double, longitude: Double, elevationMeters: Double? = nil,
                time: Date? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevationMeters = elevationMeters
        self.time = time
    }

    public var location: LatLng { LatLng(latitude, longitude) }
}

public struct GPXTrack: Equatable, Sendable {
    public var name: String
    public var points: [GPXPoint]

    public init(name: String, points: [GPXPoint]) {
        self.name = name
        self.points = points
    }

    public var line: [LatLng] { points.map(\.location) }
    public var distanceMeters: Double { Geo.length(line) }

    public var elevationGainMeters: Double {
        var gain = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            if let from = a.elevationMeters, let to = b.elevationMeters, to > from {
                gain += to - from
            }
        }
        return gain
    }
}

public enum GPXError: Error, Equatable {
    case tooLarge
    case malformed
    case noPoints
    case tooManyPoints
    case invalidCoordinate
}

/**
 GPX import/export. This is a track, not turn-by-turn guidance: the caller must
 label it as such. The parser is bounded and rejects malformed or implausible
 coordinates before they reach the map.
 */
public enum GPX {
    public static let maximumBytes = 5 * 1024 * 1024
    public static let maximumPoints = 100_000

    public static func parse(_ data: Data) throws -> GPXTrack {
        guard data.count <= maximumBytes else { throw GPXError.tooLarge }
        let parser = XMLParser(data: data)
        let delegate = GPXParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            if delegate.tooMany { throw GPXError.tooManyPoints }
            if delegate.invalid { throw GPXError.invalidCoordinate }
            throw GPXError.malformed
        }
        if delegate.tooMany { throw GPXError.tooManyPoints }
        if delegate.invalid { throw GPXError.invalidCoordinate }
        guard !delegate.points.isEmpty else { throw GPXError.noPoints }
        let name = delegate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return GPXTrack(name: name.isEmpty ? "GPX track" : name,
                        points: delegate.points)
    }

    public static func export(_ route: Route, name: String? = nil) -> Data {
        let title = escape(name ?? route.summary ?? "Kite route")
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Kite Maps" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>\(title)</name>
            <trkseg>

        """
        for point in route.polyline {
            xml += "      <trkpt lat=\"\(point.lat)\" lon=\"\(point.lng)\"></trkpt>\n"
        }
        xml += """
            </trkseg>
          </trk>
        </gpx>

        """
        return Data(xml.utf8)
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    var points: [GPXPoint] = []
    var name = ""
    var tooMany = false
    var invalid = false
    private var current: GPXPoint?
    private var text = ""
    private var readingName = false
    private var readingElevation = false
    private var readingTime = false
    private let formatter = ISO8601DateFormatter()

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let element = elementName.lowercased()
        if element == "trkpt" || element == "rtept" || element == "wpt" {
            guard points.count < GPX.maximumPoints else {
                tooMany = true
                parser.abortParsing()
                return
            }
            guard let latText = attributeDict["lat"], let lonText = attributeDict["lon"],
                  let lat = Double(latText), let lon = Double(lonText),
                  lat.isFinite, lon.isFinite, (-90...90).contains(lat),
                  (-180...180).contains(lon) else {
                invalid = true
                parser.abortParsing()
                return
            }
            current = GPXPoint(latitude: lat, longitude: lon)
        } else if element == "name", current == nil {
            readingName = true
            text = ""
        } else if element == "ele" {
            readingElevation = true
            text = ""
        } else if element == "time" {
            readingTime = true
            text = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if readingName || readingElevation || readingTime { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let element = elementName.lowercased()
        if element == "trkpt" || element == "rtept" || element == "wpt" {
            if let current { points.append(current) }
            current = nil
        } else if element == "name", readingName {
            name = text
            readingName = false
        } else if element == "ele", readingElevation {
            if let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
               value.isFinite {
                current?.elevationMeters = value
            }
            readingElevation = false
        } else if element == "time", readingTime {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = formatter.date(from: value) { current?.time = date }
            readingTime = false
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {}
}
