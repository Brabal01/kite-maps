package app.kite.core

/** Tracks stop order along the booked leg, including routes that pass the same junction twice. */
class TransitRide(private val leg: TransitLeg) {
    private val line = leg.path
    private val cumulative = Geo.cumulative(line)
    private var segmentStart = 0.0
    private val anchors = leg.calls.mapIndexed { index, call ->
        val end = cumulative.last()
        if (index == leg.calls.lastIndex && line.lastOrNull()?.distanceTo(call.at)?.let { it < 130 } == true) return@mapIndexed end
        val remaining = Geo.slice(line, segmentStart, end, cumulative)
        val projected = if (remaining.size >= 2) segmentStart + Geo.project(call.at, remaining).along else segmentStart
        projected.also { segmentStart = it }
    }
    var nextIndex = 1
        private set
    var lastPositionAt: Long? = null
        private set
    var nearExit = false
        private set
    private var lastAlong = 0.0

    val next: TransitCall? get() = leg.calls.getOrNull(nextIndex)

    fun observe(point: LatLng, accuracy: Double, at: Long): Advance {
        nearExit = false
        if (accuracy !in 0.0..75.0 || leg.calls.size < 2 || nextIndex >= leg.calls.size) return Advance()
        val end = cumulative.last()
        val floor = (lastAlong - 140).coerceAtLeast(0.0)
        val seconds = lastPositionAt?.let { (at - it).coerceAtLeast(0) / 1000.0 } ?: 45.0
        val ceiling = (lastAlong + maxOf(4200.0, seconds * 115.0)).coerceAtMost(end)
        val window = Geo.slice(line, floor, ceiling, cumulative)
        val projected = if (window.size > 1) Geo.project(point, window) else null
        val current = projected?.let { floor + it.along }
        if (projected != null && projected.offset > 125) return Advance()
        lastPositionAt = at
        if (current != null) lastAlong = maxOf(lastAlong, current)
        val previous = nextIndex
        while (nextIndex < leg.calls.lastIndex) {
            val call = leg.calls[nextIndex]
            val anchor = anchors[nextIndex]
            val reached = point.distanceTo(call.at) < 75 && (current == null || current >= anchor - 100)
            if (!reached && (current == null || current <= anchor + 65)) break
            nextIndex++
        }
        val final = leg.calls.last()
        val exitApproach = nextIndex == leg.calls.lastIndex && point.distanceTo(final.at) < 180
        nearExit = nextIndex == leg.calls.lastIndex && point.distanceTo(final.at) < 65 &&
            (current == null || current >= anchors.last() - 110)
        return Advance(nextChanged = previous != nextIndex, exitApproach = exitApproach)
    }

    fun scheduledNext(time: Long): TransitCall? =
        leg.calls.drop(nextIndex).firstOrNull { (it.departure ?: it.arrival ?: Long.MAX_VALUE) >= time }
            ?: leg.calls.lastOrNull().takeIf { next != null }

    data class Advance(val nextChanged: Boolean = false, val exitApproach: Boolean = false)
}
