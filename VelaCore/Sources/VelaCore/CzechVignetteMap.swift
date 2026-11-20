import Foundation

enum CzechVignetteMap {
    private struct Record: Decodable {
        let road: String
        let points: [[Double]]
    }

    private struct Bounds {
        let south: Double, north: Double, west: Double, east: Double

        init(_ points: [LatLng]) {
            let lat = points.map(\.lat), lng = points.map(\.lng)
            south = lat.min() ?? 0
            north = lat.max() ?? 0
            west = lng.min() ?? 0
            east = lng.max() ?? 0
        }

        func isNear(_ other: Bounds) -> Bool {
            south <= other.north + 0.001 && north >= other.south - 0.001 &&
            west <= other.east + 0.001 && east >= other.west - 0.001
        }
    }

    private struct Section {
        let road: String
        let line: [LatLng]
        let bounds: Bounds
    }

    // eDalnice's official 2026 paid network, simplified within 5 m before rounding.
    // https://edalnice.gov.cz/geodata/2026/paid.json
    private static let sections: [Section] = {
        guard let url = Bundle.module.url(forResource: "cz-vignette-2026", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        return records.compactMap { record in
            let line = record.points.compactMap { point in
                point.count == 2 ? LatLng(point[0], point[1]) : nil
            }
            guard line.count >= 2 else { return nil }
            return Section(road: record.road, line: line, bounds: Bounds(line))
        }
    }()

    static func roads(on route: [LatLng], maxOffset: Double = 26) -> [String] {
        guard route.count >= 2 else { return [] }
        let bounds = Bounds(route)
        let candidates = sections.filter { $0.bounds.isNear(bounds) }
        guard !candidates.isEmpty else { return [] }
        let nearby = NearLine(route)
        var roads: Set<String> = []
        for section in candidates where !roads.contains(section.road) {
            if follows(section.line, route: nearby, maxOffset: maxOffset) { roads.insert(section.road) }
        }
        return roads.sorted()
    }

    private static func follows(_ section: [LatLng], route: NearLine, maxOffset: Double) -> Bool {
        let cumulative = Geo.cumulative(section)
        let step = 35.0
        var previous: Double?
        var run = 0.0
        for meters in stride(from: 0.0, through: cumulative.last ?? 0, by: step) {
            let point = Geo.point(along: section, meters: meters, cumulative: cumulative)
            let match = route.project(point)
            // Allow for the opposite carriageway, and require continuous progress in either
            // direction so that nearby crossings and the ends of free sections don't count.
            guard match.offset <= maxOffset else {
                previous = nil
                run = 0
                continue
            }
            if let previous {
                let delta = match.along - previous
                if (step * 0.75...step * 1.35).contains(abs(delta)) {
                    run = run * delta > 0 ? run + delta : delta
                    if abs(run) >= 85 { return true }
                } else {
                    run = 0
                }
            }
            previous = match.along
        }
        return false
    }
}
