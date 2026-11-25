import Foundation

public struct RouteStopCandidate: Identifiable, Sendable {
    public let place: Place
    public let ahead: Double?
    public let offset: Double
    public let routeMeters: Double?
    public var id: String { place.id }
}

/// The remaining corridor during guidance, or the entire selected route in the planner.
public struct RouteStopSearch: Sendable {
    private let origin: LatLng
    private let start: Double
    private let end: Double
    private let active: Bool
    private let track: [LatLng]
    private let distances: [Double]
    private let window: [LatLng]
    private let windowDistances: [Double]

    public init(line: [LatLng], origin: LatLng, progress: Double? = nil) {
        self.origin = origin
        active = progress != nil
        track = line
        distances = Geo.cumulative(line)
        let total = distances.last ?? 0
        start = max(0, min(total, progress ?? 0))
        end = active ? min(total, start + 42_000) : total
        window = line.count >= 2 ? Geo.slice(line, from: start, to: end, cumulative: distances) : []
        windowDistances = Geo.cumulative(window)
    }

    var centers: [(point: LatLng, span: Double)] {
        let span = end - start
        guard span > 1 else { return [(origin, 4_000)] }
        let count = max(1, min(active ? 3 : 72, Int(ceil(span / (active ? 14_000 : 27_000)))))
        return (0..<count).map { index in
            (Geo.point(along: track, meters: start + span * (Double(index) + 0.5) / Double(count), cumulative: distances),
             max(4_000, span / Double(count) * 1.65))
        }
    }

    public func search(_ query: String, named: Bool, useGoogle: Bool, excluding: [Place], draft: Bool = false) async -> [RouteStopCandidate] {
        let locations = centers
        let searchAreas: [(point: LatLng, span: Double)]
        if draft, locations.count > 3 {
            searchAreas = [locations[0], locations[locations.count / 2], locations[locations.count - 1]]
        } else {
            searchAreas = locations
        }
        var places: [Place] = []
        for start in stride(from: 0, to: searchAreas.count, by: 4) {
            if Task.isCancelled { return [] }
            let end = min(start + 4, searchAreas.count)
            let batch = await withTaskGroup(of: (Int, [Place]).self) { group in
                for index in start..<end {
                    let area = searchAreas[index]
                    group.addTask {
                        let places = await Self.find(query, named: named, useGoogle: useGoogle, at: area.point, span: area.span)
                        return (index, places)
                    }
                }
                var pages: [(Int, [Place])] = []
                for await result in group { pages.append(result) }
                return pages.sorted { $0.0 < $1.0 }.flatMap { $0.1 }
            }
            places += batch
        }
        return candidates(places, named: named, excluding: excluding)
    }

    func candidates(_ places: [Place], named: Bool, excluding: [Place]) -> [RouteStopCandidate] {
        let span = end - start
        let candidates: [RouteStopCandidate] = places.compactMap { place in
            guard !excluding.contains(where: place.matchesNearby) else { return nil }
            if span <= 1 || window.count < 2 {
                let distance = origin.distance(to: place.location)
                return !active && distance < 3_500 ? RouteStopCandidate(place: place, ahead: nil, offset: distance, routeMeters: nil) : nil
            }
            let position = Geo.project(place.location, on: window, cumulative: windowDistances)
            guard position.offset <= (named ? 5_000 : 2_200) else { return nil }
            if active {
                guard position.along >= 30 else { return nil }
                if position.along >= span - 1, end < (distances.last ?? 0) {
                    let full = Geo.project(place.location, on: track, cumulative: distances)
                    if full.along > end { return nil }
                }
            }
            return RouteStopCandidate(place: place, ahead: position.along, offset: position.offset, routeMeters: start + position.along)
        }
        let ordered: [RouteStopCandidate]
        if active || span <= 42_000 {
            ordered = candidates.sorted { rank($0) < rank($1) }
        } else {
            let width = max(28_000, span / 30)
            let bands = Dictionary(grouping: candidates) { Int(($0.ahead ?? 0) / width) }
            ordered = bands.keys.sorted().flatMap { band in
                unique((bands[band] ?? []).sorted { $0.offset < $1.offset }, limit: 3)
                    .sorted { ($0.ahead ?? 0) < ($1.ahead ?? 0) }
            }
        }
        return unique(ordered, limit: 100)
    }

    private func rank(_ candidate: RouteStopCandidate) -> Double {
        (candidate.ahead ?? 0) + 3 * candidate.offset
    }

    private func unique(_ sorted: [RouteStopCandidate], limit: Int) -> [RouteStopCandidate] {
        var output: [RouteStopCandidate] = []
        for candidate in sorted where !output.contains(where: { $0.place.matchesNearby(candidate.place) }) {
            output.append(candidate)
            if output.count == limit { break }
        }
        return output
    }

    public func drivingDetours(_ candidates: [RouteStopCandidate]) async -> [String: Double] {
        let candidates = Array(candidates.filter { $0.routeMeters != nil }.prefix(8))
        guard !candidates.isEmpty, end - start > 1 else { return [:] }
        let from = Geo.point(along: track, meters: start, cumulative: distances)
        let rejoin = candidates.map { Geo.point(along: track, meters: min(end, ($0.routeMeters ?? start) + 1_200), cumulative: distances) }
        guard let times = await OSRM.detours(from: from, places: candidates.map(\.place.location), rejoin: rejoin) else { return [:] }
        return zip(candidates, times).reduce(into: [:]) { output, pair in
            if let seconds = pair.1 { output[pair.0.id] = seconds }
        }
    }

    public static func insertionIndex(for position: Double, among stops: [Place], on line: [LatLng]) -> Int {
        let cumulative = Geo.cumulative(line)
        return stops.firstIndex { Geo.project($0.location, on: line, cumulative: cumulative).along > position } ?? stops.count
    }

    private static func find(_ query: String, named: Bool, useGoogle: Bool, at point: LatLng, span: Double) async -> [Place] {
        if !named {
            if useGoogle, let places = try? await GoogleClient.shared.search(query, center: point, spanMeters: span), !places.isEmpty {
                return places
            }
            if let places = await OpenMapSearch.search(query, near: point, meters: span * 0.5), !places.isEmpty { return places }
            return await PlaceSearch.search(query, center: point, spanMeters: span, useGoogle: false).places
        }
        let radius = max(4_000, min(19_000, span * 0.8))
        async let open = (try? Photon.search(query, near: point, limit: 35)) ?? []
        async let google = useGoogle ? (try? GoogleClient.shared.search(query, center: point, spanMeters: span, pages: 1)) ?? [] : []
        let results = await (google, open)
        return (results.0 + results.1).filter { point.distance(to: $0.location) <= radius }
    }
}
