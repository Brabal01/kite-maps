import Foundation

public enum VignetteRoads {
    /// Czech toll-tagged motorway sections whose mapped geometry agrees with the selected route.
    /// This is positive-only: an empty response is never evidence that the drive is exempt.
    public static func czechMotorways(on line: [LatLng], avoidingTolls: Bool = false) async -> [String] {
        guard line.count >= 2, line.contains(where: { (48.5...51.1).contains($0.lat) && (12...19).contains($0.lng) }) else { return [] }
        return CzechVignetteMap.roads(on: line, maxOffset: avoidingTolls ? 18 : 26)
    }

    private static func elements(_ data: Data) -> [[String: Any]]? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["elements"] as? [[String: Any]]
    }
}

extension VignetteRoads {
    public static func hasLocallyKnownToll(on line: [LatLng], avoidingTolls: Bool = false) -> Bool {
        !CzechVignetteMap.roads(on: line, maxOffset: avoidingTolls ? 18 : 26).isEmpty ||
            !RoadCharges.on(line).isEmpty
    }

    /// Check every route separately: the request flag is only a router preference.
    static func verifiedTollFree(_ routes: [Route]) async -> (routes: [Route], anyTolled: Bool) {
        await withTaskGroup(of: (Int, Bool?).self) { group in
            for (index, route) in routes.enumerated() {
                group.addTask {
                    if hasLocallyKnownToll(on: route.polyline, avoidingTolls: true) { return (index, true) }
                    if let status = route.routerReportedTolls { return (index, status) }
                    let status = await deadline(10) { await Valhalla.verifiedToll(on: route.polyline) }
                    return (index, status ?? nil)
                }
            }
            var free: [Int] = []
            var paid = false
            for await (index, status) in group {
                if status == false { free.append(index) }
                if status == true { paid = true }
            }
            return (free.sorted().map { index in
                var route = routes[index]
                route.routerReportedTolls = false
                return route
            }, paid)
        }
    }

    /// Positive matches only. Incomplete map tags never mean a route is toll-free.
    public static func hasMappedToll(on line: [LatLng], avoidingTolls: Bool = false) async -> Bool {
        guard line.count >= 2 else { return false }
        if hasLocallyKnownToll(on: line, avoidingTolls: avoidingTolls) { return true }
        if avoidingTolls { return await mappedToll(on: line) }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { await Valhalla.toll(on: line) }
            group.addTask { await mappedToll(on: line) }
            for await found in group where found {
                group.cancelAll()
                return true
            }
            return false
        }
    }

    private static func mappedToll(on line: [LatLng]) async -> Bool {
        let locale = Locale(identifier: "en_US_POSIX")
        for piece in Overpass.pieces(line, meters: 60_000) {
            if Task.isCancelled { return false }
            let step = max(1, (piece.count + 179) / 180)
            let samples = stride(from: 0, to: piece.count, by: step).map { piece[$0] } + [piece[piece.count - 1]]
            let coordinates = samples.map { String(format: "%.5f,%.5f", locale: locale, $0.lat, $0.lng) }.joined(separator: ",")
            let query = """
            [out:json][timeout:14];
            (
              way["highway"]["toll"="yes"]["toll:motorcar"!="no"]["toll:motor_vehicle"!="no"](around:22,\(coordinates));
              way["highway"]["toll:motorcar"="yes"](around:22,\(coordinates));
              way["highway"]["toll:motor_vehicle"="yes"]["toll:motorcar"!="no"](around:22,\(coordinates));
              way["highway"]["toll:forward"="yes"](around:22,\(coordinates));
              way["highway"]["toll:backward"="yes"](around:22,\(coordinates));
            );
            out geom 400;
            """
            guard let data = await Overpass.firstAnswer(query, stagger: 4, valid: { elements($0) != nil }) else { continue }
            if containsToll(elements(data) ?? [], on: piece) { return true }
        }
        return false
    }

    static func containsToll(_ ways: [[String: Any]], on line: [LatLng]) -> Bool {
        let routeDistances = Geo.cumulative(line)
        guard line.count >= 2 else { return false }
        for way in ways {
            let tags = way["tags"] as? [String: String] ?? [:]
            let vehicle = tags["toll:motorcar"] ?? tags["toll:motor_vehicle"]
            let general = tags["toll"] == "yes"
            let forward = vehicle.map { $0 == "yes" } ?? (tags["toll:forward"].map { $0 == "yes" } ?? general)
            let backward = vehicle.map { $0 == "yes" } ?? (tags["toll:backward"].map { $0 == "yes" } ?? general)
            guard forward || backward else { continue }
            guard let geometry = way["geometry"] as? [[String: Double]] else { continue }
            let points = geometry.compactMap { item -> LatLng? in
                guard let lat = item["lat"], let lng = item["lon"] else { return nil }
                return LatLng(lat, lng)
            }
            guard points.count >= 2 else { continue }
            let distances = Geo.cumulative(points)
            guard let length = distances.last, length >= 30 else { continue }
            let samples = max(3, min(160, Int(ceil(length / 20))))
            let interval = length / Double(samples)
            let requiredOverlap = min(55, length * 0.8)
            var previous: Double?
            var run = 0.0
            for index in 0...samples {
                let point = Geo.point(along: points, meters: Double(index) * interval, cumulative: distances)
                let match = Geo.project(point, on: line, cumulative: routeDistances)
                guard match.offset <= 8 else {
                    previous = nil
                    run = 0
                    continue
                }
                if let previous {
                    let delta = match.along - previous
                    let eligible = delta > 0 ? forward : backward
                    if eligible && (0.8 * interval...1.2 * interval).contains(abs(delta)) {
                        run = run * delta >= 0 ? run + delta : delta
                        if abs(run) >= requiredOverlap { return true }
                    } else {
                        run = 0
                    }
                }
                previous = match.along
            }
        }
        return false
    }
}
