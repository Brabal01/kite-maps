import XCTest
@testable import VelaCore

final class HUDProfileTests: XCTestCase {
    func testSimpleKeepsTheBannerQuiet() {
        let p = HUDCatalog.profile(for: .simple)
        XCTAssertFalse(p.showLanes)
        XCTAssertFalse(p.showThen)
        XCTAssertFalse(p.showJunction)
        XCTAssertEqual(p.alertDensity, 1)
    }

    func testAdvancedShowsEveryGuidanceLayer() {
        let p = HUDCatalog.profile(for: .advanced)
        XCTAssertTrue(p.showLanes)
        XCTAssertTrue(p.showThen)
        XCTAssertTrue(p.showJunction)
        XCTAssertEqual(p.laneLeadMultiplier, 1)
    }

    func testHighwayShowsLanesEarlier() {
        let advanced = HUDCatalog.profile(for: .advanced)
        let highway = HUDCatalog.profile(for: .highway)
        XCTAssertGreaterThan(highway.laneLeadMultiplier, advanced.laneLeadMultiplier)
        XCTAssertTrue(highway.showJunction)
    }

    func testCustomOnlyShowsWhatTheUserPicked() {
        let p = HUDCatalog.profile(for: .custom, customLanes: false,
                                   customThen: true, customJunction: false)
        XCTAssertFalse(p.showLanes)
        XCTAssertTrue(p.showThen)
        XCTAssertFalse(p.showJunction)
        XCTAssertEqual(p.laneLeadMultiplier, 0)
    }
}
