import Foundation
import XCTest
@testable import VelaCore

final class KiteLinksTests: XCTestCase {
    func testOpensMapSearchAndLocalShortcuts() {
        XCTAssertEqual(parse("kite://map"), .map)
        XCTAssertEqual(parse("kite://search?q=%C4%8Cerpac%C3%AD%20stanice"), .search("Čerpací stanice"))
        XCTAssertEqual(parse("kite://shortcut?id=shortcut%3Ahome-2"), .shortcut("shortcut:home-2"))
        XCTAssertEqual(parse("kite://work"), .work)
    }

    func testValidatesCoordinatesAndDistinguishesMapFromDirections() {
        let point = LatLng(49.6, 17.25)
        XCTAssertEqual(parse("kite://place?lat=49.6&lng=17.25"), .place(point, name: nil, directions: false))
        let shared = KiteLinks.placeURL(at: point, name: "Šantovka & Olomouc", directions: true)
        XCTAssertEqual(shared.flatMap(KiteLinks.parse), .place(point, name: "Šantovka & Olomouc", directions: true))
        for bad in ["kite://place?lat=NaN&lng=17", "kite://directions?lat=49.6&lng=180.1",
                    "kite://place?lat=49&lat=50&lng=17", "kite://place/other?lat=49&lng=17",
                    "kite://user@place?lat=49&lng=17", "kite://shortcut", "https://map/?lat=49.6&lng=17.25"] {
            XCTAssertNil(parse(bad), bad)
        }
    }

    private func parse(_ value: String) -> KiteLinks.Target? {
        URL(string: value).flatMap(KiteLinks.parse)
    }
}
