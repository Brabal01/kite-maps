import Foundation

/**
 * Where the number in "take the 3rd exit" comes from. A number is only as good as the evidence
 * behind it: the route's own geometry through a complete OpenStreetMap roundabout beats a
 * router's step, which in turn beats a second provider's text.
 */
public enum RoundaboutExitSource: String, Hashable, Sendable {
    /// Counted from the roundabout's mapped topology and the route's own way off it.
    case osmTopology = "osm-topology"
    /// The topology and the router agree, which is the strongest answer available.
    case routerCorroborated = "router+osm"
    /// Only the router said a number; the map couldn't confirm it.
    case router = "router"
    /// Only a second provider (Google's text) said a number.
    case google = "google"
    /// The sources disagree and nothing in the map settles it.
    case ambiguous = "ambiguous"
    /// No source could say.
    case unavailable = "unavailable"
}

/** The evidence a roundabout's exit number is decided from. */
struct RoundaboutExitEvidence: Sendable {
    /** Where the route meets the circle. */
    public var entry: LatLng
    /** Where the route comes off the circle, when the router or the line says. */
    public var exitPoint: LatLng?
    public var line: [LatLng]
    public var cumulative: [Double]
    /** The route distance at which it enters the circle. */
    public var along: Double
    /** Traffic goes round clockwise (Britain, Ireland, Japan…). */
    public var clockwise: Bool
    /** The number the routing provider gave, if any. */
    public var routerExit: Int?
    /** A number from a second provider's words, if any. */
    public var googleExit: Int?
    /** OpenStreetMap ways around the roundabout. */
    public var ways: [Roundabouts.Way]

    init(entry: LatLng, exitPoint: LatLng?, line: [LatLng], cumulative: [Double], along: Double,
         clockwise: Bool, routerExit: Int?, googleExit: Int?, ways: [Roundabouts.Way]) {
        self.entry = entry
        self.exitPoint = exitPoint
        self.line = line
        self.cumulative = cumulative
        self.along = along
        self.clockwise = clockwise
        self.routerExit = routerExit
        self.googleExit = googleExit
        self.ways = ways
    }
}

/** One authoritative answer, with the reasoning kept for the developer diagnostics. */
public struct RoundaboutExitResolution: Hashable, Sendable {
    /** The number to say and draw, or nil when no number can be trusted. */
    public var exit: Int?
    public var source: RoundaboutExitSource
    /** 0…1. Below 0.7 the number is a best guess, not a confirmed one. */
    public var confidence: Double
    /** True when two sources or two mapped roads disagree and the map cannot settle it. */
    public var ambiguous: Bool
    /** How many legally usable exits the count found (0 when the map didn't say). */
    public var eligibleExits: Int
    /** Which eligible exit the route takes, zero-based. */
    public var chosenIndex: Int?
    /** The picture to draw, when the topology was good enough to build one. */
    public var shape: RoundaboutShape?
    public var routerExit: Int?
    public var osmExit: Int?
    public var googleExit: Int?
    public var reason: String
    public var entryWayID: Int64?
    public var exitWayID: Int64?
    /** Why mapped roads were left out of the count, for diagnostics. */
    public var rejected: [String]

    public var isCertain: Bool { exit != nil && !ambiguous && confidence >= 0.7 }

    public static func unavailable(_ reason: String, router: Int? = nil, google: Int? = nil) -> RoundaboutExitResolution {
        RoundaboutExitResolution(exit: nil, source: .unavailable, confidence: 0, ambiguous: false,
                                 eligibleExits: 0, chosenIndex: nil, shape: nil, routerExit: router,
                                 osmExit: nil, googleExit: google, reason: reason,
                                 entryWayID: nil, exitWayID: nil, rejected: [])
    }
}

/**
 * Decides which exit of a roundabout a route really takes.
 *
 * The router's `exit` number is not trusted on its own. The resolver rebuilds the roundabout from
 * OpenStreetMap — the ring, every road that meets it, whether traffic may leave by each one — and
 * counts only the exits that are legally usable in the direction of travel. The route's own line
 * says which of those it takes. Only when the map cannot answer does the router's number stand,
 * and when two known numbers conflict the resolver refuses to invent certainty.
 */
public enum RoundaboutExitResolver {
    /** A road meeting the circle, in the resolver's own terms. */
    struct Arm {
        var angle: Double
        var canExit: Bool
        var canEnter: Bool
        var wayID: Int64
        var name: String?
        var isService: Bool
        var layer: Int
    }

    struct Topology {
        var center: LatLng
        var radius: Double
        var ringWayIDs: [Int64]
        var entryAngle: Double
        var entryArm: Arm?
        var exits: [Arm]
        var inOnly: [Double]
        var exitAngles: [Double]
        var taken: Int?
        var exitAngleGap: Double
        var complete: Bool
        var ambiguous: Bool
        var rejected: [String]
        var exitWayID: Int64?
    }

    static func resolve(_ e: RoundaboutExitEvidence) -> RoundaboutExitResolution {
        let router = e.routerExit.flatMap { $0 > 0 ? $0 : nil }
        let google = e.googleExit.flatMap { $0 > 0 ? $0 : nil }
        guard let topo = topology(e) else {
            return withoutTopology(router: router, google: google,
                                   reason: "No mapped roundabout topology at the entry")
        }
        guard let taken = topo.taken else {
            // The map knows the circle but not which arm the route leaves by.
            var out = withoutTopology(router: router, google: google,
                                      reason: "The route's way off the circle could not be matched")
            out.eligibleExits = topo.exits.count
            out.osmExit = nil
            out.entryWayID = topo.entryArm?.wayID
            out.rejected = topo.rejected
            return out
        }
        let osmExit = taken + 1
        var confidence = 0.86
        if !topo.complete { confidence -= 0.25 }
        if topo.exitAngleGap > 30 { confidence -= 0.18 }
        if topo.ambiguous { confidence -= 0.22 }
        if topo.exits.count < 2 { confidence -= 0.12 }
        if router == osmExit { confidence += 0.07 }
        if google == osmExit { confidence += 0.04 }
        confidence = min(0.98, max(0.2, confidence))

        let shape = RoundaboutShape(exits: topo.exitAngles, taken: taken, entriesOnly: topo.inOnly,
                                    clockwise: e.clockwise, complete: topo.complete)
        var source: RoundaboutExitSource
        var reason: String
        var ambiguous = topo.ambiguous
        var finalExit: Int? = osmExit
        if confidence >= 0.65 {
            if router == osmExit {
                source = .routerCorroborated
                reason = "OpenStreetMap and the router both count \(osmExit)"
            } else if let router {
                source = .osmTopology
                reason = "OpenStreetMap counts \(osmExit); the router said \(router)"
            } else {
                source = .osmTopology
                reason = "OpenStreetMap counts \(osmExit)"
            }
        } else if let router {
            // The map is too uncertain to overrule a router that did give a number.
            if router == osmExit {
                source = .routerCorroborated
                finalExit = router
                reason = "Weak map match agrees with the router's \(router)"
            } else {
                source = .ambiguous
                ambiguous = true
                finalExit = nil
                reason = "Weak map match (\(osmExit)) conflicts with the router's \(router)"
            }
        } else if let google, google != osmExit {
            source = .ambiguous
            ambiguous = true
            finalExit = nil
            reason = "Weak map match (\(osmExit)) conflicts with Google's \(google)"
        } else {
            source = .osmTopology
            reason = "OpenStreetMap counts \(osmExit), with a weak match"
        }

        return RoundaboutExitResolution(exit: finalExit, source: source, confidence: confidence,
                                        ambiguous: ambiguous, eligibleExits: topo.exits.count,
                                        chosenIndex: taken, shape: shape, routerExit: router,
                                        osmExit: osmExit, googleExit: google, reason: reason,
                                        entryWayID: topo.entryArm?.wayID, exitWayID: topo.exitWayID,
                                        rejected: topo.rejected)
    }

    static func withoutTopology(router: Int?, google: Int?, reason: String) -> RoundaboutExitResolution {
        switch (router, google) {
        case let (r?, g?) where r == g:
            return RoundaboutExitResolution(exit: r, source: .routerCorroborated, confidence: 0.72,
                                            ambiguous: false, eligibleExits: 0, chosenIndex: nil, shape: nil,
                                            routerExit: r, osmExit: nil, googleExit: g,
                                            reason: "Router and Google agree on \(r); no map topology",
                                            entryWayID: nil, exitWayID: nil, rejected: [])
        case let (r?, g?) where r != g:
            return RoundaboutExitResolution(exit: nil, source: .ambiguous, confidence: 0.2,
                                            ambiguous: true, eligibleExits: 0, chosenIndex: nil, shape: nil,
                                            routerExit: r, osmExit: nil, googleExit: g,
                                            reason: "Router says \(r), Google says \(g); no map topology",
                                            entryWayID: nil, exitWayID: nil, rejected: [])
        case let (r?, nil):
            return RoundaboutExitResolution(exit: r, source: .router, confidence: 0.55,
                                            ambiguous: false, eligibleExits: 0, chosenIndex: nil, shape: nil,
                                            routerExit: r, osmExit: nil, googleExit: nil,
                                            reason: "Only the router says \(r); \(reason)",
                                            entryWayID: nil, exitWayID: nil, rejected: [])
        case let (nil, g?):
            return RoundaboutExitResolution(exit: g, source: .google, confidence: 0.5,
                                            ambiguous: false, eligibleExits: 0, chosenIndex: nil, shape: nil,
                                            routerExit: nil, osmExit: nil, googleExit: g,
                                            reason: "Only Google says \(g); \(reason)",
                                            entryWayID: nil, exitWayID: nil, rejected: [])
        default:
            return RoundaboutExitResolution(exit: nil, source: .unavailable, confidence: 0,
                                            ambiguous: false, eligibleExits: 0, chosenIndex: nil, shape: nil,
                                            routerExit: router, osmExit: nil, googleExit: google,
                                            reason: reason, entryWayID: nil, exitWayID: nil, rejected: [])
        }
    }

    // MARK: - Topology

    static func topology(_ e: RoundaboutExitEvidence) -> Topology? {
        let rings = e.ways.filter(\.isRing)
        guard !rings.isEmpty else { return nil }
        // The ring nearest the entry, plus every ring joined to it.
        guard let first = rings.min(by: { Roundabouts.distance(e.entry, $0) < Roundabouts.distance(e.entry, $1) }),
              Roundabouts.distance(e.entry, first) < 45 else { return nil }
        var ring = [first]
        var ringNodes = Set(first.nodes)
        var grew = true
        while grew {
            grew = false
            for w in rings where !ring.contains(where: { $0.id == w.id }) && w.nodes.contains(where: ringNodes.contains) {
                ring.append(w)
                ringNodes.formUnion(w.nodes)
                grew = true
            }
        }
        // Centre and radius from the ring's outline, weighted by length.
        var sx = 0.0, sy = 0.0, length = 0.0
        for w in ring {
            for k in 1..<w.points.count {
                let a = w.points[k - 1], b = w.points[k]
                let d = a.distance(to: b)
                sx += (a.lat + b.lat) / 2 * d
                sy += (a.lng + b.lng) / 2 * d
                length += d
            }
        }
        guard length > 10 else { return nil }
        let center = LatLng(sx / length, sy / length)
        let all = ring.flatMap(\.points)
        let radius = all.map { $0.distance(to: center) }.reduce(0, +) / Double(all.count)
        guard radius > 3, radius < 250 else { return nil }

        var arms: [Arm] = []
        var rejected: [String] = []
        for w in e.ways where !w.isRing {
            let access = w.tags["access"] ?? w.tags["motor_vehicle"]
            if ["no", "private"].contains(access) {
                rejected.append("way \(w.id): access=\(access ?? "no")")
                continue
            }
            let oneway = Roundabouts.onewayDirection(w.tags)
            let layer = Int(w.tags["layer"] ?? "0") ?? 0
            let name = w.tags["ref"] ?? w.tags["name"]
            let service = w.tags["highway"] == "service"
            for (i, node) in w.nodes.enumerated() where ringNodes.contains(node) {
                let p = w.points[i]
                for dir in [1, -1] {
                    let j = i + dir
                    guard j >= 0, j < w.nodes.count, !ringNodes.contains(w.nodes[j]) else { continue }
                    let leaves = oneway == 0 || oneway == dir
                    let comes = oneway == 0 || oneway == -dir
                    arms.append(Arm(angle: Geo.bearing(center, p), canExit: leaves, canEnter: comes,
                                    wayID: w.id, name: name, isService: service, layer: layer))
                }
            }
        }
        arms = merge(arms)
        guard !arms.isEmpty else { return nil }

        let entryAngle = Geo.bearing(center, e.entry)
        let entryArm = arms
            .filter { $0.canEnter }
            .min { Roundabouts.angleGap($0.angle, entryAngle) < Roundabouts.angleGap($1.angle, entryAngle) }
            ?? arms.min { Roundabouts.angleGap($0.angle, entryAngle) < Roundabouts.angleGap($1.angle, entryAngle) }
        guard let entryArm, Roundabouts.angleGap(entryArm.angle, entryAngle) < 60 else { return nil }

        func rel(_ a: Double) -> Double { Roundabouts.norm(a - entryArm.angle + 180) }
        func travel(_ r: Double) -> Double {
            let t = Roundabouts.norm(e.clockwise ? r - 180 : 180 - r)
            return t < 15 ? t + 360 : t
        }
        // Every arm you can leave by, except the way in. The road in itself is a legal exit
        // (all the way round), and travel() puts it last.
        var exits = arms.filter { $0.canExit && $0.angle != entryArm.angle }
        exits.sort { travel(rel($0.angle)) < travel(rel($1.angle)) }
        let inOnly = arms.filter { !$0.canExit }.map { rel($0.angle) }

        // The route's way off the circle.
        let outPoint = e.exitPoint ?? leavingPoint(e, center: center, radius: radius)
        guard let outPoint else {
            return Topology(center: center, radius: radius, ringWayIDs: ring.map(\.id),
                            entryAngle: entryArm.angle, entryArm: entryArm, exits: exits, inOnly: inOnly,
                            exitAngles: exits.map { rel($0.angle) }, taken: nil, exitAngleGap: .infinity,
                            complete: isComplete(ring, nodes: ringNodes), ambiguous: false,
                            rejected: rejected, exitWayID: nil)
        }
        let outAngle = rel(Geo.bearing(center, outPoint))
        guard let taken = exits.indices.min(by: { Roundabouts.angleGap(rel(exits[$0].angle), outAngle)
            < Roundabouts.angleGap(rel(exits[$1].angle), outAngle) }) else {
            return nil
        }
        let gap = Roundabouts.angleGap(rel(exits[taken].angle), outAngle)
        // Two exits closer than 18° to each other, or two arms of the same road a few metres
        // apart, cannot be told apart from the line alone.
        let close = exits.indices.filter { $0 != taken && Roundabouts.angleGap(rel(exits[$0].angle), rel(exits[taken].angle)) < 18 }
        let sameRoad = exits.indices.filter {
            $0 != taken && exits[$0].wayID == exits[taken].wayID
        }
        let ambiguous = gap > 35 || !close.isEmpty || !sameRoad.isEmpty

        return Topology(center: center, radius: radius, ringWayIDs: ring.map(\.id), entryAngle: entryArm.angle,
                        entryArm: entryArm, exits: exits, inOnly: inOnly,
                        exitAngles: exits.map { rel($0.angle) }, taken: gap < 60 ? taken : nil,
                        exitAngleGap: gap, complete: isComplete(ring, nodes: ringNodes),
                        ambiguous: ambiguous, rejected: rejected,
                        exitWayID: gap < 60 ? exits[taken].wayID : nil)
    }

    /** The first point of the route clearly outside the circle after the entry. */
    static func leavingPoint(_ e: RoundaboutExitEvidence, center: LatLng, radius: Double) -> LatLng? {
        let total = e.cumulative.last ?? 0
        let end = min(total, e.along + radius * 8 + 250)
        var d = e.along + 5
        while d <= end {
            let p = Geo.point(along: e.line, meters: d, cumulative: e.cumulative)
            if p.distance(to: center) > radius + max(12, radius * 0.4) { return p }
            d += 4
        }
        return nil
    }

    /** A ring is complete when it comes back to where it started within a few metres. */
    static func isComplete(_ ring: [Roundabouts.Way], nodes: Set<Int64>) -> Bool {
        guard ring.count >= 1 else { return false }
        let ends = ring.flatMap { w -> [Int64] in
            guard let a = w.nodes.first, let b = w.nodes.last else { return [] }
            return [a, b]
        }
        let counts = Dictionary(grouping: ends, by: { $0 }).mapValues(\.count)
        // Every open end of a ring way must meet another ring way (or close on itself).
        return !counts.isEmpty && counts.values.allSatisfy { $0 >= 2 }
    }

    /**
     * A dual carriageway meets the circle twice, once going in and once coming out: one road for
     * the count. Two arms of the same way are always one road, whatever their names.
     */
    static func merge(_ arms: [Arm]) -> [Arm] {
        var list = arms.sorted { $0.angle < $1.angle }
        var i = 0
        while list.count > 1 && i < list.count {
            let j = (i + 1) % list.count
            let a = list[i], b = list[j]
            let pair = (a.canExit && !a.canEnter && b.canEnter && !b.canExit)
                || (b.canExit && !b.canEnter && a.canEnter && !a.canExit)
            let sameWay = a.wayID == b.wayID
            let sameRoad = sameWay || a.name == nil || b.name == nil || a.name == b.name
            if i != j, pair, sameRoad, Roundabouts.angleGap(a.angle, b.angle) < 40 {
                let mid = Roundabouts.norm(a.angle + Roundabouts.signedGap(a.angle, b.angle) / 2)
                list[i] = Arm(angle: mid, canExit: true, canEnter: true,
                              wayID: a.canExit ? a.wayID : b.wayID,
                              name: a.name ?? b.name, isService: a.isService && b.isService,
                              layer: a.layer)
                list.remove(at: j)
                if j < i { i -= 1 }
            } else {
                i += 1
            }
        }
        return list
    }

    // MARK: - Developer diagnostics

    /** One line per roundabout, for the optional developer panel and anonymised test exports. */
    public static func diagnostics(_ r: RoundaboutExitResolution) -> [String] {
        var lines = [
            "router: \(r.routerExit.map(String.init) ?? "-")",
            "osm: \(r.osmExit.map(String.init) ?? "-")",
            "google: \(r.googleExit.map(String.init) ?? "-")",
            "final: \(r.exit.map(String.init) ?? "-")",
            "source: \(r.source.rawValue)",
            "confidence: \(String(format: "%.2f", r.confidence))",
            "eligible: \(r.eligibleExits)",
            "chosen index: \(r.chosenIndex.map(String.init) ?? "-")",
            "entry way: \(r.entryWayID.map(String.init) ?? "-")",
            "exit way: \(r.exitWayID.map(String.init) ?? "-")",
            "reason: \(r.reason)"
        ]
        lines += r.rejected.map { "rejected: \($0)" }
        return lines
    }
}
