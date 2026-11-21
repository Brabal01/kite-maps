package app.kite.core

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TransitBoardingTests {
    private val stop = LatLng(50.0, 14.0)
    private val line = listOf(stop, LatLng(50.01, 14.0))
    private val departure = 1_000_000L

    @Test fun confirmsForwardVehicleMovementAfterSeeingTheBoardingStop() {
        val board = TransitBoarding(line, stop)
        assertFalse(board.observe(stop, 12.0, 0.0, 0.0, departure - 10_000, departure))
        assertFalse(board.observe(LatLng(50.001, 14.0), 12.0, 11.0, 0.0, departure + 4_000, departure))
        assertTrue(board.observe(LatLng(50.0013, 14.0), 10.0, 12.0, 0.0, departure + 8_000, departure))
    }

    @Test fun rejectsWalkingWrongDirectionAndMovementOnAnotherStreet() {
        val board = TransitBoarding(line, stop)
        assertFalse(board.observe(stop, 10.0, 0.0, 0.0, departure, departure))
        assertFalse(board.observe(LatLng(50.0011, 14.0), 10.0, 1.6, 0.0, departure + 9_000, departure))
        assertFalse(board.observe(LatLng(50.0015, 14.0), 10.0, 1.6, 0.0, departure + 14_000, departure))
        assertFalse(board.observe(LatLng(50.0018, 14.0), 10.0, 14.0, 181.0, departure + 16_000, departure))
        assertFalse(board.observe(LatLng(50.0025, 14.001), 10.0, 14.0, 0.0, departure + 20_000, departure))
    }

    @Test fun needsTheRightDepartureTimeAndAStopVisit() {
        val board = TransitBoarding(line, stop)
        assertFalse(board.observe(LatLng(50.001, 14.0), 12.0, 10.0, 0.0, departure + 4_000, departure))
        assertFalse(board.observe(LatLng(50.0013, 14.0), 12.0, 10.0, 0.0, departure + 8_000, departure))
        assertFalse(board.observe(stop, 12.0, 0.0, 0.0, departure - 180_000, departure))
        assertFalse(board.observe(LatLng(50.001, 14.0), 12.0, 10.0, 0.0, departure - 170_000, departure))
        assertFalse(board.observe(LatLng(50.0013, 14.0), 12.0, 10.0, 0.0, departure - 165_000, departure))
    }
}
