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

    func testParallelLaneAndDirectionWithOverpassWayGeometry() {
        let route = [LatLng(49.59, 17.25), LatLng(49.59, 17.26)]
        let data = Data("""
        {"elements":[
          {"id":10,"lat":49.59005,"lon":17.251,"tags":{"highway":"traffic_signals"}},
          {"id":20,"lat":49.59009,"lon":17.252,"tags":{"highway":"traffic_signals"}},
          {"id":30,"lat":49.59,"lon":17.253,"tags":{"highway":"traffic_signals","traffic_signals:direction":"backward"}},
          {"id":40,"lat":49.59,"lon":17.254,"tags":{"highway":"traffic_signals","traffic_signals:direction":"E"}},
          {"type":"way","id":100,"nodes":[10],"geometry":[{"lat":49.59,"lon":17.2505},{"lat":49.59005,"lon":17.251},{"lat":49.59,"lon":17.2515}]},
          {"type":"way","id":200,"nodes":[20],"geometry":[{"lat":49.59009,"lon":17.2515},{"lat":49.59009,"lon":17.2525}]},
          {"type":"way","id":300,"nodes":[30],"geometry":[{"lat":49.59,"lon":17.2525},{"lat":49.59,"lon":17.2535}]}
        ]}
        """.utf8)
        let matched = RouteRoadEvent.matched(data, line: route, traveled: 0)
        XCTAssertEqual(matched.map(\.id), [10, 40])
        XCTAssertEqual(matched[0].point.lat, route[0].lat, accuracy: 0.000001)
    }

}
