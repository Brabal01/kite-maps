import XCTest
@testable import VelaCore

final class SavedJourneyTests: XCTestCase {
    private let home = Place(id: "home", name: "Home", location: LatLng(50, -1), source: "test")
    private let work = Place(id: "work", name: "Work", location: LatLng(50.1, -1.1), source: "test")
    private let a = Place(id: "a", name: "A", location: LatLng(50.02, -1.02), source: "test")
    private let b = Place(id: "b", name: "B", location: LatLng(50.04, -1.04), source: "test")

    func testRoundTripAndReverseKeepStopsInTheRightOrder() throws {
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
        XCTAssertEqual(reversed.name, "Morning", "a name the user chose is not overwritten")
        XCTAssertEqual(reversed.reversed().origin, home)
        XCTAssertEqual(reversed.reversed().stops, [a, b])
    }

    /// v31 turned "My location → Work" into a trip whose start and end were both Work.
    func testReversingAJourneyFromMyLocationDoesNotCollapseIntoTheDestination() {
        let journey = SavedJourney(name: "", origin: nil, destination: work, stops: [a, b])
        let back = journey.reversed()
        XCTAssertEqual(back.travelFrom, .place(work))
        XCTAssertEqual(back.travelTo, .currentLocation)
        XCTAssertNotEqual(back.travelFrom, back.travelTo)
        XCTAssertEqual(back.travelStops, [b, a])
        XCTAssertEqual(back.displayName, "Work → My location")
        XCTAssertEqual(back.title(currentLocation: "Moje poloha"), "Work → Moje poloha")
        XCTAssertEqual(back.reversed(), journey, "reversing twice restores the original")
    }

    func testAutomaticNameFollowsTheDirection() {
        let journey = SavedJourney(name: "Home → Work", origin: home, destination: work)
        XCTAssertEqual(journey.reversed().name, "Work → Home")
    }

    func testEmptyNameUsesTheTwoEnds() {
        let j = SavedJourney(name: "", origin: home, destination: work)
        XCTAssertEqual(j.displayName, "Home → Work")
    }

    /// Exactly the JSON v31 wrote: none of the later fields exist.
    func testDecodesAJourneySavedByV31() throws {
        let json = """
        {"id":"6F1D6B50-0F6F-4E67-9C0B-6E2D3D6D8C11","name":"Old","modeRaw":0,"notes":"",
         "createdAt":700000000,"avoidTolls":false,"avoidHighways":true,"isGPXTrack":false,
         "stops":[],
         "destination":{"id":"w","name":"Work","location":{"lat":50.1,"lng":-1.1},"source":"osm",
                        "permanentlyClosed":false,"hours":[],"photoUrls":[],"about":[]}}
        """
        let journey = try JSONDecoder().decode(SavedJourney.self, from: Data(json.utf8))
        XCTAssertEqual(journey.name, "Old")
        XCTAssertNil(journey.origin)
        XCTAssertFalse(journey.isReturnTrip)
        XCTAssertFalse(journey.isFavorite)
        XCTAssertNil(journey.lastUsedAt)
        XCTAssertTrue(journey.avoidHighways)
        XCTAssertEqual(journey.schemaVersion, SavedJourney.currentSchemaVersion)
        XCTAssertEqual(journey.travelFrom, .currentLocation)
    }

    func testReversedFlagForTwoRealPlacesIsStoredAsASwap() {
        let journey = SavedJourney(name: "x", origin: home, destination: work, stops: [a, b], returnTrip: true)
        XCTAssertEqual(journey.origin, work)
        XCTAssertEqual(journey.destination, home)
        XCTAssertEqual(journey.stops, [b, a])
        XCTAssertFalse(journey.isReturnTrip)
    }

    func testCopyIsIndependentAndDisplayOrderPutsFavouritesFirst() {
        var old = SavedJourney(name: "Old", origin: home, destination: work, createdAt: Date(timeIntervalSince1970: 100))
        let recent = SavedJourney(name: "Recent", origin: home, destination: a, createdAt: Date(timeIntervalSince1970: 300))
        var favourite = SavedJourney(name: "Fav", origin: home, destination: b, createdAt: Date(timeIntervalSince1970: 50))
        favourite.isFavorite = true
        XCTAssertEqual([old, recent, favourite].sortedForDisplay().map(\.name), ["Fav", "Recent", "Old"])
        old.markUsed(Date(timeIntervalSince1970: 900))
        XCTAssertEqual([old, recent, favourite].sortedForDisplay().map(\.name), ["Fav", "Old", "Recent"])
        let copy = old.copy()
        XCTAssertNotEqual(copy.id, old.id)
        XCTAssertEqual(copy.name, "Old (copy)")
        XCTAssertNil(copy.lastUsedAt)
    }

    func testExportAndImportAssignFreshIdentifiers() throws {
        let journey = SavedJourney(name: "Trip", origin: nil, destination: work, stops: [a], mode: .walk)
        let data = try [journey].exportedJSON()
        let imported = try XCTUnwrap(SavedJourneyImport.journeys(from: data))
        XCTAssertEqual(imported.count, 1)
        XCTAssertNotEqual(imported[0].id, journey.id)
        XCTAssertEqual(imported[0].destination, work)
        XCTAssertEqual(imported[0].mode, .walk)
        XCTAssertNil(SavedJourneyImport.journeys(from: Data("nope".utf8)))
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
