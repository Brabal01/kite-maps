import XCTest
@testable import VelaCore

final class ArrivalParkingTests: XCTestCase {
    func testParkingOfferRequiresTheLastKilometerAndNoRemainingStops() {
        XCTAssertTrue(ArrivalHelp.offerParking(remainingMeters: 1000, stopsRemaining: 0, offRoute: false))
        XCTAssertFalse(ArrivalHelp.offerParking(remainingMeters: 1001, stopsRemaining: 0, offRoute: false))
        XCTAssertFalse(ArrivalHelp.offerParking(remainingMeters: 300, stopsRemaining: 1, offRoute: false))
        XCTAssertFalse(ArrivalHelp.offerParking(remainingMeters: 300, stopsRemaining: 0, offRoute: true))
        XCTAssertFalse(ArrivalHelp.offerParking(remainingMeters: 0, stopsRemaining: 0, offRoute: false))
    }
}
