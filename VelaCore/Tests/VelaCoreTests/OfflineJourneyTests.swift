import XCTest
@testable import VelaCore

final class OfflineJourneyTests: XCTestCase {
    private func route() -> Route {
        let line = [LatLng(50.0, 14.0), LatLng(50.005, 14.0), LatLng(50.005, 14.01)]
        let length = Geo.length(line)
        return Route(mode: .bike, polyline: line, distanceMeters: length, typicalSeconds: 900, trafficSeconds: 960,
                     summary: "via Main St",
                     maneuvers: [Maneuver(type: .depart, instruction: "Head north", location: line[0], alongMeters: 0, distanceMeters: 555, road: "Main St"),
                                 Maneuver(type: .roundabout, instruction: "Take the 2nd exit", location: line[1], alongMeters: 555, distanceMeters: 700, exit: 2),
                                 Maneuver(type: .arrive, instruction: "Arrive", location: line[2], alongMeters: length, distanceMeters: 0)],
                     source: "osrm")
    }

    private let destination = Place(id: "d", name: "Dest", location: LatLng(50.005, 14.01), source: "test")

    private func store() -> OfflineJourneyStore {
        OfflineJourneyStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("kite-test-\(UUID().uuidString).json"))
    }

    func testTheRouteSurvivesARoundTripWithItsTurns() throws {
        let original = route()
        let restored = try XCTUnwrap(OfflineRouteSnapshot(original).route())
        XCTAssertEqual(restored.mode, .bike)
        XCTAssertEqual(restored.polyline.count, 3)
        XCTAssertEqual(restored.polyline[2].lng, 14.01, accuracy: 1e-6)
        XCTAssertEqual(restored.maneuvers.map(\.type), [.depart, .roundabout, .arrive])
        XCTAssertEqual(restored.maneuvers[1].exit, 2)
        XCTAssertEqual(restored.maneuvers[0].road, "Main St")
        XCTAssertEqual(restored.durationSeconds, 960)
        XCTAssertTrue(restored.source.hasSuffix("+saved"), "a restored route says it is a saved copy")
        XCTAssertNotEqual(restored.id, original.id)
    }

    func testStoreSavesLoadsAndClears() throws {
        let store = store()
        defer { store.clear() }
        XCTAssertNil(store.load())
        let journey = OfflineJourney(destination: destination, stops: [], avoidTolls: true, avoidHighways: false, route: route())
        XCTAssertTrue(store.save(journey))
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.destination, destination)
        XCTAssertTrue(loaded.avoidTolls)
        store.clear()
        XCTAssertNil(store.load())
    }

    func testStaleAndCorruptFilesAreIgnored() throws {
        let store = store()
        defer { store.clear() }
        let old = OfflineJourney(destination: destination, stops: [], avoidTolls: false, avoidHighways: false,
                                 route: route(), savedAt: Date().addingTimeInterval(-3 * 3600))
        XCTAssertTrue(store.save(old))
        XCTAssertNil(store.load(), "a three-hour-old plan is not offered")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kite-corrupt-\(UUID().uuidString).json")
        try Data("{broken".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(OfflineJourneyStore(url: url).load())
    }

    func testInvalidGeometryIsRejected() {
        var snapshot = OfflineRouteSnapshot(route())
        snapshot.coordinates = [50, 14]
        XCTAssertNil(snapshot.route())
        snapshot.coordinates = [95, 14, 50, 14]
        XCTAssertNil(snapshot.route(), "latitude out of range")
        snapshot.coordinates = [50, 14, 50, .nan]
        XCTAssertNil(snapshot.route())
    }
    func testSnapshotCannotResumeADifferentModeOrStopSequence() {
        let stop = Place(id: "stop", name: "Stop", location: LatLng(50.005, 14), source: "test")
        let journey = OfflineJourney(destination: destination, stops: [stop], avoidTolls: false,
                                     avoidHighways: false, route: route())
        XCTAssertTrue(journey.matches(destinationID: "d", stopIDs: ["stop"], modeRaw: TravelMode.bike.rawValue))
        XCTAssertFalse(journey.matches(destinationID: "d", stopIDs: [], modeRaw: TravelMode.bike.rawValue))
        XCTAssertFalse(journey.matches(destinationID: "d", stopIDs: ["stop"], modeRaw: TravelMode.drive.rawValue))
    }

    func testLegacyStepFlagsAndDifferentPositionAfterRestoring() throws {
        var snapshot = OfflineRouteSnapshot(route())
        snapshot.steps[0].silent = nil
        snapshot.steps[1].leavesRoundabout = nil
        snapshot.steps[1].exitAmbiguous = nil
        let restored = try XCTUnwrap(try JSONDecoder().decode(
            OfflineRouteSnapshot.self, from: JSONEncoder().encode(snapshot)
        ).route())
        let tracker = RouteTracker(route: restored)
        let progress = tracker.update(LatLng(50.004, 14.0), accuracy: 8, heading: 0, speed: 5)
        XCTAssertGreaterThan(progress.alongMeters, 350)
        XCTAssertEqual(progress.nextIndex, 1)
        XCTAssertEqual(restored.maneuvers[1].exit, 2)
    }

    func testInvalidManeuverDataIsRejected() {
        var snapshot = OfflineRouteSnapshot(route())
        snapshot.steps[1].along = -1
        XCTAssertNil(snapshot.route())
        snapshot = OfflineRouteSnapshot(route())
        snapshot.steps[1].lat = 91
        XCTAssertNil(snapshot.route())
    }

}
