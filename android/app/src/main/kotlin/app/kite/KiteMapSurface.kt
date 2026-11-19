package app.kite

import android.content.Context
import android.view.MotionEvent
import android.widget.FrameLayout
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.mapbox.maps.MapView as StandardMapView
import org.maplibre.android.maps.MapLibreMapOptions
import org.maplibre.android.maps.MapView

/** Keeps touch delivery on the visible map while the Standard renderer loads or falls back. */
class KiteMapSurface(
    context: Context, private val lifecycle: Lifecycle, kite: KiteMap, private val scenery: MapboxScenery,
) : FrameLayout(context) {
    private val classic = MapView(context, MapLibreMapOptions.createFromAttributes(context).textureMode(true))
    private var standard: StandardMapView? = null
    private var activeToken: String? = null
    private var useStandard = false
    private var destroyed = false
    private val observer = LifecycleEventObserver { _, event ->
        when (event) {
            Lifecycle.Event.ON_START -> classic.onStart()
            Lifecycle.Event.ON_RESUME -> classic.onResume()
            Lifecycle.Event.ON_PAUSE -> classic.onPause()
            Lifecycle.Event.ON_STOP -> classic.onStop()
            Lifecycle.Event.ON_DESTROY -> dispose()
            else -> Unit
        }
    }

    init {
        addView(classic, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        classic.onCreate(null)
        kite.attach(classic)
        lifecycle.addObserver(observer)
    }

    fun show(token: String?, ready: Boolean, look: MapboxScenery.Look) {
        if (destroyed) return
        if (token != activeToken) {
            removeStandard()
            activeToken = token
            if (token != null) {
                scenery.setLook(look)
                standard = scenery.attach(context, token).also {
                    addView(it, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
                }
            }
        }
        useStandard = ready && standard != null
        standard?.alpha = if (useStandard) 1f else 0f
        classic.alpha = if (useStandard) 0f else 1f
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        val target = if (useStandard) standard else null
        if (target == null) return classic.dispatchTouchEvent(event)
        scenery.touch(event)
        return target.dispatchTouchEvent(event)
    }

    private fun removeStandard() {
        val map = standard ?: return
        scenery.detach(map)
        removeView(map)
        map.onDestroy()
        standard = null
    }

    fun dispose() {
        if (destroyed) return
        destroyed = true
        lifecycle.removeObserver(observer)
        removeStandard()
        classic.onDestroy()
    }
}
