import XCTest
@testable import VelaCore

final class DiagnosticsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 10_000)

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testPositionsAreDroppedUnlessDetailedModeIsOn() {
        let log = DiagnosticsLog()
        log.record("fix", position: LatLng(50.08804, 14.42076), at: t0)
        XCTAssertNil(log.snapshot(now: t0)[0].position)
        log.setDetailed(true)
        log.record("fix", position: LatLng(50.08804, 14.42076), at: t0)
        XCTAssertNotNil(log.snapshot(now: t0)[1].position)
        log.setDetailed(false)
        XCTAssertTrue(log.snapshot(now: t0).allSatisfy { $0.position == nil }, "switching it off forgets the positions")
    }

    func testReportNeverContainsAbsoluteCoordinatesEvenWithConsent() throws {
        let log = DiagnosticsLog()
        log.setDetailed(true)
        log.record("fix", ["along": "120", "note": "at 50.08804,14.42076 near a@b.cz"], position: LatLng(50.08804, 14.42076), at: t0)
        log.record("fix", position: LatLng(50.08804, 14.42276), at: t0.addingTimeInterval(3))
        let text = String(decoding: log.report(appVersion: "1.0", includeTrack: true, now: t0.addingTimeInterval(4)), as: UTF8.self)
        XCTAssertFalse(text.contains("50.088"))
        XCTAssertFalse(text.contains("14.42"))
        XCTAssertFalse(text.contains("a@b.cz"))
        let doc = try json(Data(text.utf8))
        XCTAssertEqual(doc["containsTrack"] as? Bool, true)
        let events = try XCTUnwrap(doc["events"] as? [[String: Any]])
        XCTAssertEqual(events[0]["east"] as? Double, 0)
        let east = try XCTUnwrap(events[1]["east"] as? Double)
        XCTAssertEqual(east, 0.002 * 111_320 * cos(50.08804 * .pi / 180), accuracy: 0.5)
    }

    func testReportWithoutConsentHasNoTrackAtAll() throws {
        let log = DiagnosticsLog()
        log.setDetailed(true)
        log.record("fix", position: LatLng(50, 14), at: t0)
        let doc = try json(log.report(appVersion: "1.0", includeTrack: false, now: t0))
        XCTAssertEqual(doc["containsTrack"] as? Bool, false)
        let events = try XCTUnwrap(doc["events"] as? [[String: Any]])
        XCTAssertNil(events[0]["east"])
        XCTAssertNil(events[0]["north"])
    }

    func testRetentionAndCapacityAreBounded() {
        let log = DiagnosticsLog(retention: 60, capacity: 3)
        for i in 0..<5 { log.record("e\(i)", at: t0.addingTimeInterval(Double(i))) }
        XCTAssertEqual(log.snapshot(now: t0.addingTimeInterval(5)).map(\.kind), ["e2", "e3", "e4"])
        XCTAssertTrue(log.snapshot(now: t0.addingTimeInterval(500)).isEmpty, "old events expire")
    }

    func testSanitizerStripsCoordinatesAndEmailsAndCapsLength() {
        XCTAssertEqual(DiagnosticRedactor.sanitize("lat -33.86882 lng 151.20929"), "lat <number> lng <number>")
        XCTAssertEqual(DiagnosticRedactor.sanitize("speed 13.4"), "speed 13.4")
        XCTAssertEqual(DiagnosticRedactor.sanitize("mail me@example.com"), "mail <email>")
        XCTAssertEqual(DiagnosticRedactor.sanitize(String(repeating: "x", count: 500)).count, 120)
        XCTAssertEqual(DiagnosticRedactor.coarse(LatLng(50.08804, 14.42076)), "50.09,14.42")
    }
}
