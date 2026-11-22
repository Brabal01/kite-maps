import XCTest

/** v33 behaviour, tested on a real simulator with the deterministic fixtures used by the planner. */
final class V33UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func openSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "settings"]
        app.launch()
        return app
    }

    func testSettingsSearchOpensTheMatchingPage() {
        let app = openSettings()
        let search = app.searchFields["Search settings"]
        XCTAssertTrue(search.waitForExistence(timeout: 30), "Settings search must be visible.\n\(app.debugDescription)")
        search.tap()
        search.typeText("camera")
        let result = app.staticTexts["Cameras & speed"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), "a matching page must be listed")
        result.tap()
        let toggleText = app.staticTexts["Say when a speed camera is ahead"]
        XCTAssertTrue(toggleText.waitForExistence(timeout: 10), "the result must open the real settings page")
        XCTAssertTrue(app.staticTexts["Current jurisdiction"].exists, "the jurisdiction gate must be explained")
    }

    func testSettingsSearchReportsNoMatch() {
        let app = openSettings()
        let search = app.searchFields["Search settings"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        search.typeText("zzzznotasetting")
        XCTAssertTrue(app.staticTexts["No settings match that search."].waitForExistence(timeout: 10))
    }

    func testGPSReplayUsesASeparateSourceAndCanBeStopped() {
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
            "KITE_UITEST_LOCATION_DELAY": "1",
            "KITE_UITEST_ROUTES": "1",
            "KITE_UITEST_REPLAY": "1",
            "KITE_UITEST_REPLAY_CONTROLS": "1",
            "KITE_UITEST_REPLAY_SPEED": "1"
        ]
        app.launch()

        let work = app.buttons["favourite-work"]
        XCTAssertTrue(work.waitForExistence(timeout: 30))
        work.tap()
        let summary = app.descendants(matching: .any)["route-summary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 30))
        let go = app.buttons["start-navigation"]
        XCTAssertTrue(go.waitForExistence(timeout: 10), "the Go button must be reachable after planning")
        go.tap()

        let banner = app.descendants(matching: .any)["simulated-gps-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 40), "the simulated drive must be clearly marked.\n\(app.debugDescription)")
        let pause = app.buttons["replay-pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5), "pause must really pause")
        let skip = app.buttons["replay-skip"]
        XCTAssertTrue(skip.exists, "a replay can jump to a manoeuvre")
        skip.tap()
        app.buttons["replay-stop-detail"].tap()
        app.buttons["Done"].tap()
        XCTAssertFalse(banner.exists, "stopping the replay removes the banner")
    }
}
