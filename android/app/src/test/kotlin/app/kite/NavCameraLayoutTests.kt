package app.kite

import app.kite.core.LatLng
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.Test

class NavCameraLayoutTests {
    @Test fun drivingCameraKeepsARenderableViewportOnShortScreens() {
        for (height in listOf(160f, 320f, 480f, 499f, 500f, 540f, 567f, 800f)) {
            val top = NavGlide.topInset(height)
            val bottom = NavGlide.bottomInset(height)
            assertTrue(height - top - bottom >= 48f, "No usable viewport at ${height}dp")
            assertEquals(top + (height - top - bottom) / 2f, NavGlide.carY(height), absoluteTolerance = 0.001f)
        }
    }

    @Test fun northUpKeepsTheVehicleAtTheCenterOfTheAdjustedViewport() {
        val height = 540f
        val bottom = NavGlide.bottomInset(height)
        assertEquals((height - bottom) / 2f, NavGlide.carY(height, north = 1f))
        assertTrue(NavGlide.carY(height, north = 1f) < NavGlide.carY(height))
    }

    @Test fun startupRejectsAnOldPreviewCenterOrZoom() {
        val fix = LatLng(49.592, 17.252)
        val routeOverview = LatLng(49.604, 17.285)
        assertTrue(NavGlide.needsCameraCorrection(routeOverview, fix, 17.0, 17.0))
        assertTrue(NavGlide.needsCameraCorrection(fix, fix, 12.0, 17.0))
        assertFalse(NavGlide.needsCameraCorrection(fix.copy(lat = 49.592003), fix, 17.02, 17.0))
    }

    @Test fun vehicleCanTurnRelativeToTheFollowingCameraAcrossNorth() {
        assertEquals(28.0, NavGlide.shortestTurn(350.0, 18.0))
        assertEquals(-28.0, NavGlide.shortestTurn(18.0, 350.0))
        assertEquals(0.0, NavGlide.shortestTurn(90.0, 90.0))
    }
}
