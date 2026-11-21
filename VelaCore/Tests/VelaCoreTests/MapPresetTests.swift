import XCTest
@testable import VelaCore

final class MapPresetTests: XCTestCase {
    func testEveryPresetHasACompleteProfile() {
        for preset in MapPreset.allCases {
            let p = MapPresetCatalog.profile(for: preset)
            XCTAssertGreaterThan(p.roadContrast, 0)
            XCTAssertGreaterThan(p.labelDensity, 0)
        }
    }

    func testNavigationKeepsRoadsAndBuildingsButDropsPOIAndMinorLabels() {
        let p = MapPresetCatalog.profile(for: .navigation)
        XCTAssertFalse(p.showPOI)
        XCTAssertFalse(p.showMinorLabels)
        XCTAssertTrue(p.showBuildings)
        XCTAssertTrue(p.show3DBuildings)
        XCTAssertTrue(p.dimMinorRoads)
        XCTAssertGreaterThan(p.roadContrast, 1)
    }

    func testMinimalIsQuieterThanClassicAndExploreIsRicher() {
        let minimal = MapPresetCatalog.profile(for: .minimal)
        let classic = MapPresetCatalog.profile(for: .classic)
        let explore = MapPresetCatalog.profile(for: .explore)
        XCTAssertFalse(minimal.showBuildings)
        XCTAssertFalse(minimal.showTraffic)
        XCTAssertLessThan(minimal.labelDensity, classic.labelDensity)
        XCTAssertGreaterThan(explore.labelDensity, classic.labelDensity)
        XCTAssertTrue(explore.showTransit)
    }

    func testTransitAndOutdoorsTurnOnTheirOwnLayers() {
        XCTAssertTrue(MapPresetCatalog.profile(for: .transit).showTransit)
        XCTAssertTrue(MapPresetCatalog.profile(for: .outdoors).showTerrain)
        XCTAssertTrue(MapPresetCatalog.profile(for: .outdoors).showPaths)
        XCTAssertTrue(MapPresetCatalog.profile(for: .satellite).satellite)
    }

    func testGuidanceUsesNavigationProfileUnlessTheUserChoseMinimal() {
        XCTAssertEqual(MapPresetCatalog.guidanceProfile(base: .classic),
                       MapPresetCatalog.profile(for: .navigation))
        XCTAssertEqual(MapPresetCatalog.guidanceProfile(base: .minimal),
                       MapPresetCatalog.profile(for: .minimal))
    }
}
