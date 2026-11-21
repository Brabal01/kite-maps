import XCTest
@testable import VelaCore

final class AlertCoordinatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func alert(_ id: String, _ kind: AlertKind, _ severity: AlertSeverity,
                       distance: Double, bearing: Double? = nil, route: Double? = nil,
                       speed: Double? = nil, limit: Double? = nil,
                       confidence: Double = 1, age: TimeInterval = 0,
                       source: String = "test") -> AlertCandidate {
        AlertCandidate(id: id, kind: kind, source: source, severity: severity,
                       title: id, distanceMeters: distance,
                       eventBearing: bearing, routeBearing: route,
                       confidence: confidence, reportedAt: now.addingTimeInterval(-age),
                       speedLimitKmh: limit, vehicleSpeedKmh: speed)
    }

    func testTwoSourcesForOneEventBecomeOneCard() {
        var c = AlertCoordinator()
        let a = alert("waze-a", .accident, .warning, distance: 300, source: "waze")
        let b = alert("osm-a", .accident, .warning, distance: 305, source: "osm")
        let p = c.update([a, b], now: now)
        XCTAssertEqual(p.primary?.kind, .accident)
        XCTAssertTrue(p.queued.isEmpty)
    }

    func testOppositeDirectionEventIsNotShown() {
        var c = AlertCoordinator()
        let wrongWay = alert("reverse", .camera, .warning, distance: 120,
                             bearing: 180, route: 0, speed: 50, limit: 50)
        let p = c.update([wrongWay], now: now)
        XCTAssertNil(p.primary)
    }

    func testCameraOverTheLimitBeatsANearerHazard() {
        var c = AlertCoordinator()
        let hazard = alert("hazard", .hazard, .warning, distance: 80)
        let camera = alert("cam", .camera, .warning, distance: 220, speed: 60, limit: 50)
        let p = c.update([hazard, camera], now: now)
        XCTAssertEqual(p.primary?.id, "cam")
    }

    func testHysteresisStopsTwoSimilarAlertsFlickering() {
        var c = AlertCoordinator()
        let a = alert("a", .hazard, .warning, distance: 200)
        let b = alert("b", .hazard, .warning, distance: 190)
        XCTAssertEqual(c.update([a], now: now).primary?.id, "a")
        // A tiny later change must not swap the card every frame.
        XCTAssertEqual(c.update([a, b], now: now.addingTimeInterval(0.2)).primary?.id, "a")
        // A clearly closer, more severe event can take over.
        let severe = alert("severe", .closure, .critical, distance: 40)
        XCTAssertEqual(c.update([a, b, severe], now: now.addingTimeInterval(0.4)).primary?.id, "severe")
    }

    func testDismissedAlertStaysInCooldown() {
        var c = AlertCoordinator(cooldown: 30)
        let a = alert("cam", .camera, .warning, distance: 100, speed: 60, limit: 50)
        XCTAssertEqual(c.update([a], now: now).primary?.id, "cam")
        c.dismiss("cam", now: now)
        XCTAssertNil(c.update([a], now: now.addingTimeInterval(5)).primary)
        XCTAssertEqual(c.update([a], now: now.addingTimeInterval(31)).primary?.id, "cam")
    }

    func testUrgentManeuverSuppressesOrdinaryWarnings() {
        var c = AlertCoordinator()
        let hazard = alert("hazard", .hazard, .warning, distance: 80)
        let camera = alert("cam", .camera, .warning, distance: 100, speed: 55, limit: 50)
        let p = c.update([hazard, camera], now: now, maneuverUrgent: true)
        XCTAssertEqual(p.primary?.id, "cam", "a camera over the limit is still safety-critical")
        XCTAssertTrue(p.queued.isEmpty)
    }

    func testExpiredLowConfidenceAndReplyEventsAreDropped() {
        var c = AlertCoordinator()
        let expired = AlertCandidate(id: "expired", kind: .closure, source: "x",
                                     severity: .critical, title: "old", distanceMeters: 10,
                                     expiresAt: now.addingTimeInterval(-1))
        let weak = alert("weak", .hazard, .warning, distance: 20, confidence: 0.1)
        let reply = AlertCandidate(id: "reply", kind: .hazard, source: "x",
                                   severity: .warning, title: "reply", distanceMeters: 20,
                                   isReply: true)
        XCTAssertNil(c.update([expired, weak, reply], now: now).primary)
    }
}
