import XCTest
@testable import VelaCore

final class LaunchHealthTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testASingleCrashDoesNotEnterSafeMode() {
        var health = LaunchHealth()
        XCTAssertFalse(health.launch(now: t0))
        XCTAssertFalse(health.launch(now: t0.addingTimeInterval(30)), "one launch that never became healthy is not a loop")
    }

    func testTwoUnhealthyLaunchesInARowEnterSafeModeOnce() {
        var health = LaunchHealth()
        XCTAssertFalse(health.launch(now: t0))
        XCTAssertFalse(health.launch(now: t0.addingTimeInterval(20)))
        XCTAssertTrue(health.launch(now: t0.addingTimeInterval(40)))
        // Safe mode launch itself became healthy, or the user left it: the next normal launch is clean.
        XCTAssertFalse(health.launch(now: t0.addingTimeInterval(60)), "no permanent crash/restart loop")
    }

    func testQuitOrBackgroundingRightAfterOpeningIsNotACrash() {
        var health = LaunchHealth()
        for i in 0..<5 {
            XCTAssertFalse(health.launch(now: t0.addingTimeInterval(Double(i) * 10)))
            health.markHealthy()
        }
    }

    func testOldUnconfirmedLaunchesDoNotAccumulate() {
        var health = LaunchHealth()
        XCTAssertFalse(health.launch(now: t0))
        XCTAssertFalse(health.launch(now: t0.addingTimeInterval(3 * 3600)), "a launch from hours ago is not evidence of a loop")
        XCTAssertFalse(health.launch(now: t0.addingTimeInterval(6 * 3600)))
    }

    func testPersistsAsJSON() throws {
        var health = LaunchHealth()
        _ = health.launch(now: t0)
        let decoded = try JSONDecoder().decode(LaunchHealth.self, from: JSONEncoder().encode(health))
        XCTAssertEqual(decoded, health)
    }
}
