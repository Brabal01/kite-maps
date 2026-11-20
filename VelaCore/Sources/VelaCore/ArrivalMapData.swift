import Foundation

public enum ArrivalMapData {
    public static func parking(near point: LatLng) async -> [Place] {
        let at = coordinates(point)
        let query = """
        [out:json][timeout:12];
        nwr["amenity"="parking"]["access"~"^(public|yes|customers)$"](around:900,\(at));
        out center 35;
        """
        guard let data = await Overpass.firstAnswer(query, stagger: 4, valid: { elements($0) != nil }) else { return [] }
        return (elements(data) ?? []).compactMap { item -> Place? in
            guard let id = item["id"] as? Int64, let type = item["type"] as? String,
                  let tags = item["tags"] as? [String: String],
                  tags["motor_vehicle"] != "no", tags["motorcar"] != "no",
                  let coordinate = location(item["center"] as? [String: Any] ?? item) else { return nil }
            return Place(id: "parking-\(type)-\(id)", name: tags["name"] ?? "Parking (\(Int(coordinate.distance(to: point))) m away)",
                         location: coordinate, source: "osm")
        }.sorted { $0.location.distance(to: point) < $1.location.distance(to: point) }
    }

    public static func entrance(near point: LatLng) async -> LatLng? {
        let at = coordinates(point)
        let query = """
        [out:json][timeout:12];
        way["building"](around:30,\(at))->.buildings;
        .buildings out body geom 30;
        node(w.buildings)["entrance"="main"] out body 25;
        """
        guard let data = await Overpass.firstAnswer(query, stagger: 4, valid: { elements($0) != nil }),
              let elements = elements(data),
              let building = elements.first(where: { item in
                  guard let geometry = item["geometry"] as? [[String: Any]] else { return false }
                  return contains(point, polygon: geometry.compactMap(location))
              }), let ids = building["nodes"] as? [Int64] else { return nil }
        let entrances = elements.compactMap { item -> LatLng? in
            guard item["type"] as? String == "node", let id = item["id"] as? Int64, ids.contains(id),
                  let tags = item["tags"] as? [String: String], tags["access"] != "private", tags["access"] != "no" else { return nil }
            return location(item)
        }
        return entrances.min { $0.distance(to: point) < $1.distance(to: point) }
    }

    private static func contains(_ point: LatLng, polygon: [LatLng]) -> Bool {
        guard polygon.count >= 4, polygon.first == polygon.last else { return false }
        return zip(polygon, polygon.dropFirst()).reduce(false) { inside, edge in
            let (a, b) = edge
            guard (a.lat > point.lat) != (b.lat > point.lat) else { return inside }
            let crossing = a.lng + (b.lng - a.lng) * (point.lat - a.lat) / (b.lat - a.lat)
            return point.lng < crossing ? !inside : inside
        }
    }

    private static func coordinates(_ point: LatLng) -> String {
        String(format: "%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"), point.lat, point.lng)
    }

    private static func elements(_ data: Data) -> [[String: Any]]? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["elements"] as? [[String: Any]]
    }

    private static func location(_ item: [String: Any]) -> LatLng? {
        guard let lat = item["lat"] as? Double, let lon = item["lon"] as? Double else { return nil }
        return LatLng(lat, lon)
    }
}
