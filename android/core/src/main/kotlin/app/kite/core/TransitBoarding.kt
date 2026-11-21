package app.kite.core

/** Looks for departure from the selected stop and sustained travel along the chosen leg. */
class TransitBoarding(path: List<LatLng>, private val stop: LatLng) {
    private val firstSection = if (path.size >= 2) Geo.slice(path, 0.0, 900.0) else emptyList()
    private val distances = Geo.cumulative(firstSection)
    private var atStop: Long? = null
    private var moving: Pair<Long, Double>? = null

    fun observe(at: LatLng, accuracy: Double, speed: Double, heading: Double, now: Long, departure: Long?): Boolean {
        if (firstSection.size < 2 || accuracy !in 0.0..45.0) return false
        if (at.distanceTo(stop) <= 68) atStop = now
        val seen = atStop ?: return false
        if (now - seen !in 0..210_000 || departure != null && now - departure !in -90_000..360_000) {
            moving = null
            return false
        }
        val point = Geo.project(at, firstSection, distances)
        if (point.offset > 35 || point.along !in 85.0..850.0 || speed < 2.8) {
            moving = null
            return false
        }
        if (heading >= 0) {
            val roadHeading = Geo.bearing(Geo.point(firstSection, point.along - 12, distances),
                Geo.point(firstSection, point.along + 12, distances))
            val difference = kotlin.math.abs((heading - roadHeading + 540.0) % 360.0 - 180.0)
            if (difference > 60) { moving = null; return false }
        }
        val previous = moving
        if (previous == null || now - previous.first > 20_000 || point.along < previous.second - 12) {
            moving = now to point.along
            return false
        }
        return now - previous.first in 900..20_000 && point.along - previous.second >= 24
    }
}
