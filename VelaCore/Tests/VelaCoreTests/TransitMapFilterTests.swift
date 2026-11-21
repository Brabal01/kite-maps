import XCTest
@testable import VelaCore

final class TransitMapFilterTests: XCTestCase {
    func testEveryModeBelongsToACategoryAndNothingIsHiddenByDefault() {
        for mode in TransitMode.allCases {
            XCTAssertTrue(TransitMapFilter.shows(mode, hidden: []), "\(mode) must show by default")
        }
        XCTAssertEqual(TransitMapCategory(.subway), .metro)
        XCTAssertEqual(TransitMapCategory(.lightRail), .tram)
        XCTAssertEqual(TransitMapCategory(.suburbanRail), .suburban)
        XCTAssertEqual(TransitMapCategory(.highSpeedRail), .rail)
        XCTAssertEqual(TransitMapCategory(.trolleybus), .trolleybus)
    }

    func testHidingOneCategoryKeepsTheRest() {
        let hidden: Set<String> = ["bus"]
        XCTAssertFalse(TransitMapFilter.shows(.bus, hidden: hidden))
        XCTAssertFalse(TransitMapFilter.shows(.coach, hidden: hidden))
        XCTAssertTrue(TransitMapFilter.shows(.tram, hidden: hidden))
        XCTAssertTrue(TransitMapFilter.shows(.trolleybus, hidden: hidden))
    }

    func testShowOnlyOneKindAndRecogniseIt() {
        let hidden = TransitMapFilter.hiddenShowingOnly(.tram)
        XCTAssertTrue(TransitMapFilter.shows(.tram, hidden: hidden))
        XCTAssertFalse(TransitMapFilter.shows(.metro, hidden: hidden))
        XCTAssertFalse(TransitMapFilter.shows(.ferry, hidden: hidden))
        XCTAssertEqual(TransitMapFilter.onlyShown(in: hidden), .tram)
        XCTAssertNil(TransitMapFilter.onlyShown(in: []))
    }

    func testAStaleSettingCanNeverHideEverything() {
        XCTAssertEqual(TransitMapFilter.sanitized(["bus", "teleporter"]), ["bus"])
        XCTAssertEqual(TransitMapFilter.sanitized(TransitMapCategory.allCases.map(\.rawValue)), [],
                       "hiding every category is treated as no filter")
    }
}
