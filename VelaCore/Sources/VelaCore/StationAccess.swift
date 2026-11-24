import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct StationEntrance: Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String
    public let location: LatLng
    public let wheelchair: Bool?
}

public enum StationAccess {
    public static func entrances(near at: LatLng) async -> [StationEntrance] {
        let query = """
        [out:json][timeout:8];(
          node["railway"="subway_entrance"](around:320,\(at.lat),\(at.lng));
          node["railway"="train_station_entrance"](around:240,\(at.lat),\(at.lng));
          node["public_transport"="entrance"](around:240,\(at.lat),\(at.lng));
        );out 50;
        """
        for endpoint in ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"] {
            guard !Task.isCancelled, let url = URL(string: endpoint) else { break }
            var request = URLRequest(url: url, timeoutInterval: 12)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var form = URLComponents()
            form.queryItems = [URLQueryItem(name: "data", value: query)]
            request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = root["elements"] as? [[String: Any]] else { continue }
            let entrances = items.compactMap { row -> StationEntrance? in
                guard let id = row["id"] as? Int, let lat = row["lat"] as? Double, let lon = row["lon"] as? Double,
                      let tags = row["tags"] as? [String: String], !["no", "private", "customers"].contains(tags["access"] ?? "") else { return nil }
                let ref = tags["ref"].map { "Entrance \($0)" }
                let accessible = tags["wheelchair"].flatMap { $0 == "yes" ? true : $0 == "no" ? false : nil }
                return StationEntrance(id: id, title: tags["name"] ?? ref ?? "Station entrance",
                                       location: LatLng(lat, lon), wheelchair: accessible)
            }
            return Array(entrances.sorted { $0.location.distance(to: at) < $1.location.distance(to: at) }.prefix(12))
        }
        return []
    }
}
