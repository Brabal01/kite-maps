import XCTest
@testable import VelaCore

final class TransitRailGeometryTests: XCTestCase {
    func testOlomoucTramRemovesOnlyTheUnservedBranch() {
        let start = LatLng(49.592316, 17.277658)
        let stop = LatLng(49.59436, 17.27148)
        let spike = LatLng(49.59093, 17.27153)
        let after = LatLng(49.59465, 17.27030)
        let end = LatLng(49.59617, 17.26497)
        let line = [start, stop, spike, after, end]
        func call(_ position: LatLng) -> TransitCall {
            TransitCall(id: nil, name: "", location: position, arrival: nil, departure: nil,
                        platform: nil, arrivalDelay: nil, departureDelay: nil)
        }
        let calls = [start, stop, end].map(call)
        XCTAssertEqual(Transitous.withoutRailSpikes(line, calls: calls), [start, stop, after, end])
        XCTAssertEqual(Transitous.withoutRailSpikes(line, calls: calls + [call(spike)]), line)
    }
}
