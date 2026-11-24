import Foundation
import XCTest
@testable import VelaCore

final class RouteRoadEventTests: XCTestCase {
    func testKeepsOnlyNearbyEventsWithCompatibleDirection() throws {
        let line = [LatLng(49.59, 17.25), LatLng(49.59, 17.26)]
        let data = Data("""
        {"elements":[
          {"id":1,"lat":49.59,"lon":17.251,"tags":{"highway":"traffic_signals"}},
          {"id":2,"lat":49.5902,"lon":17.251,"tags":{"highway":"traffic_signals"}},
          {"id":3,"lat":49.59,"lon":17.252,"tags":{"highway":"stop","direction":"270"}},
          {"id":4,"lat":49.59,"lon":17.253,"tags":{"highway":"stop","direction":"90"}},
          {"id":5,"lat":49.59,"lon":17.254,"tags":{"railway":"level_crossing"}}
        ]}
        """.utf8)
        let events = RouteRoadEvent.matched(data, line: line, traveled: 500)
        XCTAssertEqual(events.map(\.id), [1, 4, 5])
        XCTAssertEqual(events.map(\.kind), [.trafficLight, .stop, .railway])
        XCTAssertTrue(events.allSatisfy { $0.along > 500 })
    }
}
