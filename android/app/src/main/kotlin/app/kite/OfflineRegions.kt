package app.kite

import app.kite.core.Box
import app.kite.core.Json
import app.kite.core.asList
import app.kite.core.num
import java.text.Collator
import kotlin.math.*

/** Catalogue bounds from Geofabrik extracts and Eurostat GISCO NUTS 2024 (Czech regions). */
internal object OfflineRegions {
    data class Region(val id: String, val parent: String?, val name: String, val box: Box) {
        val maxZoom: Int get() = zoomFor(box)
    }

    val catalogue: List<Region> by lazy {
        val input = KiteApp.app.assets.open("offline-regions.json").use { it.readBytes() }
        val collator = Collator.getInstance()
        Json.parse(input).asList().orEmpty().mapNotNull { item ->
            val columns = item.asList()?.takeIf { it.size == 7 } ?: return@mapNotNull null
            val id = columns[0] as? String ?: return@mapNotNull null
            val name = columns[2] as? String ?: return@mapNotNull null
            val (s, w, n, e) = columns.drop(3).mapNotNull { it.num() }.takeIf { it.size == 4 } ?: return@mapNotNull null
            Region(id, columns[1] as? String, name, Box(s, w, n, e))
        }.sortedWith { a, b -> collator.compare(a.name, b.name) }
    }

    private fun zoomFor(box: Box): Int {
        fun mercator(lat: Double): Double = asinh(tan(lat.coerceIn(-83.0, 83.0) * PI / 180)) / (2 * PI)
        val width = (box.e - box.w) / 360
        val height = mercator(box.n) - mercator(box.s)
        // Keep single downloads bounded. Download a smaller subregion for more street detail.
        return (15 downTo 4).firstOrNull { z ->
            val side = 1 shl z
            (ceil(width * side) + 1) * (ceil(height * side) + 1) <= 1800
        } ?: 4
    }
}
