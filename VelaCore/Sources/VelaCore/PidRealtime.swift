import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Official Prague Integrated Transport data for Transitous trips from the cz-PID feed.
public enum PidRealtime {
    public struct Update: Sendable {
        public var leg: TransitLeg
        public var position: Transitous.VehiclePosition?
    }

    private final class DirectRequest: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 7
        return URLSession(configuration: config, delegate: DirectRequest(), delegateQueue: nil)
    }()

    public static func update(_ leg: TransitLeg, token: String, now: Date = Date()) async -> Update? {
        guard !token.isEmpty, let id = leg.tripID, let separator = id.range(of: "_cz-PID_"),
              let start = leg.depart, now.timeIntervalSince(start) >= -2_400,
              now.timeIntervalSince(leg.arrive ?? start) <= 900 else { return nil }
        let trip = String(id[separator.upperBound...])
        guard !trip.isEmpty else { return nil }

        async let board = departures(first: leg.calls.first, trip: trip, token: token)
        async let gps = position(trip: trip, token: token, now: now, active: now.timeIntervalSince(start) >= -60)
        let (departure, vehicle) = await (board, gps)
        guard departure != nil || vehicle != nil else { return nil }
        var actual = leg
        if let departure {
            actual.cancelled = actual.cancelled || departure.cancelled
            if let time = departure.time, let minutes = departure.delay, let first = actual.calls.first {
                actual.delayMinutes = minutes
                actual.depart = time
                actual.calls[0] = TransitCall(id: first.id, name: first.name, location: first.location,
                    arrival: first.arrival, departure: time, platform: first.platform,
                    arrivalDelay: first.arrivalDelay, departureDelay: minutes, cancelled: first.cancelled)
            }
        }
        actual.cancelled = actual.cancelled || vehicle?.cancelled == true
        return Update(leg: actual, position: actual.cancelled ? nil : vehicle?.position)
    }

    private static func fetch(_ path: String, query: [URLQueryItem] = [], token: String) async -> Any? {
        var url = URLComponents()
        url.scheme = "https"
        url.host = "api.golemio.cz"
        url.path = path
        url.queryItems = query.isEmpty ? nil : query
        guard let endpoint = url.url else { return nil }
        var request = URLRequest(url: endpoint)
        request.setValue(token, forHTTPHeaderField: "X-Access-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, reply) = try? await session.data(for: request),
              (reply as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func departures(first: TransitCall?, trip: String, token: String) async
        -> (time: Date?, delay: Int?, cancelled: Bool)? {
        guard let first, let id = first.id, id.hasPrefix("cz-PID_"), let scheduled = first.departure else { return nil }
        let query = [
            URLQueryItem(name: "stopIds", value: String(id.dropFirst("cz-PID_".count))),
            URLQueryItem(name: "limit", value: "35"),
            URLQueryItem(name: "minutesAfter", value: "50"),
            URLQueryItem(name: "minutesBefore", value: "15")
        ]
        let data = await fetch("/v2/public/departureboards", query: query, token: token)
        let entries = (data as? [Any]) ?? ((data as? [String: Any])?["departures"] as? [Any]) ?? []
        let rows = entries.flatMap { ($0 as? [Any]) ?? [$0] }.compactMap { $0 as? [String: Any] }
        let matches: [(Double, [String: Any], Date)] = rows.compactMap { row in
            guard (row["trip"] as? [String: Any])?["id"] as? String == trip,
                  let fields = row["departure"] as? [String: Any],
                  let baseline = Transitous.date(fields["timestamp_scheduled"]) else { return nil }
            let delta = abs(baseline.timeIntervalSince(scheduled))
            return delta <= 35 * 60 ? (delta, row, baseline) : nil
        }
        guard let (_, row, baseline) = matches.min(by: { $0.0 < $1.0 }) else { return nil }
        if (row["trip"] as? [String: Any])?["is_canceled"] as? Bool == true { return (nil, nil, true) }
        guard let departure = row["departure"] as? [String: Any],
              let delay = departure["delay_seconds"] as? Double, abs(delay) < 86_400 else { return nil }
        return (Transitous.date(departure["timestamp_predicted"]) ?? baseline.addingTimeInterval(delay),
                Int((delay / 60).rounded()), false)
    }

    private static func position(trip: String, token: String, now: Date, active: Bool) async
        -> (position: Transitous.VehiclePosition?, cancelled: Bool)? {
        guard active, !trip.contains("/"), let data = await fetch("/v2/vehiclepositions/\(trip)", token: token) as? [String: Any],
              let properties = data["properties"] as? [String: Any], let summary = properties["trip"] as? [String: Any],
              (summary["gtfs"] as? [String: Any])?["trip_id"] as? String == trip,
              let last = properties["last_position"] as? [String: Any], let timestamp = Transitous.date(last["origin_timestamp"]),
              (-10...120).contains(now.timeIntervalSince(timestamp)) else { return nil }
        if last["is_canceled"] as? Bool == true { return (nil, true) }
        guard let geometry = data["geometry"] as? [String: Any], geometry["type"] as? String == "Point",
              let coords = geometry["coordinates"] as? [Double], coords.count >= 2,
              (-180...180).contains(coords[0]), (-90...90).contains(coords[1]) else { return nil }
        return (Transitous.VehiclePosition(location: LatLng(coords[1], coords[0]), isGPS: true,
                                          occupancy: last["occupancy_status"] as? String), false)
    }
}
