package app.kite.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TransitRideTests {
    @Test fun followsStopsAndRejectsBadGps() {
        val a = LatLng(50.0, 14.0)
        val b = a.copy(lat = 50.004)
        val c = a.copy(lat = 50.008)
        val stops = listOf(TransitCall("a", "Start", a, 1000, 1100), TransitCall("b", "Middle", b, 5000, 5200),
            TransitCall("c", "Transfer", c, 16_000, null))
        val ride = TransitRide(TransitLeg(false, "TRAM", path = listOf(a, b, c), calls = stops))
        assertEquals("b", ride.next?.stopId)
        assertEquals("c", ride.scheduledNext(8000)?.stopId)
        assertFalse(ride.observe(c, 300.0, 6000).nextChanged)
        assertEquals("b", ride.next?.stopId)
        assertFalse(ride.observe(c.copy(lng = 14.03), 10.0, 6100).exitApproach)
        assertTrue(ride.observe(b, 10.0, 6300).nextChanged)
        assertEquals("c", ride.next?.stopId)
        assertFalse(ride.nearExit)
        assertTrue(ride.observe(c, 12.0, 15_000).exitApproach)
        assertTrue(ride.nearExit)
    }

    @Test fun keepsTransitousWalkingStepsAndPlatform() {
        val data = """{"itineraries":[{"legs":[
          {"mode":"WALK","from":{"lat":50.0,"lon":14.0},"to":{"lat":50.002,"lon":14.0},
           "steps":[{"relativeDirection":"DEPART","distance":20},{"relativeDirection":"ELEVATOR","distance":20}]},
          {"mode":"TRAM","from":{"lat":50.002,"lon":14.0,"track":"2"},"to":{"lat":50.005,"lon":14.0}}
          ]}]}"""
        val legs = Transitous.parse(data.toByteArray()).single().legs
        assertEquals("Take the elevator", legs.first().walkSteps[1].instruction)
        assertFalse(legs.first().walkSteps[1].silent)
        assertEquals("2", legs.last().calls.first().platform)
    }

    @Test fun projectsSignalsButNotDistantSideRoads() {
        val line = listOf(LatLng(50.0, 14.0), LatLng(50.02, 14.0))
        val raw = """{"elements":[
          {"type":"node","id":1,"lat":50.004,"lon":14.0002,"tags":{"highway":"traffic_signals"}},
          {"type":"node","id":2,"lat":50.0041,"lon":14.0002,"tags":{"highway":"traffic_signals"}},
          {"type":"node","id":3,"lat":50.007,"lon":14.001,"tags":{"highway":"stop"}},
          {"type":"node","id":4,"lat":50.011,"lon":14,"tags":{"railway":"level_crossing"}}
          ]}"""
        val projected = Overpass.projectControls(Overpass.parseRoadControls(raw.toByteArray()), line)
        assertEquals(listOf(Overpass.ControlKind.SIGNAL, Overpass.ControlKind.RAIL), projected.map { it.kind })
        assertEquals(LatLng(50.004, 14.0002), projected.first().at)
    }
}
