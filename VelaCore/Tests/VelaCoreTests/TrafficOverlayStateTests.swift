import XCTest
@testable import VelaCore

final class TrafficOverlayStateTests: XCTestCase {
    func testRequestedButNotLoadedIsLoadingNotOn() {
        let s = TrafficOverlayState.map(true, provider: .apple, renderer: "MapKit",
                                        rendererReady: true, dataLoaded: false)
        XCTAssertEqual(s.status, .loading)
        XCTAssertFalse(s.isVisible)
    }

    func testOffWhenNotRequested() {
        let s = TrafficOverlayState.map(false, provider: .apple, renderer: "MapKit",
                                        rendererReady: true, dataLoaded: true)
        XCTAssertEqual(s.status, .off)
        XCTAssertFalse(s.isVisible)
    }

    func testOnWhenLoaded() {
        let s = TrafficOverlayState.map(true, provider: .apple, renderer: "MapKit",
                                        rendererReady: true, dataLoaded: true,
                                        receivedAt: Date(), dataAge: 60)
        XCTAssertEqual(s.status, .on)
        XCTAssertTrue(s.isVisible)
    }

    func testNoGoogleMapLibreProviderIsCoverage() {
        // The MapLibre provider is Google tiles; with noGoogle set there is no overlay at all.
        let s = TrafficOverlayState.map(true, provider: .none, renderer: "MapLibre",
                                        rendererReady: true, dataLoaded: false,
                                        reason: "noGoogle")
        XCTAssertEqual(s.status, .noCoverage)
        XCTAssertFalse(s.isVisible)
    }

    func testErrorIsUnavailable() {
        let s = TrafficOverlayState.map(true, provider: .google, renderer: "MapLibre",
                                        rendererReady: true, dataLoaded: false,
                                        lastError: "tiles 403")
        XCTAssertEqual(s.status, .unavailable)
    }

    func testRendererNotReadyIsUnavailable() {
        let s = TrafficOverlayState.map(true, provider: .apple, renderer: "MapKit",
                                        rendererReady: false, dataLoaded: false)
        XCTAssertEqual(s.status, .unavailable)
    }

    func testKindSeparation() {
        // The three traffic kinds are distinct models, not one fuzzy "traffic" flag.
        XCTAssertEqual(TrafficOverlayState.map(false, provider: .none, renderer: "x",
                                               rendererReady: true, dataLoaded: false).kind, .map)
        let r = TrafficOverlayState(kind: .route, provider: .apple, renderer: "MapKit",
                                    requested: true, rendererReady: true, dataLoaded: true,
                                    receivedAt: nil, dataAge: nil, legend: nil, reason: nil, lastError: nil)
        XCTAssertEqual(r.kind, .route)
    }

    func testLegacyTrafficSurvives() {
        // The existing single "traffic" toggle still maps to the map overlay.
        let on = TrafficOverlayState.map(true, provider: .apple, renderer: "MapKit",
                                         rendererReady: true, dataLoaded: true)
        XCTAssertTrue(on.isVisible)
    }
}