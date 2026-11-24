package app.kite.core

import kotlin.test.Test
import kotlin.test.assertEquals

class TransitRailGeometryTests {
    @Test fun olomoucTramDoesNotDetourThroughAnUnservedVertex() {
        val start = LatLng(49.592316, 17.277658)
        val stop = LatLng(49.59436, 17.27148)
        val spike = LatLng(49.59093, 17.27153)
        val after = LatLng(49.59465, 17.27030)
        val end = LatLng(49.59617, 17.26497)
        val path = listOf(start, stop, spike, after, end)
        val calls = listOf(start, stop, end).map { TransitCall(null, "", it, null, null) }
        assertEquals(listOf(start, stop, after, end), Transitous.withoutRailSpikes(path, calls))

        val served = TransitCall(null, "Stop at the end of the branch", spike, null, null)
        assertEquals(path, Transitous.withoutRailSpikes(path, calls + served))
    }
}
