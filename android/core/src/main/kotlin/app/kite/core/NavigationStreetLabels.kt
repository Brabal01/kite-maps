package app.kite.core

import kotlin.math.abs

/** Street names anchored near a junction rather than to the middle of a basemap tile. */
object NavigationStreetLabels {
    data class Label(val name: String, val at: LatLng, val meters: Double)

    fun find(line: List<LatLng>, meters: Double, ways: List<Pair<String, List<LatLng>>>): Pair<String?, List<Label>> {
        val start = (meters - 110).coerceAtLeast(0.0)
        val route = Geo.slice(line, start, meters + 680)
        if (route.size < 2) return null to emptyList()
        val cum = Geo.cumulative(route)
        val here = Geo.point(route, meters - start, cum)
        fun routeHeading(along: Double) = Geo.bearing(
            Geo.point(route, along - 9, cum), Geo.point(route, along + 9, cum))
        fun angle(a: Double, b: Double): Double = Geo.diff(a, b).let { minOf(it, abs(180 - it)) }

        var current: String? = null
        var best = 12.0
        val names = mutableListOf<Label>()
        for ((name, way) in ways) {
            val roadCum = Geo.cumulative(way)
            val nearest = Geo.project(here, way, roadCum)
            if (nearest.offset < best) {
                val roadBearing = Geo.bearing(Geo.point(way, nearest.along - 7, roadCum),
                    Geo.point(way, nearest.along + 7, roadCum))
                if (angle(roadBearing, routeHeading(meters - start)) < 30) {
                    current = name
                    best = nearest.offset
                }
            }
            val candidates = way.indices.asSequence().map { it to Geo.project(way[it], route, cum) }
                .filter { (_, p) -> p.offset < 8 && p.along + start in (meters - 35)..(meters + 640) }
                .sortedBy { it.second.along }
            for ((vertex, projected) in candidates) {
                val around = roadCum[vertex]
                val targets = listOf(around + 44, around - 44).filter { it in 0.0..roadCum.last() }
                val at = targets.map { Geo.point(way, it, roadCum) }.filter { point ->
                    Geo.project(point, route, cum).offset > 23 &&
                        angle(Geo.bearing(way[vertex], point), routeHeading(projected.along)) >= 29
                }.maxByOrNull { Geo.project(it, route, cum).offset } ?: continue
                names += Label(name, at, projected.along + start)
                break
            }
        }
        return current to names.filter { it.name != current }.sortedBy { it.meters }
            .distinctBy { it.name }.take(12)
    }
}
