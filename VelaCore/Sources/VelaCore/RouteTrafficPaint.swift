import Foundation

public enum RouteTrafficPaint {
    public struct Segment: Equatable {
        public let from: Double
        public let to: Double
        public let level: Int
    }

    /// Split the remaining centerline into nonoverlapping stretches, using the worst active level.
    public static func ranges(from: Double, to: Double, traffic: [TrafficSpan]) -> [Segment] {
        guard from.isFinite, to.isFinite, to > from else { return [] }
        var changes: [Double: [(level: Int, count: Int)]] = [from: [], to: []]
        for span in traffic where span.level > 0 {
            guard span.startMeters.isFinite, span.lengthMeters.isFinite else { continue }
            let start = max(from, span.startMeters)
            let end = min(to, span.startMeters + span.lengthMeters)
            guard end > start else { continue }
            let level = min(3, span.level)
            changes[start, default: []].append((level, 1))
            changes[end, default: []].append((level, -1))
        }

        var active = [0, 0, 0, 0]
        var previous = from
        var segments: [Segment] = []
        for point in changes.keys.sorted() {
            if point > previous {
                let level = active.lastIndex(where: { $0 > 0 }) ?? 0
                let start = segments.last?.level == level ? segments.removeLast().from : previous
                segments.append(Segment(from: start, to: point, level: level))
            }
            for delta in changes[point, default: []] {
                active[delta.level] += delta.count
            }
            previous = point
        }
        return segments
    }
}
