import Foundation

public struct LatLng: Hashable, Codable, Sendable {
    public var lat: Double
    public var lng: Double

    public init(_ lat: Double, _ lng: Double) {
        self.lat = lat
        self.lng = lng
    }

    /** Great-circle distance in meters. */
    public func distance(to o: LatLng) -> Double {
        let r = 6_371_000.0
        let p1 = lat * .pi / 180, p2 = o.lat * .pi / 180
        let dp = (o.lat - lat) * .pi / 180, dl = (o.lng - lng) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}

extension Double {
    /**
     * A coordinate written out in plain digits for a web address. Swift writes very small numbers
     * like 0.00005 as "5e-05" (right by the Greenwich line, in London), which servers turn away.
     */
    public var plain: String {
        if self == 0 || abs(self) >= 1e-4 { return String(self) }
        var s = String(format: "%.10f", self)
        while s.hasSuffix("0") { s.removeLast() }
        return s.hasSuffix(".") ? s + "0" : s
    }
}

public struct AboutSection: Hashable, Codable, Sendable {
    public var title: String
    public var items: [String]
}

/** One place, as the place sheet shows it. Every field but name and location is optional:
 *  Google sends a different subset per business, and Photon sends almost none. */
public struct Place: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var location: LatLng
    public var category: String?
    public var address: String?
    public var rating: Double?
    public var reviewCount: Int?
    public var priceText: String?
    public var website: String?
    public var phone: String?
    public var statusText: String?
    public var openNow: Bool?
    public var permanentlyClosed = false
    public var hours: [String] = []
    public var photoUrls: [String] = []
    public var featuredReview: String?
    public var reviewExcerpts: [String]?
    public var editorialSummary: String?
    public var about: [AboutSection] = []
    public var featureId: String?
    public var placeId: String?
    public var distanceMeters: Double?
    /** Where the place came from: "google" or "osm". */
    public var source: String

    public init(id: String, name: String, location: LatLng, source: String) {
        self.id = id
        self.name = name
        self.location = location
        self.source = source
    }

    /// Identify the same nearby named feature across map and search providers.
    ///
    /// A name and a radius alone are not enough: two branches of the same chain, or two units in
    /// one shopping centre, can sit within 150 m of each other. When both sides carry Google's
    /// stable place ID, different IDs mean different businesses even if the names are identical.
    public func matchesNearby(_ other: Place) -> Bool {
        if id == other.id { return true }
        if let mine = placeId, !mine.isEmpty, let theirs = other.placeId, !theirs.isEmpty {
            return mine == theirs
        }
        let a = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = other.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame else { return false }
        return location.distance(to: other.location) <= 150
    }

    /// Opens Google's public place page. The feature ID identifies the business even without a Places ID.
    public var googlePlacePage: URL? {
        guard source == "google" else { return nil }
        if let featureId {
            let parts = featureId.split(separator: ":", omittingEmptySubsequences: false)
            if parts.count == 2, parts.allSatisfy({ $0.hasPrefix("0x") }),
               UInt64(parts[0].dropFirst(2), radix: 16) != nil,
               let cid = UInt64(parts[1].dropFirst(2), radix: 16), cid > 0 {
                var page = URLComponents()
                page.scheme = "https"
                page.host = "www.google.com"
                page.path = "/maps"
                page.queryItems = [URLQueryItem(name: "cid", value: String(cid))]
                return page.url
            }
        }
        if placeId?.isEmpty == false { return shareURL }
        var page = URLComponents()
        page.scheme = "https"
        page.host = "www.google.com"
        page.path = "/maps/search/"
        let address = address?.isEmpty == false ? address : nil
        let nearby = address ?? "\(location.lat.plain),\(location.lng.plain)"
        page.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: "\(name) \(nearby)")
        ]
        return page.url
    }

    /** A Google Maps link for the place, for sharing and for opening it in Google Maps. */
    public var shareURL: URL? {
        if let placeId {
            var c = URLComponents(string: "https://www.google.com/maps/search/")!
            c.queryItems = [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "query", value: name),
                URLQueryItem(name: "query_place_id", value: placeId),
            ]
            return c.url
        }
        // Not a Google place (a dropped pin, a postcode, an open-map place): Google Maps at the spot,
        // which opens in any maps app the person you send it to has.
        return URL(string: "https://www.google.com/maps/search/?api=1&query=\(location.lat),\(location.lng)")
    }
}
