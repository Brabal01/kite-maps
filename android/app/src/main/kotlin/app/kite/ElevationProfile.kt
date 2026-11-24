package app.kite

import android.graphics.BitmapFactory
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.kite.core.Valhalla
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import app.kite.core.Geo
import app.kite.core.Http
import app.kite.core.LatLng
import app.kite.core.Route
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlin.math.*

/** Samples the same open elevation tiles as the 3D terrain. */
object ElevationProfile {
    private data class Tile(val x: Int, val y: Int)
    private data class Pixel(val tile: Tile, val x: Int, val y: Int)
    private val client = Http.client(8)

    data class Result(val heights: List<Double>) {
        private val changes = heights.zipWithNext { a, b -> b - a }.filter { abs(it) > 2.0 }
        val ascent: Double get() = changes.filter { it > 0 }.sum()
        val descent: Double get() = -changes.filter { it < 0 }.sum()
    }

    suspend fun sample(route: Route): Result? = withContext(Dispatchers.Default) {
        if (route.polyline.size < 2) return@withContext null
        val cum = Geo.cumulative(route.polyline)
        val length = cum.last()
        if (length <= 0) return@withContext null
        val zoom = if (length > 35_000) 10 else 12
        val count = (length / 35).roundToInt().coerceIn(24, 64)
        val pixels = (0..count).map { pixel(Geo.point(route.polyline, length * it / count, cum), zoom) }
        val groups = pixels.indices.groupBy { pixels[it].tile }
        val heights = arrayOfNulls<Double>(pixels.size)
        for (batch in groups.entries.chunked(4)) coroutineScope {
            batch.map { (tile, indices) ->
                async {
                    val url = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/$zoom/${tile.x}/${tile.y}.png"
                    val content = Http.getOrNull(url, client = client)?.takeIf { it.ok }?.body ?: return@async
                    val bitmap = BitmapFactory.decodeByteArray(content, 0, content.size) ?: return@async
                    try {
                        for (i in indices) {
                            val p = pixels[i]
                            val rgb = bitmap.getPixel(p.x.coerceAtMost(bitmap.width - 1), p.y.coerceAtMost(bitmap.height - 1))
                            heights[i] = (rgb shr 16 and 255) * 256.0 + (rgb shr 8 and 255) + (rgb and 255) / 256.0 - 32768.0
                        }
                    } finally { bitmap.recycle() }
                }
            }.awaitAll()
        }
        if (heights.any { it == null }) return@withContext null
        val values = heights.filterNotNull()
        Result(values.indices.map { i ->
            if (i == 0 || i == values.lastIndex) values[i] else (values[i - 1] + 2 * values[i] + values[i + 1]) / 4
        })
    }

    private fun pixel(at: LatLng, zoom: Int): Pixel {
        val world = 256 shl zoom
        val lat = at.lat.coerceIn(-85.05112878, 85.05112878) * PI / 180
        val x = floor((at.lng + 180.0) / 360.0 * world).toInt().mod(world)
        val y = floor((1.0 - asinh(tan(lat)) / PI) * world / 2).toInt().coerceIn(0, world - 1)
        return Pixel(Tile(x / 256, y / 256), x % 256, y % 256)
    }
}

internal const val PREFETCH_SURFACE_METERS = 32_000.0

class RouteProfiles(private val scope: CoroutineScope) {
    class Entry {
        var elevation by mutableStateOf<ElevationProfile.Result?>(null)
        var elevationDone by mutableStateOf(false)
        var surfaces by mutableStateOf<List<Valhalla.PathSection>?>(null)
        var fullSurface by mutableStateOf(false)
        var loadingSurface by mutableStateOf(false)
    }

    private val entries = mutableStateMapOf<String, Entry>()
    operator fun get(route: Route): Entry? = entries[route.id]

    fun load(route: Route, entireSurface: Boolean = false) {
        val existing = entries[route.id]
        val entry = existing ?: Entry().also {
            if (entries.size >= 5) entries.remove(entries.keys.first())
            entries[route.id] = it
        }
        if (existing == null) scope.launch {
            entry.elevation = try {
                ElevationProfile.sample(route)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                null
            }
            entry.elevationDone = true
        }
        if (entry.loadingSurface || entry.fullSurface || !entireSurface && entry.surfaces != null) return
        entry.loadingSurface = true
        scope.launch {
            val max = if (entireSurface) Double.POSITIVE_INFINITY else PREFETCH_SURFACE_METERS
            try {
                entry.surfaces = Valhalla.pathSections(route, max).fold(mutableListOf<Valhalla.PathSection>()) { merged, raw ->
                    val category = when (raw.surface) {
                        "paved_smooth" -> "Smooth pavement"
                        "paved" -> "Pavement"
                        "paved_rough" -> "Rough pavement"
                        "compacted", "gravel" -> "Gravel and compacted"
                        "dirt", "path", "grass" -> "Natural surface"
                        else -> null
                    }
                    val previous = merged.lastOrNull()
                    if (category != null && previous?.surface == category && raw.from - previous.to < 2.0) {
                        merged[merged.lastIndex] = previous.copy(to = raw.to)
                    } else if (category != null) {
                        merged += raw.copy(surface = category, type = null)
                    }
                    merged
                }
                entry.fullSurface = entireSurface || route.distanceMeters <= PREFETCH_SURFACE_METERS
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                if (entry.surfaces == null) entry.surfaces = emptyList()
            } finally {
                entry.loadingSurface = false
            }
        }
    }
}
