import XCTest
@testable import VelaCore

final class RouteStopSearchTests: XCTestCase {
    func testPlannerSearchesAllSectionsOfTheRoute() {
        let route = [LatLng(49.2, 17.2), LatLng(49.9, 17.2), LatLng(50.8, 17.2)]
        let search = RouteStopSearch(line: route, origin: route[0])
        XCTAssertGreaterThan(search.centers.count, 4)
        XCTAssertLessThan(search.centers.first?.point.lat ?? 90, 49.35)
        XCTAssertGreaterThan(search.centers.last?.point.lat ?? 0, 50.65)
        XCTAssertEqual(search.candidates([
            place("early", LatLng(49.24, 17.2)), place("late", LatLng(50.76, 17.2))
        ], named: false, excluding: []).map(\.id), ["early", "late"])
    }

    func testGuidanceRejectsPlacesBehindOrPastItsSearchHorizon() {
        let route = [LatLng(49.2, 17.2), LatLng(50.2, 17.2)]
        let start = Geo.project(LatLng(49.5, 17.2), on: route).along
        let search = RouteStopSearch(line: route, origin: route[0], progress: start)
        let candidates = search.candidates([
            place("behind", LatLng(49.49, 17.2)),
            place("ahead", LatLng(49.62, 17.2)),
            place("past-window", LatLng(49.90, 17.2)),
            place("parallel", LatLng(49.62, 17.25))
        ], named: false, excluding: [])
        XCTAssertEqual(search.centers.count, 3)
        XCTAssertEqual(candidates.map(\.id), ["ahead"])
        XCTAssertGreaterThan(candidates.first?.routeMeters ?? 0, start)
        XCTAssertEqual(candidates.first?.ahead ?? 0, route[0].distance(to: LatLng(49.62, 17.2)) - start, accuracy: 5)
    }

    func testOmitsTheDestinationAndCollapsesDuplicateProviderPins() {
        let start = LatLng(49.55, 17.2)
        let end = LatLng(49.63, 17.2)
        let stop = place("shop", LatLng(49.59, 17.2), name: "Kaufland")
        let search = RouteStopSearch(line: [start, end], origin: start)
        let output = search.candidates([
            stop, place("duplicate", LatLng(49.5901, 17.2), name: "Kaufland"),
            place("other", LatLng(49.5902, 17.2), name: "Pharmacy"), place("end", end)
        ], named: true, excluding: [place("end", end)])
        XCTAssertEqual(output.map(\.id), ["shop", "other"])
    }

    func testInsertsBetweenExistingStopsInTravelOrder() {
        let line = [LatLng(49.55, 17.2), LatLng(49.63, 17.2)]
        let stops = [place("near", LatLng(49.56, 17.2)), place("far", LatLng(49.62, 17.2))]
        let halfway = Geo.project(LatLng(49.59, 17.2), on: line).along
        XCTAssertEqual(RouteStopSearch.insertionIndex(for: halfway, among: stops, on: line), 1)
        XCTAssertEqual(RouteStopSearch.insertionIndex(for: halfway, among: stops.reversed(), on: line.reversed()), 1)
    }

    private func place(_ id: String, _ point: LatLng, name: String? = nil) -> Place {
        Place(id: id, name: name ?? id, location: point, source: "osm")
    }
}
