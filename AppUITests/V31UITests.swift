import XCTest

/**
 * The v31 P0/P1 screens, driven by deterministic demo data so the test does not
 * depend on routing servers or a live timetable.
 */
final class V31UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ step: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", step]
        app.launch()
        return app
    }

    func testRoundaboutBannerShowsAConfirmedExit() {
        let app = launch("roundaboutsynthetic")
        let exit = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'exit'"))
            .firstMatch
        XCTAssertTrue(exit.waitForExistence(timeout: 40), "the roundabout banner must show an exit")
    }

    func testSignalDemoShowsOurDirectionLights() {
        let app = launch("signalsynthetic")
        let light = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'Traffic lights ahead'"))
            .firstMatch
        XCTAssertTrue(light.waitForExistence(timeout: 40), "the upcoming strip must show the route's lights")
    }

    func testTransitDemoShowsOfficialLineChips() {
        let app = launch("transitsynthetic")
        // LineChip's accessibility label is "<mode> <line>": the synthetic metro is "Metro A".
        let metro = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'Metro A'"))
            .firstMatch
        XCTAssertTrue(metro.waitForExistence(timeout: 40), "the transit card must show the metro line chip")
    }
}
