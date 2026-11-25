import XCTest
@testable import VelaCore

final class FuelPricesTests: XCTestCase {
    func testGoogleLabelsRequireARealPrice() {
        XCTAssertEqual(FuelPrices.googleLabel("$3.95/Regular"), "$3.95/Regular")
        XCTAssertEqual(FuelPrices.googleLabel("36,90\u{00a0}Kč/l"), "36,90 Kč/l")
        XCTAssertNil(FuelPrices.googleLabel("Diesel B7"))
        XCTAssertNil(FuelPrices.googleLabel("Open until 10 pm"))
    }

    func testUKPricesNeedAUniqueNearStationAndAFreshTimestamp() {
        let stations = FuelPrices.parseCSV("""
            brand,lat,lng,e10,e5,b7s,b7p,updated
            "A, Fuels",51.50000,-0.12000,153.9,,160,,1785000000
            B,51.50000,-0.12060,157,,162,,1785000000
            C,52.60,-1.3,999,,,,1785000000
            """)
        let now = Date(timeIntervalSince1970: 1_785_000_100)
        XCTAssertEqual(stations.count, 2)
        XCTAssertEqual(FuelPrices.match(LatLng(51.5, -0.12), stations: stations, now: now)?.labels,
                       ["E10 153.9 p/L", "Diesel 160 p/L"])
        XCTAssertNil(FuelPrices.match(LatLng(51.5, -0.1203), stations: stations, now: now))
        XCTAssertNil(FuelPrices.match(LatLng(51.5, -0.12), stations: stations, now: now.addingTimeInterval(8 * 86_400)))
    }

    func testReadsGzipAndRejectsCorruption() throws {
        let encoded = "H4sIAAAAAAACA8tJLNHJyUvXSTU00CktSEksSU3hMjXUM9XRNdAzNNIxNDXWs9QxNLcwNQADLgA68lecMAAAAA=="
        let fixture = try XCTUnwrap(Data(base64Encoded: encoded))
        let csv = try XCTUnwrap(FuelPrices.gunzip(fixture))
        XCTAssertEqual(FuelPrices.parseCSV(String(decoding: csv, as: UTF8.self)).first?.quote.labels, ["E10 153.9 p/L"])
        var broken = fixture
        broken[broken.count - 8] ^= 0xff
        XCTAssertNil(FuelPrices.gunzip(broken))
    }
}
