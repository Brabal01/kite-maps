package app.kite.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NavigationContinuityTests {
    @Test fun smallGpsDriftDoesNotJumpToTheReturnLeg() {
        val path = listOf(LatLng(50.0, 14.0), LatLng(50.005, 14.0),
            LatLng(50.005, 14.00012), LatLng(50.0, 14.00012))
        val route = Route(TravelMode.DRIVE, path, Geo.length(path), 130.0, null,
            null, mutableListOf(), source = "osm")
        val tracker = RouteTracker(route)
        val first = tracker.update(LatLng(50.0003, 14.00001))
        val jitter = tracker.update(LatLng(50.00045, 14.00010))
        assertTrue(jitter.alongMeters in first.alongMeters..65.0)
        assertEquals(14.0, jitter.snapped.lng, 0.00001)
    }

    @Test fun namesASharedJunctionButLeavesParallelRoadsUnlabelled() {
        val line = listOf(LatLng(50.0, 14.0), LatLng(50.005, 14.0))
        val branch = listOf(LatLng(50.001, 14.0), LatLng(50.001, 14.0014))
        val parallel = line.map { it.copy(lng = 14.00019) }
        val (current, signs) = NavigationStreetLabels.find(line, 40.0,
            listOf("Main Street" to line, "Market Street" to branch, "Service Lane" to parallel))
        assertEquals("Main Street", current)
        assertEquals("Market Street", signs.single().name)
        assertTrue(Geo.project(signs.single().at, line).offset > 25)
    }

    @Test fun timedTransitSegmentMatchesTheTripAndInterpolates() {
        val data = """[{"realTime":true,"trips":[{"tripId":"abc"}],
            "departure":"2026-11-24T11:00:00Z","arrival":"2026-11-24T11:02:00Z","polyline":"??oK?"}]""".toByteArray()
        val at = java.time.Instant.parse("2026-11-24T11:01:00Z").toEpochMilli()
        val point = assertNotNull(Transitous.parseMapSegment(data, "abc", at))
        assertEquals(0.001, point.lat, 0.00001)
        assertNull(Transitous.parseMapSegment(data, "different-trip", at))
    }
}
