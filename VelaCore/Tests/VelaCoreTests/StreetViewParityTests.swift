import XCTest
@testable import VelaCore

final class StreetViewParityTests: XCTestCase {
    func testReadsNestedPanoramaAndReportedTileLevels() throws {
        let node = #"""
        [[1],[2,"AbCdEfGhIjKlMnOpQrStUv"],[null,null,null,[[[[256,512]],[[512,1024]],[[1024,2048]]],[512,512]]],null,null,[[null,[[null,null,50.087,14.421],null,[252.5]]]]]
        """#
        let direct = try XCTUnwrap(StreetView.parse("[[0],\(node)]"))
        XCTAssertEqual(StreetView.parse(")]}'\n[[0],[\(node)]]"), direct)
        XCTAssertEqual(direct.location, LatLng(50.087, 14.421))
        XCTAssertEqual(direct.heading, 252.5)
        XCTAssertEqual(direct.tileSize, 512)
        XCTAssertEqual(direct.size(zoom: 2).width, 2048)
        XCTAssertEqual(direct.size(zoom: 2).height, 1024)
    }

    func testWalkDirectionExcludesHistoricalAndRedundantLinks() throws {
        let response = #"""
        [[0],[[1],[2,"AbCdEfGhIjKlMnOpQrStUv"],null,null,null,[[null,
          [[null,null,50.087,14.421],null,[252.5]],null,
          [[[[2,"firstWalkPanorama12345"],null,[[null,null,50.08709,14.421]]],
            [[2,"nextWalkPanorama123456"],null,[[null,null,50.0872,14.421]]],
            [[2,"olderViewPanorama12345"],null,[[null,null,50.087,14.42115]]]]],null,null,null,null,
          [[2,[2020,1]]]]]]]
        """#
        let pano = try XCTUnwrap(StreetView.parse(response))
        XCTAssertEqual(pano.links.map(\.id), ["firstWalkPanorama12345"])
        XCTAssertEqual(try XCTUnwrap(pano.step(facing: 350)).bearing, 0, accuracy: 0.001)
        XCTAssertNil(pano.step(facing: 180))
    }
}
