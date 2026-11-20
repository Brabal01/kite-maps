package app.kite.core

import kotlin.math.roundToInt

/** Mapbox's traffic-aware car routes use the same turn and lane objects as the open router. */
object MapboxDirections {
    private val client = Http.client(8)
    private val publicToken = Regex("pk\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+")

    fun isPublicToken(token: String): Boolean = publicToken.matches(token)

    suspend fun routes(
        from: LatLng, to: LatLng, via: List<LatLng>, heading: Double?,
        avoidHighways: Boolean, avoidTolls: Boolean, alternatives: Boolean, token: String,
    ): List<Route> {
        if (!isPublicToken(token) || via.size > 23) return emptyList()
        val points = listOf(from) + via + to
        val coordinates = points.joinToString(";") { "${it.lng.plain()},${it.lat.plain()}" }
        val query = mutableListOf(
            "access_token=$token", "overview=full", "geometries=polyline6", "steps=true",
            "roundabout_exits=true", "annotations=congestion,maxspeed", "alternatives=$alternatives",
        )
        val exclusions = listOfNotNull("motorway".takeIf { avoidHighways }, "toll".takeIf { avoidTolls })
        if (exclusions.isNotEmpty()) query += "exclude=${exclusions.joinToString(",")}"
        if (heading != null) query += "bearings=${Math.floorMod(heading.roundToInt(), 360)},60" + ";".repeat(points.lastIndex)
        val url = "https://api.mapbox.com/directions/v5/mapbox/driving-traffic/$coordinates?${query.joinToString("&")}"
        val response = Http.getOrNull(url, client = client)?.takeIf { it.ok } ?: return emptyList()
        return parse(response.body)
    }

    internal fun parse(body: ByteArray): List<Route> {
        val root = Json.obj(body)?.takeIf { it["code"] == "Ok" } ?: return emptyList()
        return OSRM.parseRoot(root, TravelMode.DRIVE, source = "mapbox")
    }

    /** Refresh congestion on the next stretch only if the new route follows the same roads. */
    fun refreshTraffic(line: List<LatLng>, previous: List<TrafficSpan>, fresh: Route, from: Double): List<TrafficSpan>? {
        if (line.size < 2 || fresh.polyline.size < 2) return null
        val end = minOf(4500.0, Geo.length(fresh.polyline))
        if (end < 60) return null
        val cum = Geo.cumulative(line)
        val start = (from - 300).coerceAtLeast(0.0)
        val window = Geo.slice(line, start, minOf(cum.last(), from + end + 300), cum)
        if (window.size < 2) return null
        val wc = Geo.cumulative(window)
        val fc = Geo.cumulative(fresh.polyline)
        val count = kotlin.math.ceil(end / 200.0).toInt()
        val matches = (0..count).map { i ->
            Geo.project(Geo.point(fresh.polyline, end * i / count, fc), window, wc)
        }
        if (matches.any { it.offset > 22 } || matches.zipWithNext().any { (a, b) -> b.along - a.along < 0 }) return null
        val first = matches.first().along + start
        val last = matches.last().along + start
        if (kotlin.math.abs(last - first - end) > 140) return null
        fun along(distance: Double) = first + (last - first) * distance / end
        val kept = previous.flatMap { span ->
            val stop = span.startMeters + span.lengthMeters
            listOfNotNull(
                span.copy(lengthMeters = minOf(stop, first) - span.startMeters).takeIf { it.lengthMeters > 0 },
                span.copy(startMeters = maxOf(span.startMeters, last), lengthMeters = stop - maxOf(span.startMeters, last))
                    .takeIf { it.lengthMeters > 0 },
            )
        }
        return (kept + fresh.trafficSpans.mapNotNull { span ->
            if (span.startMeters >= end) return@mapNotNull null
            val a = along(span.startMeters)
            val b = along(minOf(end, span.startMeters + span.lengthMeters))
            TrafficSpan(span.level, a, b - a)
        }).sortedBy { it.startMeters }
    }

    internal fun trafficSpans(legs: List<Map<String, Any?>>, cumulative: DoubleArray): List<TrafficSpan> {
        val levels = legs.flatMap { it["annotation"].asMap()?.get("congestion").asList().orEmpty() }
        if (levels.size != cumulative.lastIndex) return emptyList()
        val spans = mutableListOf<TrafficSpan>()
        var start = 0
        while (start < levels.size) {
            var end = start + 1
            while (end < levels.size && levels[end] == levels[start]) end++
            val level = when (levels[start]) {
                "moderate" -> 1
                "heavy" -> 2
                "severe" -> 3
                else -> 0
            }
            val length = cumulative[end] - cumulative[start]
            if (level > 0 && length > 0) spans += TrafficSpan(level, cumulative[start], length)
            start = end
        }
        return spans
    }
}
