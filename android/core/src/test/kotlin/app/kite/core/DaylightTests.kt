package app.kite.core

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DaylightTests {
    @Test fun followsPragueSeasonsAndLocalSunset() {
        val prague = LatLng(50.08, 14.43)
        fun dark(utc: String) = Daylight.isDark(prague, Instant.parse(utc).toEpochMilli())
        assertFalse(dark("2026-06-21T18:00:00Z"))
        assertTrue(dark("2026-06-21T21:00:00Z"))
        assertFalse(dark("2026-12-21T13:00:00Z"))
        assertTrue(dark("2026-12-21T17:00:00Z"))
    }

    @Test fun followsLocationWhenDeviceTimeIsTheSame() {
        val time = Instant.parse("2026-03-20T12:00:00Z").toEpochMilli()
        assertFalse(Daylight.isDark(LatLng(0.0, 0.0), time))
        assertTrue(Daylight.isDark(LatLng(0.0, 179.0), time))
    }
}
