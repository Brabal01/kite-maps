import XCTest

final class V34UITests: XCTestCase {
    func testOfflineRestartRecoversNavigationAndCanDiscardLater() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-planning"]
        app.launchEnvironment = [
            "KITE_UITEST_LOCATION": "38.5449,-121.7405",
            "KITE_UITEST_ROUTES": "1"
        ]
        app.launch()
        let discard = app.buttons["discard-interrupted-journey"]
        if discard.exists { discard.tap() }
        let work = app.buttons["favourite-work"]
        XCTAssertTrue(work.waitForExistence(timeout: 30))
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
        XCTAssertTrue(resume.waitForExistence(timeout: 25))
        resume.tap()
        XCTAssertTrue(instruction.waitForExistence(timeout: 20), "Existing maneuvers must load without a router fixture.")
        app.terminate()
        app.launch()
        XCTAssertTrue(discard.waitForExistence(timeout: 25))
        discard.tap()
        XCTAssertFalse(resume.exists)
    }
}
