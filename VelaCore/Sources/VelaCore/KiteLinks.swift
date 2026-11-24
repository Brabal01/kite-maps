import Foundation

public enum KiteLinks {
    public enum Target: Equatable, Sendable {
        case map
        case search(String?)
        case place(LatLng, name: String?, directions: Bool)
        case shortcut(String)
        case home
        case work
        case car
    }

    public static func parse(_ url: URL) -> Target? {
        guard url.absoluteString.utf8.count <= 4096,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "kite", let host = parts.host?.lowercased(),
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              parts.percentEncodedPath.isEmpty || parts.percentEncodedPath == "/" else { return nil }

        var parameters: [String: String] = [:]
        for item in parts.queryItems ?? [] {
            guard parameters[item.name] == nil else { return nil }
            parameters[item.name] = item.value ?? ""
        }
        switch host {
        case "map": return .map
        case "search": return .search(label(parameters["q"], limit: 300))
        case "home": return .home
        case "work": return .work
        case "car": return .car
        case "shortcut":
            guard let id = parameters["id"], id.count <= 100,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return .shortcut(id)
        case "place", "directions":
            guard let lat = parameters["lat"].flatMap({ Double($0) }), (-90...90).contains(lat),
                  let lng = parameters["lng"].flatMap({ Double($0) }), (-180...180).contains(lng) else { return nil }
            return .place(LatLng(lat, lng), name: label(parameters["name"], limit: 100), directions: host == "directions")
        default: return nil
        }
    }

    public static func placeURL(at point: LatLng, name: String, directions: Bool = false) -> URL? {
        guard (-90...90).contains(point.lat), (-180...180).contains(point.lng) else { return nil }
        var parts = URLComponents()
        parts.scheme = "kite"
        parts.host = directions ? "directions" : "place"
        parts.queryItems = [
            URLQueryItem(name: "lat", value: String(point.lat)),
            URLQueryItem(name: "lng", value: String(point.lng)),
            URLQueryItem(name: "name", value: label(name, limit: 100))
        ]
        return parts.url
    }

    private static func label(_ value: String?, limit: Int) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return String(value.prefix(limit))
    }
}
