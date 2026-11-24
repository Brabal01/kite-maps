package app.kite.core

import java.util.TreeMap

/** Partitions the route's own centerline into nonoverlapping colour ranges. */
object RouteTrafficPaint {
    data class Segment(val from: Double, val to: Double, val level: Int)

    fun ranges(from: Double, to: Double, traffic: List<TrafficSpan>): List<Segment> {
        if (to <= from) return emptyList()
        val breaks = TreeMap<Double, IntArray>()
        breaks[from] = IntArray(4)
        breaks[to] = IntArray(4)
        for (span in traffic) {
            val a = maxOf(from, span.startMeters)
            val b = minOf(to, span.startMeters + span.lengthMeters)
            val level = span.level.coerceIn(0, 3)
            if (level == 0 || !a.isFinite() || !b.isFinite() || b <= a) continue
            breaks.getOrPut(a) { IntArray(4) }[level]++
            breaks.getOrPut(b) { IntArray(4) }[level]--
        }
        val active = IntArray(4)
        var last = from
        return buildList {
            for ((at, deltas) in breaks) {
                val level = active.indexOfLast { it > 0 }.coerceAtLeast(0)
                if (at > last) {
                    val previous = lastOrNull()
                    if (previous != null && previous.level == level) set(lastIndex, previous.copy(to = at))
                    else add(Segment(last, at, level))
                }
                deltas.forEachIndexed { index, count -> active[index] += count }
                last = at
            }
        }
    }
}
