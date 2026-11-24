package app.kite.core

import kotlin.math.roundToInt

/** Mapbox's traffic-aware car routes use the same turn and lane objects as the open router. */
object MapboxDirections {
    private val client = Http.client(8)
    private val publicToken = Regex("pk\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+")

    fun isPublicToken(token: String): Boolean = publicToken.matches(token)

    suspend fun routes(
        from: LatLng, to: LatLng, via: List<LatLng>, heading: Double?,
        avoidHighways: Boolean, avoidTolls: Boolean, alternatives: Boolean, token: String, mode: TravelMode = TravelMode.DRIVE,
    ): List<Route> {
        if (!isPublicToken(token) || via.size > 23) return emptyList()
        val points = listOf(from) + via + to
        val coordinates = points.joinToString(";") { "${it.lng.plain()},${it.lat.plain()}" }
        val query = mutableListOf(
            "access_token=$token", "overview=full", "geometries=polyline6", "steps=true",
            "roundabout_exits=true", "alternatives=$alternatives",
        )
        if (mode == TravelMode.DRIVE) query += "annotations=congestion,maxspeed"
        val profile = when (mode) {
            TravelMode.DRIVE -> "driving-traffic"
            TravelMode.WALK -> "walking"
            TravelMode.BIKE -> "cycling"
        }
        val exclusions = listOfNotNull("motorway".takeIf { avoidHighways }, "toll".takeIf { avoidTolls })
        if (mode == TravelMode.DRIVE && exclusions.isNotEmpty()) query += "exclude=${exclusions.joinToString(",")}"
        if (heading != null) query += "bearings=${Math.floorMod(heading.roundToInt(), 360)},60" + ";".repeat(points.lastIndex)
        val url = "https://api.mapbox.com/directions/v5/mapbox/$profile/$coordinates?${query.joinToString("&")}"
        val response = Http.getOrNull(url, client = client)?.takeIf { it.ok } ?: return emptyList()
        return parse(response.body, mode)
    }

    internal fun parse(body: ByteArray, mode: TravelMode = TravelMode.DRIVE): List<Route> {
        val root = Json.obj(body)?.takeIf { it["code"] == "Ok" } ?: return emptyList()
        return OSRM.parseRoot(root, mode, source = "mapbox")
    }

    /** Refresh congestion on the next stretch only if the new route follows the same roads. */
    fun refreshTraffic(line: List<LatLng>, previous: List<TrafficSpan>, fresh: Route, from: Double): List<TrafficSpan>? {
        if (line.size < 2 || fresh.polyline.size < 2) return null
        val cum = Geo.cumulative(line)
        val fc = Geo.cumulative(fresh.polyline)
        // When the provider gives no later congestion measurements, retain the previous ones beyond
        // the routine refresh window. Extend the match when the response explicitly marks more of the road.
        val measuredEnd = fresh.trafficSpans.maxOfOrNull { it.startMeters + it.lengthMeters } ?: 0.0
        val maxDistance = minOf(maxOf(4500.0, measuredEnd), 16_000.0, fc.last())
        if (maxDistance < 60) return null
        val start = (from - 300).coerceAtLeast(0.0)
        val window = Geo.slice(line, start, minOf(cum.last(), from + maxDistance + 300), cum)
        if (window.size < 2) return null
        val wc = Geo.cumulative(window)
        val begin = Geo.project(fresh.polyline.first(), window, wc)
        if (begin.offset > 22 || kotlin.math.abs(begin.along + start - from) > 160) return null
        val count = kotlin.math.ceil(maxDistance / 150.0).toInt()
        var end = 0.0
        var lastMatch = begin.along
        for (i in 1..count) {
            val distance = maxDistance * i / count
            val match = Geo.project(Geo.point(fresh.polyline, distance, fc), window, wc)
            if (match.offset > 22 || match.along < lastMatch ||
                kotlin.math.abs(match.along - begin.along - distance) > 140) break
            end = distance
            lastMatch = match.along
        }
        if (end + 0.01 < minOf(4500.0, maxDistance)) return null
        val first = begin.along + start
        val last = lastMatch + start
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
