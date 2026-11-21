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
        addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            for title in ["Allow While Using App", "Allow Once", "Allow"] {
                let button = alert.buttons[title]
                if button.exists { button.tap(); return true }
            }
            return false
        }
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

        // One route shows its duration in the trip header; more than one also
        // puts a card with the same identifier in the header's card row.
        let status = app.descendants(matching: .any)["planning-status"]
        let summary = app.descendants(matching: .any)["route-summary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 30),
                      "a delayed GPS fix must still produce a route (status: \(status.exists ? status.label : "none"))\n\(app.debugDescription)")
        var previousLabel = summary.label
        XCTAssertFalse(previousLabel.isEmpty)

        // Drive -> walk -> bike: each must show a route, not the waiting state.
        for mode in ["mode-walk", "mode-bike"] {
            let tab = app.buttons[mode]
            XCTAssertTrue(tab.waitForExistence(timeout: 10))
            tab.tap()
            XCTAssertTrue(summary.waitForExistence(timeout: 20),
                          "\(mode) must produce its own route")
            let changed = expectation(
                for: NSPredicate(format: "exists == true AND label != %@", previousLabel),
                evaluatedWith: summary)
            wait(for: [changed], timeout: 20)
            previousLabel = summary.label
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
