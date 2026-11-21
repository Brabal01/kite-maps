import Foundation
import VelaCore

/**
 Reproducible microbenchmarks of the pure navigation code. No network, no simulator, no GPU:
 these numbers measure the algorithms themselves on the machine running the command, and are
 reported with their conditions. They are not iPhone FPS or battery measurements.
 */
private func measure(_ name: String, iterations: Int, _ work: () -> Void) -> [String: Any] {
    let clock = ContinuousClock()
    let start = clock.now
    for _ in 0..<iterations { work() }
    let elapsed = clock.now - start
    let micros = Int(elapsed / .microseconds(1))
    return [
        "name": name,
        "iterations": iterations,
        "totalMicroseconds": micros,
        "microsecondsPerIteration": iterations > 0 ? Double(micros) / Double(iterations) : 0,
    ]
}

private func line(_ count: Int) -> [LatLng] {
    (0..<count).map { LatLng(50 + Double($0) / 110_540 * 20, 14.0) }
}

private func route(_ points: Int) -> Route {
    let path = line(points)
    return Route(mode: .drive, polyline: path, distanceMeters: Geo.length(path),
                 typicalSeconds: 3600, maneuvers: [], source: "bench")
}

private var results: [[String: Any]] = []

let benchLine = line(1_000)
let benchCumulative = Geo.cumulative(benchLine)
results.append(measure("Geo.project on a 1,000-point line", iterations: 10_000) {
    _ = Geo.project(LatLng(50.0005, 14.0002), on: benchLine, cumulative: benchCumulative)
})

let trackerRoute = route(200)
results.append(measure("RouteTracker.update (snap + progress)", iterations: 5_000) {
    let tracker = RouteTracker(route: trackerRoute)
    _ = tracker.update(LatLng(50.0005, 14.0005), accuracy: 5, heading: 0, speed: 12)
})

results.append(measure("RouteSectionScheduler next + succeed", iterations: 5_000) {
    var scheduler = RouteSectionScheduler(totalMeters: 200_000)
    for _ in 0..<50 {
        if let i = scheduler.next(now: Date()) { scheduler.succeeded(i) }
    }
})

let replayLine = line(300)
let replayFixture = GPSReplayFixture.drive(along: replayLine, speed: 12, interval: 1)
results.append(measure("GPSReplayPlan.schedule (300 fixes)", iterations: 500) {
    var options = GPSReplayOptions(); options.noiseMeters = 5
    _ = GPSReplayPlan.schedule(replayFixture, options: options)
})

results.append(measure("DiagnosticsRedactor.sanitize", iterations: 20_000) {
    _ = DiagnosticRedactor.sanitize("At 50.08804,14.42076 near me@example.com")
})

let benchRoute = route(600)
results.append(measure("OfflineRouteSnapshot encode + restore", iterations: 2_000) {
    let snapshot = OfflineRouteSnapshot(benchRoute)
    _ = try? JSONDecoder().decode(OfflineRouteSnapshot.self, from: JSONEncoder().encode(snapshot))
})

let journey = SavedJourney(name: "A → B", origin: Place(id: "a", name: "A", location: LatLng(50, 14), source: "bench"),
                           destination: Place(id: "b", name: "B", location: LatLng(50.1, 14.1), source: "bench"))
let journeyData = try! JSONEncoder().encode(journey)
results.append(measure("SavedJourney decode", iterations: 10_000) {
    _ = try? JSONDecoder().decode(SavedJourney.self, from: journeyData)
})

var memory: [String: Any] = ["source": "unavailable"]
#if os(Linux)
if let status = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8),
   let line = status.split(separator: "\n").first(where: { $0.hasPrefix("VmRSS:") }) {
    memory = ["source": "/proc/self/status VmRSS", "line": String(line)]
}
#endif

let document: [String: Any] = [
    "schema": "kite-v33-benchmarks-v1",
    "conditions": "VelaCore pure Swift algorithms, release-independent local run, no network, no UI, single process, wall clock.",
    "swiftVersion": "\(SystemInfo.swiftVersion)",
    "results": results,
    "memory": memory,
]
print(String(decoding: try! JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))

enum SystemInfo {
    static let swiftVersion: String = {
        #if compiler(>=6)
        "6.x"
        #else
        "5.x"
        #endif
    }()
}
