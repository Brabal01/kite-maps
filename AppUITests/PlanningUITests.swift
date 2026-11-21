import XCTest

/**
 A real simulator run: the planner opens, a simulated GPS fix arrives late,
 Kite calculates a route, and every travel mode can take over without the
 "waiting for your location" screen coming back.
 */
final class PlanningUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPlannerProducesRoutesAndSwitchesEveryMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-planning"]
        app.launchEnvironment = [
            "KITE_UITEST_LOCATION": "38.5449,-121.7405",
            "KITE_UITEST_LOCATION_DELAY": "3",
            "KITE_UITEST_ROUTES": "1"
        ]
        app.launch()

        let work = app.buttons["favourite-work"]
        XCTAssertTrue(work.waitForExistence(timeout: 20), "the Routes page should be ready")
        work.tap()

        let summary = app.buttons["route-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 30),
                      "a delayed GPS fix must still produce a route")
        let driveLabel = summary.label
        XCTAssertFalse(driveLabel.isEmpty)

        // Drive -> walk -> bike: each must show a route, not the waiting state.
        for mode in ["mode-walk", "mode-bike"] {
            let tab = app.buttons[mode]
            XCTAssertTrue(tab.waitForExistence(timeout: 10))
            tab.tap()
            let changed = expectation(for: NSPredicate(format: "label != %@", driveLabel),
                                      evaluatedWith: summary)
            wait(for: [changed], timeout: 20)
            let waiting = app.descendants(matching: .any)["planning-status"]
            XCTAssertFalse(waiting.exists, "\(mode) must not fall back to waiting for location")
        }

        // Transit has its own provider; the shared start point and request must survive.
        let transit = app.buttons["mode-transit"]
        XCTAssertTrue(transit.waitForExistence(timeout: 10))
        transit.tap()
        XCTAssertFalse(app.descendants(matching: .any)["planning-status"].exists,
                       "transit must use the same location and not start a second wait")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
