package app.kite.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class MapboxDirectionsTests {
    private val fixture = """
        {
          "code": "Ok",
          "routes": [{
            "geometry": "??o}@?o}@?o}@?",
            "distance": 333.6,
            "duration": 45,
            "duration_typical": 40,
            "legs": [
              {
                "annotation": {"congestion": ["low"], "maxspeed": [{"speed": 30, "unit": "mph"}]},
                "steps": [
                  {"name": "First Road", "distance": 111.2, "maneuver": {"type": "depart", "location": [0, 0]}},
                  {"distance": 0, "maneuver": {"type": "arrive", "location": [0, 0.001]}}
                ]
              },
              {
                "annotation": {"congestion": ["heavy", "heavy"], "maxspeed": [{"speed": 30, "unit": "mph"}, {"unknown": true}]},
                "steps": [
                  {"name": "First Road", "distance": 111.2, "maneuver": {"type": "depart", "location": [0, 0.001]}},
                  {"name": "Second Road", "distance": 111.2, "maneuver": {
                    "type": "turn", "modifier": "left", "location": [0, 0.002], "instruction": "Bear left onto Second Road"
                  }, "intersections": [{"lanes": [
                    {"indications": ["left"], "valid": true}, {"indications": ["straight"], "valid": false}
                  ]}]},
                  {"distance": 0, "maneuver": {"type": "arrive", "location": [0, 0.003]}}
                ]
              }
            ]
          }]
        }
    """.trimIndent()

    @Test fun usesTrafficInstructionsAndLaneDataAcrossStops() {
        val route = MapboxDirections.parse(fixture.toByteArray()).single()
        val turn = route.maneuvers[1]
        assertEquals("mapbox", route.source)
        assertEquals(45.0, route.durationSeconds)
        assertEquals(40.0, route.typicalSeconds)
        assertEquals(listOf(ManeuverType.DEPART, ManeuverType.TURN_LEFT, ManeuverType.ARRIVE), route.maneuvers.map { it.type })
        assertEquals("Bear left onto Second Road", turn.instruction)
        assertEquals(listOf(true, false), turn.lanes.map { it.valid })
        assertEquals(222.4, turn.alongMeters, 0.1)
        assertEquals(30 * 1.609344, route.speedLimits.first().kmh)
        assertEquals(null, route.speedLimits.last().kmh)
        val span = route.trafficSpans.single()
        assertEquals(2, span.level)
        assertEquals(111.2, span.startMeters, 1.0)
        assertEquals(222.4, span.lengthMeters, 1.0)
    }

    @Test fun ignoresAnnotationsThatCannotBeAlignedToTheRoute() {
        val route = MapboxDirections.parse(fixture.replace("\"heavy\", \"heavy\"", "\"heavy\"")
            .replace(", {\"unknown\": true}", "").toByteArray()).single()
        assertTrue(route.trafficSpans.isEmpty())
        assertTrue(route.speedLimits.isEmpty())
    }

    @Test fun rejectsApiErrorsAndIncompleteTurnLists() {
        assertTrue(MapboxDirections.parse("""{"code":"NoRoute"}""".toByteArray()).isEmpty())
        assertTrue(MapboxDirections.parse(fixture.replace("\"arrive\"", "\"continue\"").toByteArray()).isEmpty())
    }
}
