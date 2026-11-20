import XCTest
@testable import VelaCore

final class HeadingFilterTests: XCTestCase {
    func testShortestDeltaCrossesNorthTheShortWay() {
        XCTAssertEqual(HeadingFilter.shortestDelta(from: 350, to: 10), 20, accuracy: 1e-9)
        XCTAssertEqual(HeadingFilter.shortestDelta(from: 10, to: 350), -20, accuracy: 1e-9)
        XCTAssertEqual(abs(HeadingFilter.shortestDelta(from: 0, to: 180)), 180, accuracy: 1e-9)
    }

    func testFirstReadingIsTakenAsIs() {
        XCTAssertEqual(HeadingFilter.smooth(previous: nil, raw: 359, dt: 0.1), 359, accuracy: 1e-9)
        XCTAssertEqual(HeadingFilter.smooth(previous: nil, raw: -1, dt: 0.1), 359, accuracy: 1e-9)
    }

    func testNoiseIsSmoothedButARealTurnFollows() {
        // A 2° wobble while the phone is still barely moves the arrow.
        let held = HeadingFilter.smooth(previous: 90, raw: 92, dt: 0.05)
        XCTAssertLessThan(abs(held - 90), 1.0)
        // The same reading for a whole second follows it.
        let followed = HeadingFilter.smooth(previous: 90, raw: 180, dt: 1.0)
        XCTAssertGreaterThan(followed, 150)
        XCTAssertLessThanOrEqual(followed, 180)
    }

    func testWrapAroundStaysContinuous() {
        var heading = 350.0
        for _ in 0..<10 { heading = HeadingFilter.smooth(previous: heading, raw: 10, dt: 0.1) }
        XCTAssertTrue(heading == 10 || heading > 350 || heading < 10, "went the short way through north")
    }
}
