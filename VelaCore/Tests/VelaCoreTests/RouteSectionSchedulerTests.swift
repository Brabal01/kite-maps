import XCTest
@testable import VelaCore

final class RouteSectionSchedulerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 5_000)

    private func scheduler(_ meters: Double) -> RouteSectionScheduler {
        RouteSectionScheduler(totalMeters: meters)
    }

    func testSectionsAreRequestedNearestFirstAndOneAtATime() {
        var s = scheduler(20_000)
        XCTAssertEqual(s.sectionCount, 5)
        XCTAssertEqual(s.next(now: t0), 0)
        XCTAssertNil(s.next(now: t0), "only one request is in flight")
        s.succeeded(0)
        XCTAssertEqual(s.next(now: t0), 1)
    }

    func testALongRouteOnlyAsksForTheWindowAheadOfTheVehicle() {
        var s = scheduler(400_000)
        var asked: [Int] = []
        while let next = s.next(now: t0) { asked.append(next); s.succeeded(next) }
        XCTAssertEqual(asked, Array(0...6), "a 24 km look-ahead from the start: sections 0…6, not 100")
        XCTAssertTrue(s.isWindowLoaded)
        XCTAssertFalse(s.isRouteLoaded)
        s.updateProgress(100_000)
        XCTAssertEqual(s.next(now: t0), 25, "the section under the vehicle comes first")
    }

    func testPassedSectionsAreNeverRequested() {
        var s = scheduler(40_000)
        s.updateProgress(21_000)
        var asked: [Int] = []
        while let next = s.next(now: t0) { asked.append(next); s.succeeded(next) }
        XCTAssertEqual(asked.first, 5)
        XCTAssertFalse(asked.contains(0))
    }

    func testProgressNeverMovesBackwards() {
        var s = scheduler(40_000)
        s.updateProgress(10_000)
        s.updateProgress(2_000)
        XCTAssertEqual(s.progressMeters, 10_000)
    }

    func testFailureBacksOffExponentiallyThenGivesUp() {
        var config = RouteSectionScheduler.Config()
        config.breakerThreshold = 99
        var s = RouteSectionScheduler(totalMeters: 4_000, config: config)
        var now = t0
        var waits: [TimeInterval] = []
        for _ in 0..<config.maxAttempts {
            guard let index = s.next(now: now) else { return XCTFail("a retry was due") }
            s.failed(index, now: now)
            if case .failed(_, let retryAt) = s.statuses[0] {
                waits.append(retryAt.timeIntervalSince(now))
                XCTAssertNil(s.next(now: now.addingTimeInterval(1)), "not before the back-off ends")
                now = retryAt
            }
        }
        XCTAssertEqual(waits, [15, 30, 60])
        XCTAssertEqual(s.statuses[0], .abandoned)
        XCTAssertNil(s.next(now: now.addingTimeInterval(10_000)), "the retry budget is spent")
        XCTAssertTrue(s.hasUnavailableSection)
    }

    func testServerWaitOverridesTheShortBackoff() {
        var s = scheduler(4_000)
        let index = s.next(now: t0)!
        s.failed(index, now: t0, wait: 120)
        XCTAssertNil(s.next(now: t0.addingTimeInterval(100)))
        XCTAssertEqual(s.next(now: t0.addingTimeInterval(121)), 0)
    }

    func testCircuitBreakerStopsEverySectionAfterRepeatedFailures() {
        var s = scheduler(40_000)
        for _ in 0..<3 {
            let i = s.next(now: t0)!
            s.failed(i, now: t0)
        }
        // Sections 1 and 2 are pending and section 0.. are failed, but the breaker is open.
        XCTAssertNil(s.next(now: t0.addingTimeInterval(30)))
        XCTAssertNotNil(s.next(now: t0.addingTimeInterval(91)))
    }

    func testSuccessResetsTheBreaker() {
        var s = scheduler(40_000)
        let a = s.next(now: t0)!; s.failed(a, now: t0)
        let b = s.next(now: t0)!; s.failed(b, now: t0)
        s.succeeded(s.next(now: t0.addingTimeInterval(16))!)
        let c = s.next(now: t0.addingTimeInterval(16))!
        s.failed(c, now: t0.addingTimeInterval(16))
        XCTAssertNotNil(s.next(now: t0.addingTimeInterval(17)), "two failures in a row after a success do not trip it")
    }

    func testCancellationIsNotAFailure() {
        var s = scheduler(8_000)
        let i = s.next(now: t0)!
        s.cancelled(i)
        XCTAssertEqual(s.statuses[i], .pending)
        XCTAssertEqual(s.next(now: t0), i)
    }

    func testNextWakeReportsTheEarliestRetry() {
        var s = scheduler(4_000)
        let i = s.next(now: t0)!
        s.failed(i, now: t0)
        XCTAssertEqual(s.nextWake(now: t0)?.timeIntervalSince(t0) ?? -1, 15, accuracy: 0.01)
        var done = scheduler(4_000)
        done.succeeded(done.next(now: t0)!)
        XCTAssertNil(done.nextWake(now: t0))
    }

    func testEmptyRoute() {
        var s = scheduler(0)
        XCTAssertNil(s.next(now: t0))
        XCTAssertTrue(s.isRouteLoaded)
        XCTAssertFalse(s.hasUnavailableSection)
    }

    func testCacheReusesAnswersUntilTheyExpire() {
        let cache = RouteControlCache(lifetime: 60, capacity: 2)
        let line = [LatLng(50, 14), LatLng(50.01, 14.01)]
        let key = RouteControlCache.key(for: line, walking: false)
        XCTAssertNotEqual(key, RouteControlCache.key(for: line, walking: true))
        XCTAssertNil(cache.controls(for: key, now: t0))
        let light = RouteControl(kind: .light, location: LatLng(50.005, 14.005))
        cache.store([light], for: key, now: t0)
        XCTAssertEqual(cache.controls(for: key, now: t0.addingTimeInterval(59)), [light])
        XCTAssertNil(cache.controls(for: key, now: t0.addingTimeInterval(61)))
        cache.store([], for: "a", now: t0); cache.store([], for: "b", now: t0); cache.store([], for: "c", now: t0)
        XCTAssertNil(cache.controls(for: "a", now: t0), "the oldest entry was evicted")
        XCTAssertNotNil(cache.controls(for: "c", now: t0))
    }
}
