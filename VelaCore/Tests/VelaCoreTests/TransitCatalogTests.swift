import XCTest
@testable import VelaCore

final class TransitCatalogTests: XCTestCase {
    private let csv = """
    id,data_type,entity_type,location.country_code,location.subdivision,location.municipality,provider,is_official,name,note,feed_contact_email,static_reference,urls.direct_download,urls.authentication_type,urls.authentication_info,urls.api_key_parameter_name,urls.latest,urls.license,location.bounding_box.minimum_latitude,location.bounding_box.maximum_latitude,location.bounding_box.minimum_longitude,location.bounding_box.maximum_longitude,location.bounding_box.extracted_on,status,features,redirect.id,redirect.comment
    mdb-1,gtfs_rt,tu|vp,DE,,Berlin,BVG,1,BVG live,,"a@b.c",static-1,https://example.com/rt,0,,,,CC-BY-4.0,52.3,52.7,13.1,13.8,2026-01-01,active,,
    mdb-2,gtfs_rt,tu,US,,New York,MTA,1,MTA live,,"a@b.c",static-2,https://example.com/ny,1,,,,CC-BY-4.0,40.4,41.0,-74.3,-73.6,2026-01-01,active,,
    mdb-3,gtfs_rt,tu,FR,,Paris,RATP,1,Dev only,development purposes,,"a@b.c",static-3,https://example.com/dev,0,,,,CC-BY-4.0,48.6,49.0,2.1,2.6,2026-01-01,active,,
    mdb-4,gtfs_rt,tu,JP,,Tokyo,Toei,1,Toei live,,"a@b.c",static-4,https://example.com/jp,0,,,,CC-BY-4.0,35.4,35.9,139.4,140.0,2026-01-01,inactive,,
    mdb-5,gtfs, ,GB,,London,TfL,1,Static only,,"a@b.c",static-5,https://example.com/static,0,,,,CC-BY-4.0,51.2,51.8,-0.6,0.3,2026-01-01,active,,
    """

    func testParsesOnlyPublicActiveRealtimeFeeds() {
        let feeds = TransitCatalog.parse(csv)
        XCTAssertEqual(feeds.map(\.id), ["mdb-1"])
        let feed = feeds[0]
        XCTAssertTrue(feed.hasTripUpdates)
        XCTAssertTrue(feed.hasVehiclePositions)
        XCTAssertEqual(feed.status, "active")
        XCTAssertEqual(feed.license, "CC-BY-4.0")
        XCTAssertEqual(feed.entities, "tu|vp")
    }

    func testDistanceUsesTheCoverageBox() {
        let feed = TransitCatalog.parse(csv)[0]
        XCTAssertEqual(feed.distanceMeters(to: LatLng(52.5, 13.4)), 0, accuracy: 1)
        XCTAssertGreaterThan(feed.distanceMeters(to: LatLng(48.8, 2.3)), 700_000)
    }

    func testQuotedCommasAndEscapedQuotes() {
        let text = """
        id,data_type,entity_type,location.country_code,location.subdivision,location.municipality,provider,is_official,name,note,feed_contact_email,static_reference,urls.direct_download,urls.authentication_type,urls.authentication_info,urls.api_key_parameter_name,urls.latest,urls.license,location.bounding_box.minimum_latitude,location.bounding_box.maximum_latitude,location.bounding_box.minimum_longitude,location.bounding_box.maximum_longitude,location.bounding_box.extracted_on,status,features,redirect.id,redirect.comment
        mdb-9,gtfs_rt,tu,CA,,Toronto,"TTC, Inc.",1,"Live, ""real"" data",,"a@b.c",static-9,https://example.com/ca,0,,,,CC-BY-4.0,43.5,43.9,-79.6,-79.1,2026-01-01,active,,
        """
        let feeds = TransitCatalog.parse(text)
        XCTAssertEqual(feeds.count, 1)
        XCTAssertEqual(feeds[0].provider, "TTC, Inc.")
        XCTAssertEqual(feeds[0].name, "Live, \"real\" data")
    }
}
