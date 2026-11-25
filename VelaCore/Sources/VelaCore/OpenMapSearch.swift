import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OpenMapSearch {
    public static func search(_ text: String, near at: LatLng, meters: Double) async -> [Place]? {
        let query = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let category: (key: String, value: String, title: String)
        switch query {
        case "drinking water", "water fountain", "pitko", "pitka", "pitna voda":
            category = ("amenity", "drinking_water", "Drinking water")
        case "parking", "parkoviste":
            category = ("amenity", "parking", "Parking")
        case "toilets", "public toilets", "restroom", "wc", "zachody":
            category = ("amenity", "toilets", "Toilets")
        case "gas station", "gas stations", "petrol station", "petrol stations", "cerpaci stanice", "benzinka":
            category = ("amenity", "fuel", "Fuel station")
        case "ev charging", "ev charging station", "nabijeci stanice":
            category = ("amenity", "charging_station", "Charging station")
        case "coffee", "cafe", "kavarna", "kavarny":
            category = ("amenity", "cafe", "Café")
        case "restaurants", "restaurant", "restaurace":
            category = ("amenity", "restaurant", "Restaurant")
        case "supermarket", "supermarkets":
            category = ("shop", "supermarket", "Supermarket")
        case "pharmacy", "pharmacies", "lekarna", "lekarny":
            category = ("amenity", "pharmacy", "Pharmacy")
        case "bench", "benches", "lavicka", "lavicky":
            category = ("amenity", "bench", "Bench")
        case "camping", "campsites", "kemp", "kempy":
            category = ("tourism", "camp_site", "Campsite")
        default: return nil
        }
        let radius = Int(min(15_000, max(1200, meters.isFinite ? meters : 4500)))
        let data = "[out:json][timeout:9];nwr[\"\(category.key)\"=\"\(category.value)\"](around:\(radius),\(at.lat),\(at.lng));out center 120;"
        for endpoint in ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"] {
            guard !Task.isCancelled, let url = URL(string: endpoint) else { break }
            var request = URLRequest(url: url, timeoutInterval: 11)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var form = URLComponents()
            form.queryItems = [URLQueryItem(name: "data", value: data)]
            request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
            guard let (body, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let rows = root["elements"] as? [[String: Any]] else { continue }
            return rows.compactMap { row -> Place? in
                let center = row["center"] as? [String: Any] ?? row
                guard let lat = center["lat"] as? Double, let lon = center["lon"] as? Double,
                      let id = row["id"] as? Int else { return nil }
                let tags = row["tags"] as? [String: String] ?? [:]
                guard tags["access"] != "private", tags["access"] != "no" else { return nil }
                let location = LatLng(lat, lon)
                var place = Place(id: "osm:\(row["type"] ?? ""):\(id)", name: tags["name"] ?? category.title,
                                  location: location, source: "osm")
                place.category = category.title
                place.distanceMeters = at.distance(to: location)
                return place
            }.sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
        }
        return []
    }
}
