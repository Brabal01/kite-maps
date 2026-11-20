import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/**
 * One public GTFS-Realtime feed from the Mobility Database catalog.
 *
 * The catalog is the public CSV export at files.mobilitydatabase.org. It is keyless and carries
 * coverage, licence, authentication type and the entity types a feed provides. Kite only offers
 * feeds that are public (no key), active and inside the requested area. A feed that needs a key is
 * never used, and a feed marked as development-only is skipped.
 */
public struct TransitFeed: Identifiable, Hashable, Sendable {
    public var id: String
    public var provider: String
    public var country: String
    public var name: String
    public var url: String
    /// `tu` (trip updates), `vp` (vehicle positions), `sa` (service alerts), pipe separated.
    public var entities: String
    public var license: String
    public var status: String
    public var minimumLatitude: Double
    public var maximumLatitude: Double
    public var minimumLongitude: Double
    public var maximumLongitude: Double

    public var hasTripUpdates: Bool { entities.split(separator: "|").contains("tu") }
    public var hasVehiclePositions: Bool { entities.split(separator: "|").contains("vp") }
    public var hasServiceAlerts: Bool { entities.split(separator: "|").contains("sa") }

    /** Straight-line distance from [point] to the feed's coverage box; zero when inside it. */
    public func distanceMeters(to point: LatLng) -> Double {
        let lat = min(max(point.lat, minimumLatitude), maximumLatitude)
        let lng = min(max(point.lng, minimumLongitude), maximumLongitude)
        return point.distance(to: LatLng(lat, lng))
    }
}

/**
 * Keyless access to the public Mobility Database catalog. The CSV is about 3 MB and changes
 * slowly, so it is cached in memory for twelve hours. Discovery is best effort: a failed catalog
 * request returns the previous cache, or an empty list, and the timetable keeps working.
 */
public actor TransitCatalog {
    public static let shared = TransitCatalog()

    public static let catalogURL = URL(string: "https://files.mobilitydatabase.org/feeds_v2.csv")!

    private var cached: [TransitFeed] = []
    private var cachedAt: Date?
    private var loading: Task<[TransitFeed], Never>?

    public init() {}

    public func feeds(maxAge: TimeInterval = 12 * 3600, now: Date = Date()) async -> [TransitFeed] {
        if let cachedAt, now.timeIntervalSince(cachedAt) < maxAge, !cached.isEmpty {
            return cached
        }
        if let loading { return await loading.value }
        let task = Task<[TransitFeed], Never> {
            var request = URLRequest(url: Self.catalogURL, timeoutInterval: 25)
            request.setValue("Kite-iOS transit catalog", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8) else { return [] }
            return Self.parse(text)
        }
        loading = task
        let result = await task.value
        loading = nil
        if !result.isEmpty {
            cached = result
            cachedAt = now
        }
        return result.isEmpty ? cached : result
    }

    /**
     * Public feeds whose coverage box is within [radiusMeters] of [point]. Trip-update feeds come
     * first, then vehicle-only feeds. The caller should still treat every feed as optional and fall
     * back to the timetable if it fails.
     */
    public func candidates(near point: LatLng, radiusMeters: Double = 30_000,
                           limit: Int = 3, now: Date = Date()) async -> [TransitFeed] {
        let all = await feeds(now: now)
        return all
            .map { ($0, $0.distanceMeters(to: point)) }
            .filter { $0.1 <= radiusMeters }
            .sorted { a, b in
                if a.0.hasTripUpdates != b.0.hasTripUpdates { return a.0.hasTripUpdates }
                if a.1 != b.1 { return a.1 < b.1 }
                return a.0.provider < b.0.provider
            }
            .prefix(max(0, limit))
            .map(\.0)
    }

    /// Exposed for tests: parse the public CSV without touching the network.
    public static func parse(_ text: String) -> [TransitFeed] {
        let rows = csv(text)
        guard let header = rows.first else { return [] }
        let index = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset) })
        func value(_ row: [String], _ key: String) -> String {
            guard let i = index[key], i < row.count else { return "" }
            return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var out: [TransitFeed] = []
        for row in rows.dropFirst() {
            guard value(row, "data_type") == "gtfs_rt" else { continue }
            let status = value(row, "status").lowercased()
            guard status.isEmpty || status == "active" else { continue }
            let auth = value(row, "urls.authentication_type")
            guard auth.isEmpty || auth == "0" else { continue }
            let url = value(row, "urls.direct_download")
            guard url.hasPrefix("https://") else { continue }
            let note = value(row, "note").lowercased()
            guard !note.contains("development purposes"), !note.contains("not be used in public") else { continue }
            guard let minLat = Double(value(row, "location.bounding_box.minimum_latitude")),
                  let maxLat = Double(value(row, "location.bounding_box.maximum_latitude")),
                  let minLng = Double(value(row, "location.bounding_box.minimum_longitude")),
                  let maxLng = Double(value(row, "location.bounding_box.maximum_longitude")),
                  minLat <= maxLat, minLng <= maxLng else { continue }
            let entities = value(row, "entity_type")
            guard entities.contains("tu") || entities.contains("vp") || entities.contains("sa") else { continue }
            out.append(TransitFeed(
                id: value(row, "id"),
                provider: value(row, "provider"),
                country: value(row, "location.country_code"),
                name: value(row, "name"),
                url: url,
                entities: entities,
                license: value(row, "urls.license"),
                status: status,
                minimumLatitude: minLat,
                maximumLatitude: maxLat,
                minimumLongitude: minLng,
                maximumLongitude: maxLng))
        }
        return out
    }

    /// A small RFC 4180 parser: quoted fields, escaped quotes and CRLF.
    static func csv(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if quoted {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        i = next
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    quoted = true
                case ",":
                    row.append(field)
                    field = ""
                case "\r":
                    break
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                default:
                    field.append(c)
                }
            }
            i = text.index(after: i)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        if let first = rows.first, let head = first.first, head == "\u{FEFF}" {
            rows[0][0] = String(rows[0][0].dropFirst())
        }
        return rows
    }
}
