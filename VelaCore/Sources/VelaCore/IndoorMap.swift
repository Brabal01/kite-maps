import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct IndoorPlan: Sendable {
    public struct Feature: Identifiable, Hashable, Sendable {
        public let id: String
        public let floors: Set<String>
        public let name: String?
        public let kind: String
        public let points: [LatLng]
        public var isPolygon: Bool { points.count >= 4 && points.first == points.last }
        public var center: LatLng {
            let ring = isPolygon ? Array(points.dropLast()) : points
            let count = Double(ring.count)
            return LatLng(ring.reduce(0) { $0 + $1.lat } / count, ring.reduce(0) { $0 + $1.lng } / count)
        }
    }

    public let name: String?
    public let building: [LatLng]
    public let features: [Feature]
    public var floors: [String] {
        Set(features.flatMap(\.floors)).sorted { (Double($0) ?? 0) > (Double($1) ?? 0) }
    }

    public static func contains(_ point: LatLng, ring: [LatLng]) -> Bool {
        guard ring.count >= 4 else { return false }
        var inside = false
        for (a, b) in zip(ring, ring.dropFirst()) where (a.lat > point.lat) != (b.lat > point.lat) {
            if point.lng < (b.lng - a.lng) * (point.lat - a.lat) / (b.lat - a.lat) + a.lng { inside.toggle() }
        }
        return inside
    }

    public static func near(_ place: LatLng) async -> IndoorPlan? {
        let query = """
        [out:json][timeout:10];(
          nwr["indoor"]["level"](around:170,\(place.lat),\(place.lng));
          way["building"](around:170,\(place.lat),\(place.lng));
          relation["building"]["type"="multipolygon"](around:170,\(place.lat),\(place.lng));
          nwr["shop"]["level"](around:160,\(place.lat),\(place.lng));
          nwr["amenity"~"^(toilets|restaurant|cafe|food_court|pharmacy)$"]["level"](around:160,\(place.lat),\(place.lng));
          nwr["highway"~"^(elevator|steps)$"]["level"](around:160,\(place.lat),\(place.lng));
        );out body geom 2200;
        """
        for endpoint in ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"] {
            guard !Task.isCancelled, let url = URL(string: endpoint) else { break }
            var request = URLRequest(url: url, timeoutInterval: 13)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var form = URLComponents()
            form.queryItems = [URLQueryItem(name: "data", value: query)]
            request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 { return parse(data, at: place) }
        }
        return nil
    }

    static func parse(_ data: Data, at: LatLng) -> IndoorPlan? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = root["elements"] as? [[String: Any]] else { return nil }
        func point(_ row: [String: Any]) -> LatLng? {
            guard let a = row["lat"] as? Double, let b = row["lon"] as? Double,
                  (-90...90).contains(a), (-180...180).contains(b) else { return nil }
            return LatLng(a, b)
        }
        func shapes(_ row: [String: Any]) -> [[LatLng]] {
            if let node = point(row) { return [[node]] }
            if let points = row["geometry"] as? [[String: Any]] { return [points.compactMap(point)] }
            return (row["members"] as? [[String: Any]] ?? []).filter { $0["role"] as? String == "outer" }.compactMap {
                ($0["geometry"] as? [[String: Any]])?.compactMap(point)
            }
        }
        func boundsArea(_ points: [LatLng]) -> Double {
            let lat = points.map(\.lat), lon = points.map(\.lng)
            return ((lat.max() ?? 0) - (lat.min() ?? 0)) * ((lon.max() ?? 0) - (lon.min() ?? 0))
        }
        let buildings = elements.flatMap { row -> [(String?, [LatLng])] in
            guard let tags = row["tags"] as? [String: String], tags["building"] != nil else { return [] }
            return shapes(row).filter { $0.first == $0.last && contains(at, ring: $0) }.map { (tags["name"], $0) }
        }
        guard let building = buildings.min(by: { boundsArea($0.1) < boundsArea($1.1) }) else { return nil }
        let features = elements.flatMap { row -> [Feature] in
            guard let tags = row["tags"] as? [String: String], let levels = tags["level"],
                  !["no", "private"].contains(tags["access"] ?? "") else { return [] }
            let floors: Set<String> = Set(levels.split(separator: ";").compactMap {
                Double($0.trimmingCharacters(in: .whitespaces)).flatMap {
                    $0.isFinite && abs($0) < 200 ? ($0.rounded() == $0 ? String(Int($0)) : String($0)) : nil
                }
            })
            guard !floors.isEmpty else { return [] }
            let kind = tags["shop"] != nil ? "shop" : tags["amenity"] ?? tags["highway"] ?? tags["indoor"] ?? "room"
            let fallback = ["toilets": "Toilets", "elevator": "Lift", "steps": "Stairs"][kind]
            return shapes(row).enumerated().compactMap { i, points in
                guard points.contains(where: { contains($0, ring: building.1) }) else { return nil }
                let id = "\(row["type"] ?? ""):\(row["id"] ?? ""):\(i)"
                return Feature(id: id, floors: floors, name: tags["name"] ?? tags["ref"] ?? fallback, kind: kind, points: points)
            }
        }
        guard !features.isEmpty else { return nil }
        return IndoorPlan(name: building.0, building: building.1, features: features)
    }
}
