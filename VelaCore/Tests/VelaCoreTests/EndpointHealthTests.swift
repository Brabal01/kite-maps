import XCTest
@testable import VelaCore

final class EndpointHealthTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let a = "https://a.example/api"
    private let b = "https://b.example/api"

    func testARateLimitBlocksAtOnceAndHonoursRetryAfter() {
        let health = EndpointHealth()
        health.recordFailure(a, .rateLimited(retryAfter: 120), now: now)
        XCTAssertFalse(health.isAvailable(a, now: now.addingTimeInterval(119)))
        XCTAssertTrue(health.isAvailable(a, now: now.addingTimeInterval(121)))
        XCTAssertTrue(health.isAvailable(b, now: now), "other mirrors stay usable")
        XCTAssertEqual(health.available([a, b], now: now), [b])
    }

    func testARateLimitWithoutRetryAfterStillBacksOff() {
        let health = EndpointHealth()
        health.recordFailure(a, .rateLimited(retryAfter: nil), now: now)
        XCTAssertFalse(health.isAvailable(a, now: now.addingTimeInterval(10)))
    }

    func testRetryAfterIsCapped() {
        let health = EndpointHealth()
        health.recordFailure(a, .rateLimited(retryAfter: 86_400), now: now)
        XCTAssertTrue(health.isAvailable(a, now: now.addingTimeInterval(1_801)))
    }

    func testOneTimeoutIsForgivenButRepeatedOnesBackOffExponentially() {
        let health = EndpointHealth()
        health.recordFailure(a, .timeout, now: now)
        XCTAssertTrue(health.isAvailable(a, now: now), "a single timeout is not a verdict")
        health.recordFailure(a, .timeout, now: now)
        XCTAssertFalse(health.isAvailable(a, now: now.addingTimeInterval(39)))
        XCTAssertTrue(health.isAvailable(a, now: now.addingTimeInterval(41)))
        // The probe after the block fails too: the delay doubles again.
        let later = now.addingTimeInterval(41)
        health.recordFailure(a, .timeout, now: later)
        XCTAssertFalse(health.isAvailable(a, now: later.addingTimeInterval(79)))
        XCTAssertTrue(health.isAvailable(a, now: later.addingTimeInterval(81)))
    }

    func testBackoffIsCapped() {
        let health = EndpointHealth()
        for _ in 0..<30 { health.recordFailure(a, .serverError, now: now) }
        XCTAssertTrue(health.isAvailable(a, now: now.addingTimeInterval(901)))
    }

    func testSuccessClearsTheCircuit() {
        let health = EndpointHealth()
        health.recordFailure(a, .rateLimited(retryAfter: 600), now: now)
        health.recordSuccess(a)
        XCTAssertTrue(health.isAvailable(a, now: now))
        health.recordFailure(a, .timeout, now: now)
        XCTAssertTrue(health.isAvailable(a, now: now), "the failure count restarted")
    }

    func testSecondsUntilAvailableReportsTheSoonestMirror() {
        let health = EndpointHealth()
        health.recordFailure(a, .rateLimited(retryAfter: 300), now: now)
        health.recordFailure(b, .rateLimited(retryAfter: 100), now: now)
        XCTAssertEqual(health.secondsUntilAvailable([a, b], now: now), 100, accuracy: 0.01)
        XCTAssertEqual(health.secondsUntilAvailable([a, b, "c"], now: now), 0)
    }

    func testRetryAfterHeaderParsing() {
        XCTAssertEqual(EndpointHealth.retryAfter("30"), 30)
        XCTAssertNil(EndpointHealth.retryAfter("soon"))
        XCTAssertNil(EndpointHealth.retryAfter(nil))
        let date = EndpointHealth.retryAfter("Wed, 21 Oct 2015 07:28:30 GMT",
                                             now: Date(timeIntervalSince1970: 1_445_412_480))
        XCTAssertEqual(date ?? -1, 30, accuracy: 0.5)
    }

    func testStatusClassification() {
        XCTAssertEqual(EndpointHealth.failure(forStatus: 429, retryAfter: 5), .rateLimited(retryAfter: 5))
        XCTAssertEqual(EndpointHealth.failure(forStatus: 504, retryAfter: nil), .timeout)
        XCTAssertEqual(EndpointHealth.failure(forStatus: 502, retryAfter: nil), .serverError)
        XCTAssertNil(EndpointHealth.failure(forStatus: 400, retryAfter: nil), "a bad query is not the server's fault")
        XCTAssertNil(EndpointHealth.failure(forStatus: 200, retryAfter: nil))
    }
}
