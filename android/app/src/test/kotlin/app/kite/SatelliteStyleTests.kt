package app.kite

import app.kite.core.Json
import app.kite.core.asMap
import app.kite.core.asMaps
import app.kite.core.int
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import org.junit.Test

class SatelliteStyleTests {
    @Test fun bothRenderersUseImageryAsTheBasemap() {
        for (mapbox in listOf(false, true)) {
            val root = assertNotNull(Json.obj(SatelliteStyle.json(mapbox).encodeToByteArray()))
            assertNull(root["imports"])
            val layers = assertNotNull(root["layers"].asMaps())
            val imagery = layers.single { it["type"] == "raster" }
            val sources = assertNotNull(root["sources"].asMap())
            val source = assertNotNull(sources[imagery["source"]].asMap())
            assertEquals("raster", source["type"])
            assertEquals(listOf("${SatelliteStyle.URL}/tile/{z}/{y}/{x}?blankTile=false"), source["tiles"])
            assertEquals(21, source["maxzoom"].int())
            assertEquals("background", layers.first()["type"])
            assertEquals(1, layers.indexOf(imagery))
            val slots = layers.drop(2).map { it["id"] to it["type"] }
            assertEquals(if (mapbox) listOf("bottom" to "slot", "middle" to "slot", "top" to "slot") else emptyList(), slots)
        }
    }
}
