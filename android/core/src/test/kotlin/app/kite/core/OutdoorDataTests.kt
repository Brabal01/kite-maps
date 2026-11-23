package app.kite.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class OutdoorDataTests {
    @Test fun unnamedFacilitiesStaySearchable() {
        val data = """{"elements":[{"type":"node","id":123,"lat":50.0,"lon":14.0,"tags":{"amenity":"drinking_water"}},
            {"type":"way","id":456,"center":{"lat":50.01,"lon":14.0},"tags":{"amenity":"parking"}}]}"""
        val places = OutdoorData.parsePlaces(data.toByteArray())
        assertEquals(listOf("Drinking water", "Parking"), places.map { it.name })
        assertEquals(listOf("osm:N123", "osm:W456"), places.map { it.id })
        assertEquals(OutdoorData.WATER, OutdoorData.kind("Pítka"))
    }

    @Test fun reviewedGooglePlacesWinOnlyTheirDuplicates() {
        val here = LatLng(50.0, 14.0)
        val reviewed = Place("g1", "Parking 1", here, "google", category = "Parking lot", rating = 4.3)
        val openParking = Place("o1", "Parking", here, "osm", category = "Parking")
        val water = Place("o2", "Drinking water", here, "osm", category = "Drinking water")
        val unnamed = Place("g2", "Parking 2", here.copy(lat = 50.002), "google", category = "Parking lot")
        val openOther = Place("o3", "Public parking", unnamed.location, "osm", category = "Parking")
        assertEquals(listOf("g1", "o2", "o3"), OutdoorData.combine(listOf(reviewed, unnamed), listOf(openParking, water, openOther)).map { it.id })
    }

    @Test fun liveTrafficRefreshRequiresTheSameRoad() {
        val line = listOf(LatLng(50.0, 14.0), LatLng(50.09, 14.0))
        val start = 500.0
        val freshLine = listOf(Geo.point(line, start), line.last())
        val fresh = Route(TravelMode.DRIVE, freshLine, Geo.length(freshLine), 600.0, 640.0, null, mutableListOf(),
            trafficSpans = listOf(TrafficSpan(2, 400.0, 100.0)), source = "mapbox")
        val older = TrafficSpan(1, 6200.0, 300.0)
        val refreshed = assertNotNull(MapboxDirections.refreshTraffic(line, listOf(older), fresh, start))
        assertEquals(2, refreshed.size)
        assertEquals(2, refreshed.first().level)
        assertTrue(kotlin.math.abs(refreshed.first().startMeters - 900) < 10)
        assertEquals(older, refreshed.last())
        val parallel = fresh.copy(polyline = freshLine.map { it.copy(lng = it.lng + 0.002) })
        assertNull(MapboxDirections.refreshTraffic(line, listOf(older), parallel, start))
    }

    @Test fun storesTransitStopsInTravelOrder() {
        val data = """{"itineraries":[{"legs":[{"mode":"TRAM","tripId":"tram1",
            "from":{"stopId":"A","name":"Start","lat":50.0,"lon":14.0},
            "intermediateStops":[{"stopId":"B","name":"Midway","lat":50.01,"lon":14.0}],
            "to":{"stopId":"C","name":"End","lat":50.02,"lon":14.0}}]}]}"""
        val leg = Transitous.parse(data.toByteArray()).single().legs.single()
        assertEquals("tram1", leg.tripId)
        assertEquals(listOf("A", "B", "C"), leg.calls.map { it.stopId })
    }

    @Test fun surfaceSectionsFollowTheSelectedRoute() {
        val shape = "??o}@?o}@?"
        val response = """{"shape":"$shape","edges":[
          {"surface":"paved","use":"footway","begin_shape_index":0,"end_shape_index":1},
          {"surface":"gravel","use":"cycleway","begin_shape_index":1,"end_shape_index":2},
          {"surface":"dirt","use":"track","begin_shape_index":2,"end_shape_index":9}]}""".toByteArray()
        val route = listOf(LatLng(0.0, 0.0), LatLng(0.002, 0.0))
        val sections = Valhalla.parsePathSections(response, route)
        assertEquals(listOf("paved", "gravel"), sections.map { it.surface })
        assertEquals(listOf("footway", "cycleway"), sections.map { it.type })
        assertEquals(sections[0].to, sections[1].from, 0.001)
        assertEquals(Geo.length(route), sections.last().to, 0.001)
        assertTrue(Valhalla.parsePathSections(response, route.map { it.copy(lng = 0.0004) }).isEmpty())
    }

}
