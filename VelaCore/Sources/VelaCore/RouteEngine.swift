import Foundation

public enum RouteEngine: String, CaseIterable, Identifiable, Sendable {
    case automatic, openStreetMap, mapbox, google
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .openStreetMap: return "OpenStreetMap"
        case .mapbox: return "Mapbox"
        case .google: return "Google"
        }
    }

    public static func isMapboxPublicToken(_ token: String) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "pk" else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        return parts.dropFirst().allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }
    }
}

enum MapboxRoutes {
    static func plan(from: LatLng, to: LatLng, via: [LatLng], mode: TravelMode,
                     heading: Double?, alternatives: Bool, avoidHighways: Bool, avoidTolls: Bool, token: String) async -> [Route] {
        guard RouteEngine.isMapboxPublicToken(token), via.count <= 23 else { return [] }
        let profile = mode == .drive ? "driving-traffic" : mode == .walk ? "walking" : "cycling"
        let points = ([from] + via + [to]).map { "\($0.lng.plain),\($0.lat.plain)" }.joined(separator: ";")
        var url = URLComponents(string: "https://api.mapbox.com/directions/v5/mapbox/\(profile)/\(points)")
        var query = ["access_token": token, "overview": "full", "geometries": "polyline6", "steps": "true",
                     "roundabout_exits": "true", "alternatives": alternatives ? "true" : "false"]
        if mode == .drive {
            query["annotations"] = "congestion,maxspeed"
            let exclusions = [avoidHighways ? "motorway" : nil, avoidTolls ? "toll" : nil].compactMap { $0 }
            if !exclusions.isEmpty { query["exclude"] = exclusions.joined(separator: ",") }
            if let heading, heading.isFinite {
                let degrees = (Int(heading.rounded()) % 360 + 360) % 360
                query["bearings"] = "\(degrees),60" + String(repeating: ";", count: via.count + 1)
            }
        }
        url?.queryItems = query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let endpoint = url?.url else { return [] }
        let request = URLRequest(url: endpoint, timeoutInterval: 10)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return OSRM.parse(data, mode: mode)
    }
}
