package app.kite.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class OpenPlaceSearchTests {
    @Test fun resolvesCzechCategoryNamesAndOffersCompletion() {
        assertEquals(OutdoorData.WATER, OutdoorData.kind("  PITNÁ   VODA "))
        assertEquals(OutdoorData.WATER, OutdoorData.kind("pítka"))
        assertEquals("bicycle_parking", OutdoorData.kind("stojany na kola"))
        assertEquals("viewpoint", OutdoorData.kind("vyhlídky"))
        assertTrue("Drinking water" in OutdoorData.categorySuggestions("pít"))
        assertNull(OutdoorData.kind("Kaufland"))
        assertNull(OutdoorData.classicKind("lavičky"))
    }

    @Test fun recognizesUnnamedTapsFountainsAndSpringsWithPotableWater() {
        val fixtures = """{"elements":[
          {"id":1,"type":"node","lat":50.08,"lon":14.42,"tags":{"amenity":"drinking_water"}},
          {"id":2,"type":"node","lat":50.08,"lon":14.43,"tags":{"man_made":"water_tap","drinking_water":"yes"}},
          {"id":3,"type":"way","center":{"lat":50.08,"lon":14.44},"tags":{"amenity":"fountain","drinking_water":"yes"}},
          {"id":4,"type":"node","lat":50.08,"lon":14.45,"tags":{"natural":"spring","drinking_water":"yes"}},
          {"id":5,"type":"node","lat":50.08,"lon":14.46,"tags":{"amenity":"fountain","drinking_water":"no"}}
        ]}"""
        val places = OutdoorData.parsePlaces(fixtures.toByteArray())
        assertEquals(listOf("osm:N1", "osm:N2", "osm:W3", "osm:N4", "osm:N5"), places.map { it.id })
        assertTrue(places.take(4).all { it.category == "Drinking water" && it.source == "osm" })
        assertEquals("Fountain", places.last().category)
    }
}
