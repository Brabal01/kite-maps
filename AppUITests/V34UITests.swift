import XCTest

final class V34UITests: XCTestCase {
    func testOfflineRestartRecoversNavigationAndCanDiscardLater() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // XCTest terminates the process repeatedly. Do not carry the previous suite's launch-health
        // state or onboarding dialogs into this test of the application's normal journey store.
        app.launchArguments = [
            "-uitest-planning", "-safeMode", "NO", "-launchHealth", "UITest",
            "-welcomed", "YES", "-wazeAsked", "YES", "-AppleLanguages", "(en)"
        ]
        addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            for title in ["Allow While Using App", "Allow Once", "Allow"] {
                let button = alert.buttons[title]
                if button.exists { button.tap(); return true }
            }
            return false
        }
        app.launchEnvironment = [
            "KITE_UITEST_LOCATION": "38.5449,-121.7405",
            "KITE_UITEST_ROUTES": "1"
        ]
        app.launch()
        let discard = app.buttons["discard-interrupted-journey"]
        if discard.exists { discard.tap() }
        let work = app.buttons["favourite-work"]
        if !work.exists, app.buttons["Routes"].exists {
            app.buttons["Routes"].tap()
        }
        XCTAssertTrue(work.waitForExistence(timeout: 30), "The test must start on Routes.\n\(app.debugDescription)")
        work.tap()
        let start = app.buttons["start-navigation"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        start.tap()
        let instruction = app.descendants(matching: .any)["active-navigation-instruction"].firstMatch
        XCTAssertTrue(instruction.waitForExistence(timeout: 20))
        app.terminate()

        app.launchEnvironment = [
            "KITE_UITEST_LOCATION": "38.5460,-121.7411",
            "KITE_UITEST_OFFLINE": "1"
        ]
        app.launch()
        let resume = app.buttons["resume-interrupted-journey"]
        XCTAssertTrue(resume.waitForExistence(timeout: 25), "The saved journey must appear after restart.\n\(app.debugDescription)")
        resume.tap()
        XCTAssertTrue(instruction.waitForExistence(timeout: 20), "Existing maneuvers must load without a router fixture.")
        app.terminate()
        app.launch()
        XCTAssertTrue(discard.waitForExistence(timeout: 25))
        discard.tap()
        XCTAssertFalse(resume.exists)
    }
}
