import XCTest
@testable import VelaCore

final class SearchParserTests: XCTestCase {
    /** A list reply cut down to the fields the parser reads, at Vela's calibrated positions. */
    private func entry(name: String, lat: Double, lng: Double, status: String?) -> [Any] {
        var node = [Any](repeating: NSNull(), count: 210)
        node[11] = name
        node[9] = [NSNull(), NSNull(), lat, lng]
        node[39] = "\(name), 1 Main St, Springfield"
        node[13] = ["Pizza restaurant"]
        var four = [Any](repeating: NSNull(), count: 9)
        four[7] = 4.5
        four[8] = 120
        node[4] = four
        node[10] = "0x1:0x\(name.count)"
        if let status {
            var meta = [Any](repeating: NSNull(), count: 9)
            meta[4] = [status]
            let day: [Any] = ["Monday", 1, [2026, 10, 19], [["11 AM–10 PM"]]]
            node[203] = [[day], meta]
        }
        return [NSNull(), node]
    }

    func testParsesListReply() {
        var root = [Any](repeating: NSNull(), count: 65)
        root[64] = [
            entry(name: "Far Pizza", lat: 40.80, lng: -73.98, status: "Closed · Opens 11 AM"),
            entry(name: "Near Pizza", lat: 40.7485, lng: -73.9857, status: "Open · Closes 10 PM"),
        ]
        let places = SearchParser.parse(root: root, near: LatLng(40.7484, -73.9857))
        // Google's order is kept (not re-sorted nearest first).
        XCTAssertEqual(places.map(\.name), ["Far Pizza", "Near Pizza"])
        let near = places[1]
        XCTAssertEqual(near.address, "1 Main St, Springfield")
        XCTAssertEqual(near.category, "Pizza restaurant")
        XCTAssertEqual(near.rating, 4.5)
        XCTAssertEqual(near.reviewCount, 120)
        XCTAssertEqual(near.openNow, true)
        XCTAssertEqual(near.hours, ["Monday: 11 AM–10 PM"])
        XCTAssertEqual(places[0].openNow, false)
    }

    func testSearchFindsRelocatedListAndCzechHours() {
        let first = entry(name: "Kavárna Most", lat: 50, lng: 14, status: "Otevřeno · Zavírá v 18:00")
        let second = entry(name: "Kavárna u parku", lat: 50.02, lng: 14, status: "Zavřeno")
        let places = SearchParser.parse(root: [NSNull(), [first, second]] as [Any], near: nil)
        XCTAssertEqual(places.map(\.name), ["Kavárna Most", "Kavárna u parku"])
        XCTAssertEqual(places.map(\.openNow), [true, false])
        XCTAssertEqual(PlaceSearch.mapFocus(query: "kavarna", places: places, category: true).count, 2)
        XCTAssertEqual(PlaceSearch.mapFocus(query: "kavarna", places: places, category: false).count, 1)
    }

    func testGoogleFocusedResultOnlyAddsMatchingBranches() {
        func nested(_ value: Any, _ indices: [Int]) -> Any {
            indices.reversed().reduce(value) { child, index in
                var row = [Any](repeating: NSNull(), count: index + 1)
                row[index] = child
                return row
            }
        }
        var focus = entry(name: "Cafe Atlas", lat: 50, lng: 14, status: nil)[1] as! [Any]
        let branch = entry(name: "Cafe Atlas Centrum", lat: 50.02, lng: 14, status: nil)
        let other = entry(name: "Atlas Books", lat: 50.03, lng: 14, status: nil)
        focus[99] = nested([branch, other, branch], [0, 0, 1])
        let places = SearchParser.parse(root: nested(focus, [0, 1, 0, 14]), near: nil, query: "cafe atlas")
        XCTAssertEqual(places.map(\.name), ["Cafe Atlas", "Cafe Atlas Centrum"])
    }

    func testLivePlaceSearchWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["KITE_VERIFY_GOOGLE"] == "1" else {
            throw XCTSkip("Live search is opt-in")
        }
        let response = await PlaceSearch.search("Eiffel Tower", center: LatLng(48.858, 2.294),
                                                spanMeters: 10_000, language: "en")
        guard response.places.contains(where: { $0.source == "google" && $0.name.lowercased().contains("eiffel") }) else {
            throw XCTSkip("Google did not return a verifiable Eiffel Tower result from this runner")
        }
    }

    func testOpensIsClosed() {
        XCTAssertEqual(SearchParser.openNow("Opens 5 AM"), false)
        XCTAssertEqual(SearchParser.openNow("Open 24 hours"), true)
        XCTAssertEqual(SearchParser.openNow("Closes soon · 9 PM"), true)
        XCTAssertNil(SearchParser.openNow(nil))
    }

    func testStripNamePrefix() {
        XCTAssertEqual(SearchParser.stripNamePrefix("Safeway, 1451 W Covell Blvd", name: "Safeway"), "1451 W Covell Blvd")
        XCTAssertEqual(SearchParser.stripNamePrefix("Safeway Plaza, 1 Rd", name: "Safeway"), "Safeway Plaza, 1 Rd")
    }

    func testXssiGuard() {
        let v = GoogleJSON.parse(")]}'\n[1,[\"a\"]]")
        XCTAssertEqual(str(at(v, 1, 0)), "a")
    }

    func testPbTemplate() {
        let pb = SearchPb.build(query: "pizza!", center: LatLng(1.5, 2.5), spanMeters: 3000)
        XCTAssertTrue(pb.hasPrefix("!1spizza!4m8!1m3!1d3000.0!2d2.5!3d1.5!3m2"))
        XCTAssertFalse(pb.contains(" "))
        XCTAssertFalse(pb.contains("\n"))
        XCTAssertTrue(pb.hasSuffix("!69i782!77b1"))
    }
}
