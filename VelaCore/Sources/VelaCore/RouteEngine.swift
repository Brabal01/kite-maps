import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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

public enum MapboxRoutes {
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
        return parse(data, mode: mode)
    }

    static func parse(_ data: Data, mode: TravelMode) -> [Route] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["code"] as? String == "Ok" else { return [] }
        return OSRM.parse(data, mode: mode, source: "mapbox")
    }

    static func trafficSpans(_ legs: [[String: Any]], cumulative: [Double]) -> [TrafficSpan] {
        let congestion = legs.flatMap { leg -> [Any] in
            let annotation = leg["annotation"] as? [String: Any]
            return annotation?["congestion"] as? [Any] ?? []
        }
        guard congestion.count == cumulative.count - 1 else { return [] }
        let levels = congestion.map { value in
            switch value as? String {
            case "moderate": return 1
            case "heavy": return 2
            case "severe": return 3
            default: return 0
            }
        }
        var spans: [TrafficSpan] = []
        var start = 0
        while start < levels.count {
            var end = start + 1
            while end < levels.count && levels[end] == levels[start] { end += 1 }
            let distance = cumulative[end] - cumulative[start]
            if levels[start] > 0, distance > 0 {
                spans.append(TrafficSpan(level: levels[start], startMeters: cumulative[start], lengthMeters: distance))
            }
            start = end
        }
        return spans
    }

    /// Replace live traffic only on the portion of the current route that matches the fresh geometry.
    public static func refreshedTraffic(line: [LatLng], previous: [TrafficSpan],
                                        fresh: Route, from: Double) -> [TrafficSpan]? {
        guard fresh.source == "mapbox", line.count >= 2, fresh.polyline.count >= 2 else { return nil }
        let routeDistances = Geo.cumulative(line)
        let freshDistances = Geo.cumulative(fresh.polyline)
        let measuredEnd = fresh.trafficSpans.map { $0.startMeters + $0.lengthMeters }.max() ?? 0
        let distance = min(max(4500, measuredEnd), 16_000, freshDistances.last ?? 0)
        guard distance >= 60 else { return nil }
        let origin = max(0, from - 300)
        let window = Geo.slice(line, from: origin, to: min(routeDistances.last ?? 0, from + distance + 300),
                               cumulative: routeDistances)
        guard window.count >= 2 else { return nil }
        let windowDistances = Geo.cumulative(window)
        let begin = Geo.project(fresh.polyline[0], on: window, cumulative: windowDistances)
        guard begin.offset <= 22, abs(begin.along + origin - from) <= 160 else { return nil }

        let count = Int(ceil(distance / 150))
        var end = 0.0
        var lastMatch = begin.along
        for index in 1...count {
            let meters = distance * Double(index) / Double(count)
            let position = Geo.point(along: fresh.polyline, meters: meters, cumulative: freshDistances)
            let match = Geo.project(position, on: window, cumulative: windowDistances)
            guard match.offset <= 22, match.along >= lastMatch, abs(match.along - begin.along - meters) <= 140 else { break }
            end = meters
            lastMatch = match.along
        }
        guard end + 0.01 >= min(4500, distance) else { return nil }
        let first = begin.along + origin
        let last = lastMatch + origin
        let retained: [TrafficSpan] = previous.flatMap { span in
            let end = span.startMeters + span.lengthMeters
            let before = min(end, first) - span.startMeters
            let afterStart = max(span.startMeters, last)
            return [
                before > 0 ? TrafficSpan(level: span.level, startMeters: span.startMeters, lengthMeters: before) : nil,
                end > afterStart ? TrafficSpan(level: span.level, startMeters: afterStart, lengthMeters: end - afterStart) : nil
            ].compactMap { $0 }
        }
        let updated: [TrafficSpan] = fresh.trafficSpans.compactMap { span in
            guard span.startMeters < end else { return nil }
            let factor = (last - first) / end
            return TrafficSpan(level: span.level, startMeters: first + span.startMeters * factor,
                               lengthMeters: min(span.lengthMeters, end - span.startMeters) * factor)
        }
        return (retained + updated).sorted { $0.startMeters < $1.startMeters }
    }

}
