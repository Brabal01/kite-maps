package app.kite.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class MapSearchTests {
    private val center = LatLng(50.08, 14.43)

    @Test fun submittedNameKeepsTheLocalAutocompletePlaceEvenIfFullSearchOnlyFindsDistantBranches() {
        val local = Place("prague", "OBI Praha", LatLng(50.15, 14.43), "google")
        val distant = Place("germany", "OBI Berlin", LatLng(52.52, 13.41), "google")
        val unrelated = Place("bakery", "Bakery", LatLng(50.09, 14.43), "google")
        assertEquals(listOf(local), PlaceSearch.forMap("obi", center, 1_500.0, listOf(distant), listOf(local, unrelated)))
    }

    @Test fun keepsTheRichResultInsteadOfDuplicatingItsAutocompletePin() {
        val coords = LatLng(50.10, 14.43)
        val match = Place("obi", "OBI", coords, "google", rating = 4.1)
        val suggestion = match.copy(id = "suggest", rating = null)
        assertEquals(listOf(match), PlaceSearch.forMap("obi", center, null, listOf(match), listOf(suggestion)))
    }

    @Test fun looksFartherForTheClosestBusinessWithoutFramingOtherCountries() {
        val regional = Place("regional", "OBI", LatLng(50.53, 14.43), "osm")
        val remote = Place("remote", "OBI", LatLng(47.50, 19.04), "osm")
        assertEquals(listOf(regional), PlaceSearch.forMap("obi", center, 1_500.0, listOf(remote, regional)))
        assertTrue(PlaceSearch.forMap("obi", center, 1_500.0, listOf(remote)).isEmpty())
    }

    @Test fun retainsADistantTownWhenExplicitlySearchedByName() {
        val town = Place("berlin", "Berlin", LatLng(52.52, 13.41), "osm", category = "City")
        assertEquals(listOf(town), PlaceSearch.forMap("Berlin", center, null, listOf(town)))
    }
}
