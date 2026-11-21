package app.kite

import app.kite.core.LatLng
import app.kite.core.Place
import app.kite.core.Route
import app.kite.core.TravelMode
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertSame
import org.junit.Test

class RoadStartTests {
    private val here = LatLng(50.07, 14.43)
    private val start = Place("start", "Start", LatLng(50.11, 14.43), "osm")
    private val via = Place("via", "Stop", LatLng(50.14, 14.43), "osm")
    private val end = Place("end", "Destination", LatLng(50.17, 14.43), "osm")
    private val direct = Route(TravelMode.DRIVE, listOf(here, end.location), 11_000.0, 900.0, null, null, mutableListOf(), source = "test")
    private val alternative = Route(TravelMode.DRIVE, listOf(here, via.location, end.location), 12_000.0, 950.0, null, null, mutableListOf(), source = "test")

    @Test fun goWaitsForGpsAndFollowsTheChosenDrivingRouteWhenItArrives() {
        val plan = DirectionsState(end, mode = TravelMode.DRIVE,
            routes = mapOf(TravelMode.DRIVE to listOf(direct, alternative)), selected = 1, startRequested = true)
        assertIs<RoadStart.WaitForLocation>(plan.roadStart(null))
        assertSame(alternative, assertIs<RoadStart.Follow>(plan.roadStart(here)).route)
    }

    @Test fun goCanBeRequestedBeforeTheRoadRouterHasAnswered() {
        val plan = DirectionsState(end, mode = TravelMode.DRIVE, startRequested = true)
        assertIs<RoadStart.FindRoute>(plan.roadStart(here))
        assertNull(plan.copy(transit = true).roadStart(here))
    }

    @Test fun savedPlansJoinTheExplicitStartAndPreserveStops() {
        val plan = DirectionsState(end, mode = TravelMode.DRIVE,
            routes = mapOf(TravelMode.DRIVE to listOf(direct)), start = start, stops = listOf(via))
        val action = assertIs<RoadStart.ConnectToPlan>(plan.roadStart(here))
        assertEquals(end, action.destination)
        assertEquals(listOf(start, via), action.stops)
        assertIs<RoadStart.Follow>(plan.roadStart(start.location))
    }

    @Test fun reversedPlansReturnToTheCurrentPositionAfterVisitingEveryPoint() {
        val plan = DirectionsState(end, mode = TravelMode.DRIVE,
            routes = mapOf(TravelMode.DRIVE to listOf(alternative)), reversed = true, stops = listOf(via, start))
        val action = assertIs<RoadStart.ConnectToPlan>(plan.roadStart(here))
        assertEquals(here, action.destination.location)
        assertEquals(listOf(end, start, via), action.stops)
    }
}
