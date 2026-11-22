import Foundation

/// Approximate geographic country boundaries for gating speed camera alerts.
public struct CountryBoundaries: Sendable {
    public struct Polygon: Sendable {
        let code: String
        let rings: [[LatLng]]
        let bounds: (south: Double, west: Double, north: Double, east: Double)

        public init?(code: String, rings: [[LatLng]]) {
            guard let exterior = rings.first, exterior.count >= 4,
                  rings.allSatisfy({ $0.count >= 4 && $0.first == $0.last }) else { return nil }
            self.code = code
            self.rings = rings
            var south = 90.0, west = 180.0, north = -90.0, east = -180.0
            for vertex in exterior {
                south = min(south, vertex.lat)
                west = min(west, vertex.lng)
                north = max(north, vertex.lat)
                east = max(east, vertex.lng)
            }
            bounds = (south, west, north, east)
        }
    }

    private struct ResourcePolygon: Decodable {
        let polygon: Polygon?

        init(from decoder: Decoder) throws {
            var values = try decoder.unkeyedContainer()
            let code = try values.decode(String.self)
            let rings = try values.decode([[Double]].self)
            polygon = Polygon(code: code, rings: rings.map { ring in
                stride(from: 0, to: ring.count - 1, by: 2).map { LatLng(ring[$0 + 1], ring[$0]) }
            })
        }
    }

    public static let bundled: CountryBoundaries = {
        let polygons = (0..<4).flatMap { index -> [Polygon] in
            guard let url = Bundle.module.url(forResource: "country-boundaries-\(index)", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([ResourcePolygon].self, from: data) else { return [] }
            return decoded.compactMap(\.polygon)
        }
        return CountryBoundaries(polygons: polygons)
    }()

    let polygons: [Polygon]

    public init(polygons: [Polygon]) { self.polygons = polygons }

    /// Return a conservative local clearance, capped at 25 km for the short-lived cache.
    func locate(_ point: LatLng) -> (code: String?, clearance: Double) {
        let limit = 25_000.0
        let xScale = 111_000 * cos(point.lat * .pi / 180)
        let yScale = 110_000.0
        let dx = limit / xScale, dy = limit / yScale
        // Rings are split at the date line. Reject fixes whose search window straddles it.
        guard abs(point.lat) < 85, abs(point.lng) + dx < 180 else { return (nil, 0) }
        var countries = Set<String>()
        var clearanceSquared = limit * limit
        for polygon in polygons where
            point.lat >= polygon.bounds.south - dy && point.lat <= polygon.bounds.north + dy &&
            point.lng >= polygon.bounds.west - dx && point.lng <= polygon.bounds.east + dx {
            var contains = false
            for ring in polygon.rings {
                for i in 1..<ring.count {
                    let a = ring[i - 1], b = ring[i]
                    let ax = (a.lng - point.lng) * xScale, ay = (a.lat - point.lat) * yScale
                    let bx = (b.lng - point.lng) * xScale, by = (b.lat - point.lat) * yScale
                    let vx = bx - ax, vy = by - ay
                    let lengthSquared = vx * vx + vy * vy
                    guard lengthSquared > 0 else { continue }
                    if (ay > 0) != (by > 0), ax - ay * vx / vy > 0 { contains.toggle() }
                    let t = min(1, max(0, -(ax * vx + ay * vy) / lengthSquared))
                    let x = ax + t * vx, y = ay + t * vy
                    clearanceSquared = min(clearanceSquared, x * x + y * y)
                }
            }
            if contains { countries.insert(polygon.code) }
        }
        return (countries.count == 1 ? countries.first : nil, clearanceSquared.squareRoot())
    }
}

public struct JurisdictionCoordinator: Sendable {
    public struct Decision: Equatable, Sendable {
        public let countryCode: String?
        public var policy: CameraWarningPolicy { CameraJurisdiction.policy(isoCountryCode: countryCode) }
    }

    private struct Sample: Sendable {
        let point: LatLng
        let time: Date
        let code: String?
        let clearance: Double
    }

    private let boundaries: CountryBoundaries
    private let boundaryBuffer: Double
    private var sample: Sample?

    public init(boundaries: CountryBoundaries = .bundled, boundaryBuffer: Double = 5_000) {
        self.boundaries = boundaries
        self.boundaryBuffer = boundaryBuffer
    }

    public mutating func reset() { sample = nil }

    public mutating func update(position: LatLng, accuracy: Double, timestamp: Date, now: Date,
                                routeLookahead: LatLng? = nil) -> Decision {
        guard position.lat.isFinite, position.lng.isFinite, abs(position.lat) <= 90, abs(position.lng) <= 180,
              accuracy.isFinite, (0...100).contains(accuracy),
              (-2...8).contains(now.timeIntervalSince(timestamp)) else { return Decision(countryCode: nil) }

        let uncertainty = boundaryBuffer + accuracy
        if let sample {
            let elapsed = now.timeIntervalSince(sample.time)
            let traveled = sample.point.distance(to: position)
            let lookahead = routeLookahead.map { position.distance(to: $0) } ?? 0
            // Leave extra margin for the local distance approximation. Anticipate a boundary from
            // the route, but always base the decision on the raw GPS position, even after a reroute.
            let remaining = sample.clearance - 1.1 * traveled
            if (0..<30).contains(elapsed), let code = sample.code,
               remaining > uncertainty + min(lookahead, 1_000) {
                return Decision(countryCode: code)
            }
            if (0..<2).contains(elapsed), traveled < 100, remaining <= uncertainty {
                return Decision(countryCode: nil)
            }
        }

        let result = boundaries.locate(position)
        sample = Sample(point: position, time: now, code: result.code, clearance: result.clearance)
        return Decision(countryCode: result.clearance > uncertainty ? result.code : nil)
    }
}
