package app.kite

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.kite.core.LatLng
import app.kite.core.OutdoorData
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.offline.OfflineManager
import org.maplibre.android.offline.OfflineRegion
import org.maplibre.android.offline.OfflineRegionError
import org.maplibre.android.offline.OfflineRegionStatus
import org.maplibre.android.offline.OfflineTilePyramidRegionDefinition

/** MapLibre uses its ordinary tile database for these retained, explicitly downloaded areas. */
internal object OfflineMaps {
    data class Area(
        val id: Long, val name: String, val bounds: LatLngBounds,
        val active: Boolean = false, val complete: Boolean = false,
        val bytes: Long = 0, val progress: Float? = null,
    )

    val areas = mutableStateMapOf<Long, Area>()
    var message by mutableStateOf<String?>(null)
        private set
    var creating by mutableStateOf(false)
        private set
    private var loaded = false
    private val regions = mutableMapOf<Long, OfflineRegion>()
    private val manager get() = OfflineManager.getInstance(KiteApp.app)

    fun load() {
        if (loaded) return
        loaded = true
        manager.listOfflineRegions(object : OfflineManager.ListOfflineRegionsCallback {
            override fun onList(list: Array<OfflineRegion>?) { list.orEmpty().forEach(::register) }
            override fun onError(error: String) { loaded = false; message = error }
        })
    }

    private fun register(region: OfflineRegion) {
        val def = region.definition as? OfflineTilePyramidRegionDefinition ?: return
        if (def.styleURL != KiteMap.STYLE_URL) return
        val bounds = def.bounds ?: return
        val id = region.id
        val name = region.metadata.toString(Charsets.UTF_8).trim().ifBlank { "Offline area" }
        regions[id] = region
        areas[id] = Area(id, name, bounds)
        region.setObserver(object : OfflineRegion.OfflineRegionObserver {
            override fun onStatusChanged(status: OfflineRegionStatus) { update(region, status) }
            override fun onError(error: OfflineRegionError) { message = error.message }
            override fun mapboxTileCountLimitExceeded(limit: Long) { stop(id); message = "Offline tile limit reached." }
        })
        region.getStatus(object : OfflineRegion.OfflineRegionStatusCallback {
            override fun onStatus(status: OfflineRegionStatus?) { status?.let { update(region, it) } }
            override fun onError(error: String?) { message = error }
        })
    }

    private fun update(region: OfflineRegion, status: OfflineRegionStatus) {
        val current = areas[region.id] ?: return
        val progress = if (status.isRequiredResourceCountPrecise && status.requiredResourceCount > 0) {
            (status.completedResourceCount.toFloat() / status.requiredResourceCount).coerceIn(0f, 1f)
        } else null
        areas[region.id] = current.copy(complete = status.isComplete, bytes = status.completedResourceSize, progress = progress)
        if (status.isComplete && current.active) stop(region.id)
    }

    fun download(name: String, center: LatLng, radiusKm: Float) {
        if (creating || areas.values.any { it.active }) return
        val box = OutdoorData.bounds(center, radiusKm.coerceIn(2f, 15f) * 1000.0)
        // The SDK expects an ordinary non-wrapping geographic rectangle.
        if (box.w >= box.e || box.s >= box.n || center.lat !in -83.0..83.0) {
            message = "Choose a map area away from the poles."
            return
        }
        creating = true
        message = null
        val bounds = LatLngBounds.from(box.n, box.e, box.s, box.w)
        val definition = OfflineTilePyramidRegionDefinition(KiteMap.STYLE_URL, bounds, 9.0, 15.0,
            KiteApp.app.resources.displayMetrics.density, false)
        manager.createOfflineRegion(definition, name.trim().ifBlank { "Offline area" }.take(70).toByteArray(),
            object : OfflineManager.CreateOfflineRegionCallback {
                override fun onCreate(region: OfflineRegion) {
                    creating = false
                    register(region)
                    resume(region.id)
                }
                override fun onError(error: String) { creating = false; message = error }
            })
    }

    fun resume(id: Long) {
        if (areas.values.any { it.active }) return
        val area = areas[id]?.takeUnless { it.complete } ?: return
        val region = regions[id] ?: return
        message = null
        areas[id] = area.copy(active = true)
        region.setDownloadState(OfflineRegion.STATE_ACTIVE)
    }

    fun stop(id: Long) {
        val area = areas[id] ?: return
        areas[id] = area.copy(active = false)
        regions[id]?.setDownloadState(OfflineRegion.STATE_INACTIVE)
    }

    fun delete(id: Long) {
        stop(id)
        regions[id]?.delete(object : OfflineRegion.OfflineRegionDeleteCallback {
            override fun onDelete() { regions.remove(id); areas.remove(id) }
            override fun onError(error: String) { message = error }
        })
    }
}
