package app.kite.core

import kotlin.test.*

class GooglePlaceMediaTests {
    @Test fun structurallyReadsNestedPanoramaAndTileLevels() {
        val node = Json.parse("""[[1],[2,"AbCdEfGhIjKlMnOpQrStUv"],[null,null,null,[[[[256,512]],[[512,1024]],[[1024,2048]]],[512,512]]],null,null,[[null,[[null,null,50.087,14.421],null,[252.5]]]]]""")
        val direct = StreetView.parse(Json.write(listOf(listOf(0), node)))
        val byId = StreetView.parse(")]}'\n" + Json.write(listOf(listOf(0), listOf(node))))
        assertEquals(direct, byId)
        val p = assertNotNull(direct)
        assertEquals(2048 to 1024, p.size(2))
        assertEquals(512, p.tileSize)
        assertEquals(252.5, p.heading)
        assertEquals(LatLng(50.087, 14.421), p.location)
    }

    @Test fun separatesGalleryPhotosFromAvatarsAndStreetView() {
        val paths = listOf("https://lh3.googleusercontent.com/gps-cs-s/photoA=w400-h400",
            "https://lh3.googleusercontent.com/gps-cs-s/photoA=w80-h80",
            "https://lh4.googleusercontent.com/p/AF1QipPhotoB=s640",
            "https://lh3.googleusercontent.com/a/Avatar",
            "https://streetviewpixels-pa.googleapis.com/v1/thumbnail?panoid=AbCdEfGhIjKlMnOpQrStUv&yaw=22")
        assertEquals(listOf("https://lh3.googleusercontent.com/gps-cs-s/photoA=w800-h600",
            "https://lh4.googleusercontent.com/p/AF1QipPhotoB=w800-h600"), GooglePlaceMedia.imageUrls(paths, 10))
        assertEquals(StreetView.Hint("AbCdEfGhIjKlMnOpQrStUv", 22.0), GooglePlaceMedia.streetViewHint(paths))
        val row = listOf("wrb.fr", "hspqX", Json.write(listOf(paths)))
        val envelope = ")]}'\n\n100\n" + Json.write(listOf(row))
        assertEquals(2, GooglePlaceMedia.photos(envelope).size)
    }

    @Test fun parsesReviewsAndUsesUnsignedGoogleFeatureIds() {
        val json = Json.parse("""[null,null,[[[null,"Dana",null],"yesterday",null,"Good coffee",5],[[null,"Alex"],"last week",null,null,4]]]""")
        val reviews = GooglePlaceMedia.reviews(json)
        assertEquals(listOf("Dana", "Alex"), reviews.map { it.author })
        assertEquals("Good coffee", reviews.first().text)
        assertNull(reviews.last().text)
        assertContains(assertNotNull(GooglePlaceMedia.reviewParameter("0x1:0xffffffffffffffff")), "!2y18446744073709551615")
        assertEquals("18446744073709551615", GooglePlaceMedia.cid("0x1:0xffffffffffffffff"))
        assertNull(GooglePlaceMedia.photoRequest("not-a-feature-id"))
    }
}
