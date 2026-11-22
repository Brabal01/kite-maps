package app.kite

import kotlin.test.assertEquals
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
}
