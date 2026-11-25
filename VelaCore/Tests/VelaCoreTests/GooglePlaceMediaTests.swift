import XCTest
@testable import VelaCore

final class GooglePlaceMediaTests: XCTestCase {
    func testSeparatesGalleryPhotosFromAvatarsAndStreetView() {
        let urls = [
            "https://lh3.googleusercontent.com/gps-cs-s/photoA=w400-h400",
            "https://lh3.googleusercontent.com/gps-cs-s/photoA=w80-h80",
            "//lh4.googleusercontent.com/p/AF1QipPhotoB=s640",
            "https://lh3.googleusercontent.com/a/Avatar",
            "https://streetviewpixels-pa.googleapis.com/v1/thumbnail?panoid=AbCdEfGhIjKlMnOpQrStUv&yaw=22",
            "https://lh3.googleusercontent.com.example.org/p/foreign",
            "https://lh3.googleusercontent.com@example.org/p/foreign",
            "http://lh3.googleusercontent.com/p/insecure"
        ]
        XCTAssertEqual(GooglePlaceMedia.gallery(batch("hspqX", [urls])), [
            "https://lh3.googleusercontent.com/gps-cs-s/photoA=w800-h600",
            "https://lh4.googleusercontent.com/p/AF1QipPhotoB=w800-h600"
        ])
    }

    func testParsesTextAndStarOnlyReviewsAndUnsignedIDs() {
        let source = #"[null,null,[[[null,"Dana",null],"yesterday",null,"Good coffee",5],[[null,"Alex"],"last week",null,null,4]]]"#
        let rows = GooglePlaceMedia.legacyReviews(source)
        XCTAssertEqual(rows.map(\.author), ["Dana", "Alex"])
        XCTAssertEqual(rows.map(\.rating), [5, 4])
        XCTAssertEqual(rows.first?.text, "Good coffee")
        XCTAssertNil(rows.last?.text)
        XCTAssertTrue(GooglePlaceMedia.legacyParameter("0x1:0xffffffffffffffff")?.contains("!2y18446744073709551615") == true)
        XCTAssertNotNil(GooglePlaceMedia.galleryRequest("0x1:0xffffffffffffffff"))
        XCTAssertNil(GooglePlaceMedia.galleryRequest("not-a-feature-id"))
        XCTAssertNil(GooglePlaceMedia.reviewsRequest("0x1:0x2\n"))
    }

    func testReadsReviewFeedWithContributorPhotosAndKeepsEachReview() {
        let source = #"[null,null,[[[null,[null,null,null,null,[null,null,null,null,null,["Dana"]],null,"yesterday"],[[5],null,[["https://lh3.googleusercontent.com/grass-cs/CustomerPhoto=k-no","https://lh3.googleusercontent.com/a/Avatar"]],null,null,null,null,null,null,null,null,null,null,null,null,[["Good coffee"]]]]]]]"#
        let rows = GooglePlaceMedia.reviewFeed(batch("qv9Egd", GoogleJSON.parse(source)))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.author, "Dana")
        XCTAssertEqual(rows.first?.rating, 5)
        XCTAssertEqual(rows.first?.time, "yesterday")
        XCTAssertEqual(rows.first?.text, "Good coffee")
        XCTAssertEqual(rows.first?.photos, ["https://lh3.googleusercontent.com/grass-cs/CustomerPhoto=w800-h600"])
        let legacy = GooglePlaceMedia.legacyReviews(#"[null,null,[[[null,"Dana"],null,null,"Good coffee",5],[[null,"Alex"],null,null,null,4]]]"#)
        let combined = GooglePlaceMedia.mergedReviews(legacy, rows)
        XCTAssertEqual(combined.map(\.author), ["Dana", "Alex"])
        XCTAssertEqual(combined.first?.photos, rows.first?.photos)
    }

    private func batch(_ method: String, _ payload: Any?) -> String {
        ")]}'\n\n100\n" + GoogleJSON.text([["wrb.fr", method, GoogleJSON.text(payload)]])
    }
}
