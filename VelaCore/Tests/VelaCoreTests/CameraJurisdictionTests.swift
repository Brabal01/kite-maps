import XCTest
@testable import VelaCore

final class CameraJurisdictionTests: XCTestCase {
    func testKnownCountries() {
        for code in ["FR", "DE", "CH", "CY", "SK", "TR"] {
            XCTAssertEqual(CameraJurisdiction.policy(isoCountryCode: code), .restricted)
        }
        XCTAssertEqual(CameraJurisdiction.policy(isoCountryCode: "gb"), .allowed, "codes are case-insensitive")
        XCTAssertEqual(CameraJurisdiction.policy(isoCountryCode: "CZ"), .allowed)
    }

    func testUnknownIsNeverAllowedByDefault() {
        XCTAssertEqual(CameraJurisdiction.policy(isoCountryCode: nil), .unknown)
        XCTAssertEqual(CameraJurisdiction.policy(isoCountryCode: ""), .unknown)
        XCTAssertEqual(CameraJurisdiction.policy(isoCountryCode: "CZE"), .unknown)
        XCTAssertFalse(CameraJurisdiction.warningsEnabled(userPreference: true, policy: .unknown,
                                                          userAcceptsResponsibility: false))
    }

    func testDeviceRegionIsOnlyAHintAfterExplicitAcceptance() {
        XCTAssertEqual(CameraJurisdiction.policy(isoCountryCode: nil, deviceRegion: "FR", userAcceptsResponsibility: false), .unknown)
        XCTAssertEqual(CameraJurisdiction.policy(isoCountryCode: nil, deviceRegion: "FR", userAcceptsResponsibility: true), .restricted)
        XCTAssertEqual(CameraJurisdiction.policy(isoCountryCode: "CZ", deviceRegion: "FR", userAcceptsResponsibility: true), .allowed,
                       "a verified location wins over the device region")
    }

    func testResponsibilityAcknowledgementCannotOverrideAKnownRestriction() {
        XCTAssertFalse(CameraJurisdiction.warningsEnabled(userPreference: true, policy: .restricted,
                                                          userAcceptsResponsibility: true))
        XCTAssertFalse(CameraJurisdiction.warningsEnabled(userPreference: false, policy: .allowed,
                                                          userAcceptsResponsibility: true))
        XCTAssertTrue(CameraJurisdiction.warningsEnabled(userPreference: true, policy: .unknown,
                                                         userAcceptsResponsibility: true))
    }
}
