import XCTest

final class V35UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTransitLayerIsolationAcrossRenderersAndGuidance() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "maplayers", "-uitest-map-layers", "-AppleLanguages", "(en)"]
        app.launch()
        let renderer = app.staticTexts["layer-inspector-renderer"]
        let rail = app.buttons["inspected-vela-rail"]
        let route = app.buttons["inspected-vela-route"]
        waitForLabel("MapKit", on: renderer)
        XCTAssertTrue(rail.waitForExistence(timeout: 30))
        rail.tap()
        waitForValue("Hidden", on: rail)
        rail.tap()
        waitForValue("Visible", on: rail)
        capture("v35-mapkit-transit")

        app.buttons["Start fixture"].tap()
        XCTAssertTrue(route.waitForExistence(timeout: 15))
        XCTAssertFalse(rail.exists)
        capture("v35-mapkit-drive")

        app.buttons["Switch renderer"].tap()
        waitForLabel("MapLibre", on: renderer)
        XCTAssertTrue(route.waitForExistence(timeout: 45))
        XCTAssertFalse(rail.exists)
        capture("v35-maplibre-drive")

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(route.waitForExistence(timeout: 15))
        XCTAssertFalse(rail.exists)
        app.buttons["Stop fixture"].tap()
        XCTAssertTrue(rail.waitForExistence(timeout: 20))
        XCTAssertFalse(route.exists)
        capture("v35-maplibre-transit")
    }

    private func waitForLabel(_ label: String, on element: XCUIElement) {
        let check = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [check], timeout: 45), .completed)
    }

    private func waitForValue(_ value: String, on element: XCUIElement) {
        let check = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [check], timeout: 10), .completed)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
