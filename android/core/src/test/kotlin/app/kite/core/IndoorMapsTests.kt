package app.kite.core

import kotlin.test.Test
import kotlin.test.assertEquals

class IndoorMapsTests {
    @Test fun keepsMixedFloorsAndNamedFacilities() {
        val plan = IndoorMaps.parsePlan("""
            {"elements":[
              {"type":"node","lat":50.0,"lon":14.0,"tags":{"level":"-1;0;0.5","highway":"elevator"}},
              {"type":"way","geometry":[{"lat":50.0,"lon":14.0},{"lat":50.001,"lon":14.001}],
                "tags":{"level":"1","indoor":"corridor"}},
              {"type":"node","lat":50.0,"lon":14.0,"tags":{"level":"0","amenity":"toilets"}},
              {"type":"node","lat":50.0,"lon":14.0,"tags":{"level":"2","shop":"clothes","access":"private"}}
            ]}
        """.trimIndent().toByteArray())
        assertEquals(listOf("1", "0.5", "0", "-1"), plan.floors)
        assertEquals(listOf("Lift", null, "Toilets"), plan.features.map { it.name })
        assertEquals(2, plan.features[1].geometry.size)
    }
}
