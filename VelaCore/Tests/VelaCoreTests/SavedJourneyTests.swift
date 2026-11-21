import XCTest
@testable import VelaCore

final class SavedJourneyTests: XCTestCase {
    func testRoundTripAndReverseKeepStopsInTheRightOrder() throws {
        let home = Place(id: "home", name: "Home", location: LatLng(50, -1), source: "test")
        let work = Place(id: "work", name: "Work", location: LatLng(50.1, -1.1), source: "test")
        let a = Place(id: "a", name: "A", location: LatLng(50.02, -1.02), source: "test")
        let b = Place(id: "b", name: "B", location: LatLng(50.04, -1.04), source: "test")
        let journey = SavedJourney(name: "Morning", origin: home, destination: work,
                                   stops: [a, b], mode: .bike, notes: "Take the quiet road",
                                   avoidTolls: true, avoidHighways: true)
        let data = try JSONEncoder().encode(journey)
        let decoded = try JSONDecoder().decode(SavedJourney.self, from: data)
        XCTAssertEqual(decoded, journey)
        XCTAssertEqual(decoded.mode, .bike)

        let reversed = journey.reversed()
        XCTAssertEqual(reversed.origin, work)
        XCTAssertEqual(reversed.destination, home)
        XCTAssertEqual(reversed.stops, [b, a])
    }

    func testEmptyNameUsesTheTwoEnds() {
        let home = Place(id: "home", name: "Home", location: LatLng(50, -1), source: "test")
        let work = Place(id: "work", name: "Work", location: LatLng(50.1, -1.1), source: "test")
        let j = SavedJourney(name: "", origin: home, destination: work)
        XCTAssertEqual(j.displayName, "Home → Work")
    }
}

final class GPXTests: XCTestCase {
    private let sample = """
    <?xml version="1.0"?>
    <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
      <trk><name>Sunday ride</name><trkseg>
        <trkpt lat="50.000" lon="-1.000"><ele>100</ele></trkpt>
        <trkpt lat="50.010" lon="-1.010"><ele>130</ele><time>2026-11-21T10:00:00Z</time></trkpt>
        <trkpt lat="50.020" lon="-1.020"><ele>120</ele></trkpt>
      </trkseg></trk>
    </gpx>
    """

    func testImportReadsNameElevationTimeAndDistance() throws {
        let track = try GPX.parse(Data(sample.utf8))
        XCTAssertEqual(track.name, "Sunday ride")
        XCTAssertEqual(track.points.count, 3)
        XCTAssertEqual(track.points[1].elevationMeters, 130)
        XCTAssertNotNil(track.points[1].time)
        XCTAssertGreaterThan(track.distanceMeters, 2_000)
        XCTAssertEqual(track.elevationGainMeters, 30, accuracy: 0.01)
    }

    func testImportRejectsBrokenAndHugeInput() {
        XCTAssertThrowsError(try GPX.parse(Data("<gpx><trkpt lat=\"x\" lon=\"2\"/></gpx>".utf8))) {
            XCTAssertEqual($0 as? GPXError, .invalidCoordinate)
        }
        XCTAssertThrowsError(try GPX.parse(Data("<gpx><trk></trk></gpx>".utf8))) {
            XCTAssertEqual($0 as? GPXError, .noPoints)
        }
        XCTAssertThrowsError(try GPX.parse(Data(repeating: 0, count: GPX.maximumBytes + 1))) {
            XCTAssertEqual($0 as? GPXError, .tooLarge)
        }
        XCTAssertThrowsError(try GPX.parse(Data("<gpx><trkpt lat=\"91\" lon=\"0\"/></gpx>".utf8))) {
            XCTAssertEqual($0 as? GPXError, .invalidCoordinate)
        }
    }

    func testExportCanBeParsedBack() throws {
        let route = Route(mode: .bike,
                          polyline: [LatLng(50, -1), LatLng(50.01, -1.01)],
                          distanceMeters: 1_500, typicalSeconds: 300,
                          maneuvers: [], source: "test")
        let data = GPX.export(route, name: "A & B")
        let parsed = try GPX.parse(data)
        XCTAssertEqual(parsed.name, "A & B")
        XCTAssertEqual(parsed.points.count, 2)
        XCTAssertEqual(parsed.points[1].location, LatLng(50.01, -1.01))
    }
}
