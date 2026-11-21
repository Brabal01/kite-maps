package app.kite.core

import java.time.Instant
import java.time.ZoneOffset
import kotlin.math.*

/** Day/night by the sun's position at this place. UTC avoids guessing the device's time zone. */
object Daylight {
    fun isDark(at: LatLng, timeMillis: Long): Boolean {
        val utc = Instant.ofEpochMilli(timeMillis).atZone(ZoneOffset.UTC)
        val hour = utc.hour + utc.minute / 60.0 + utc.second / 3600.0
        val gamma = 2 * PI / utc.toLocalDate().lengthOfYear() * (utc.dayOfYear - 1 + (hour - 12) / 24)
        val equation = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma) -
            0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        val declination = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma) -
            0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma) -
            0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        val hourAngle = Math.toRadians((hour * 60 + equation + 4 * at.lng) / 4 - 180)
        val lat = Math.toRadians(at.lat)
        val sineAltitude = sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hourAngle)
        return sineAltitude < sin(Math.toRadians(-0.833))
    }
}
