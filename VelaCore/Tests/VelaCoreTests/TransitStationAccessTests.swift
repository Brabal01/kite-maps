import XCTest
@testable import VelaCore

final class TransitStationAccessTests: XCTestCase {
    func testEntranceQueryContainsTheRequestedNodeIDs() {
        let query = TransitStationAccess.entranceQuery("123,456")
        XCTAssertTrue(query.contains("node(id:(123,456))"), query)
        XCTAssertTrue(query.contains("railway"))
    }

    func testEntranceQueryDoesNotUseAPlaceholder() {
        // Regression: the query said `node(id:(ids))`, so Overpass looked for a
        // node called "ids" and every entrance lookup returned nothing.
        XCTAssertFalse(TransitStationAccess.entranceQuery("1").contains("(ids)"))
    }
}
