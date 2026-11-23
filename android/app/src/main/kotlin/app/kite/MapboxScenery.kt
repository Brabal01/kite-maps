package app.kite

import android.content.Context
import android.graphics.Color
import android.util.Log
import android.view.MotionEvent
import android.widget.Toast
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.kite.core.*
import com.mapbox.bindgen.Value
import com.mapbox.common.MapboxOptions
import com.mapbox.geojson.Feature
import com.mapbox.geojson.FeatureCollection
import com.mapbox.geojson.Point
import com.mapbox.maps.CameraOptions
import com.mapbox.maps.EdgeInsets
import com.mapbox.maps.MapInitOptions
import com.mapbox.maps.MapView
import com.mapbox.maps.RenderedQueryGeometry
import com.mapbox.maps.RenderedQueryOptions
import com.mapbox.maps.ScreenBox
import com.mapbox.maps.ScreenCoordinate
import com.mapbox.maps.Style
import com.mapbox.maps.extension.style.expressions.generated.Expression
import com.mapbox.maps.extension.style.layers.addLayer
import com.mapbox.maps.extension.style.layers.generated.*
import com.mapbox.maps.extension.style.layers.properties.generated.*
import com.mapbox.maps.extension.style.sources.addSource
import com.mapbox.maps.extension.style.sources.generated.*
import com.mapbox.maps.extension.style.sources.getSourceAs
import com.mapbox.maps.extension.style.terrain.generated.Terrain
import com.mapbox.maps.extension.style.terrain.generated.removeTerrain
import com.mapbox.maps.extension.style.terrain.generated.setTerrain
import com.mapbox.maps.plugin.animation.camera
import com.mapbox.maps.plugin.animation.easeTo
import com.mapbox.maps.plugin.animation.MapAnimationOptions.Companion.mapAnimationOptions
import com.mapbox.maps.plugin.attribution.AttributionDialogManagerImpl
import com.mapbox.maps.plugin.attribution.attribution
import com.mapbox.maps.plugin.gestures.addOnMapClickListener
import com.mapbox.maps.plugin.gestures.addOnMapLongClickListener
import com.mapbox.maps.plugin.logo.logo
import com.mapbox.common.NetworkRestriction
import com.mapbox.common.TileRegionLoadOptions
import com.mapbox.common.TileStore
import com.mapbox.geojson.LineString
import com.mapbox.maps.OfflineManager
import com.mapbox.maps.TilesetDescriptorOptions
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.Job
import kotlinx.coroutines.withContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.yield
import org.maplibre.android.camera.CameraPosition
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor

/** Mapbox Standard paints the map and mirrors Kite's existing route, alert and place overlays. */
class MapboxScenery(private val model: AppModel, private val kite: KiteMap) {
    data class Look(val dark: Boolean, val satellite: Boolean, val terrain: Boolean, val shade: Boolean,
                    val shadows: Boolean, val lamps: Boolean, val traffic: Boolean = true,
                    val palette: MapPalette = MapPalette.default(dark), val driving: Boolean = false)

    private var view: MapView? = null
    private var attributionDialog: AttributionDialogManagerImpl? = null
    private var style: Style? = null
    private var look = Look(false, false, false, false, true, true)
    private var movingFromTouch = false
    private var downX = 0f
    private var downY = 0f
    private var destroying = false
    private var lampJob: Job? = null
    private val lampRequests = mutableMapOf<Pair<Int, Int>, Deferred<LampArea?>>()
    private var routeTileKey: Pair<String, Int>? = null
    private var routeTileLoad: com.mapbox.common.Cancelable? = null
    private val tileStore by lazy { TileStore.create() }
    private var routeTileDescriptor: com.mapbox.common.TilesetDescriptor? = null
    private var watchdog: Job? = null
    private var styleRequest = 0
    private var submittedCamera: CameraPosition? = null
    private var lastCameraCorrection = 0L
    private var cameraEase: com.mapbox.common.Cancelable? = null
    private var cameraEaseSync: Job? = null
    private var lastLampCell: Pair<Int, Int>? = null
    private var errorSubscription: com.mapbox.common.Cancelable? = null
    private var idleSubscription: com.mapbox.common.Cancelable? = null
    private data class Lamp(val at: LatLng, val bearing: Double = 0.0, val pool: LatLng = at)
    private data class LampArea(val mapped: List<Lamp>, val inferred: List<Lamp>)
    private var lastLampCenter: LatLng? = null
    private var lampRequestAt = 0L
    private val lampCache = object : LinkedHashMap<Pair<Int, Int>, LampArea>(12, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<Pair<Int, Int>, LampArea>?) = size > 12
    }
    private val overlayData = mutableMapOf<String, String>()
    private val pendingOverlays = linkedMapOf<String, () -> String>()
    private var overlayJob: Job? = null
    fun renders(source: String) = source in overlaySources

    fun refreshPinSizes() { style?.let(::applyPinSizes) }

    private fun applyPinSizes(st: Style) {
        val sizes = MapPinSizes.read()
        for (id in listOf(GOOGLE_PLACES, KiteMap.GOOGLE_UNREVIEWED))
            st.setStyleLayerProperty(id, "icon-size", Value.valueOf(sizes.google))
        st.setStyleLayerProperty(OpenMapStyle.POIS, "icon-size", Value.valueOf(0.55 * sizes.osm))
        st.setStyleLayerProperty("kite-vela-results", "icon-size", Value.valueOf(0.72 * sizes.search))
        st.setStyleLayerProperty("kite-search-hit", "circle-radius", Value.valueOf(14.0 * sizes.search))
        Value.fromJson("[0,${1.15 * sizes.search}]").value?.let { st.setStyleLayerProperty("kite-vela-results", "text-offset", it) }
    }

    fun showTransit(show: Boolean) {
        style?.setStyleLayerProperty("kite-rail", "visibility", Value.valueOf(if (show) "visible" else "none"))
    }

    fun applyOutdoorLayers() { style?.let(::applyOutdoorLayers) }

    private fun applyOutdoorLayers(st: Style) {
        val s = AppSettings
        fun show(id: String, enabled: Boolean) {
            st.setStyleLayerProperty(id, "visibility", Value.valueOf(if (enabled) "visible" else "none"))
        }
        val groups = OpenMapStyle.visibleGroups(model)
        show(OpenMapStyle.POIS, groups.isNotEmpty())
        show(OpenMapStyle.HIKING, s.hikingTrails)
        show(OpenMapStyle.CYCLING, s.bikeTrails)
        show(OpenMapStyle.WALK_PATHS, s.hikingTrails)
        show(OpenMapStyle.BIKE_PATHS, s.bikeTrails)
        Value.fromJson(OpenMapStyle.filter(groups)).value?.let {
            st.setStyleLayerProperty(OpenMapStyle.POIS, "filter", it)
        }
    }
    var ready by mutableStateOf(false)
        private set
    var failed by mutableStateOf(false)
        private set

    fun allowRetry() { failed = false }

    fun pointAt(x: Float, y: Float): LatLng? =
        view?.takeIf { ready }?.mapboxMap?.coordinateForPixel(ScreenCoordinate(x.toDouble(), y.toDouble()))?.kite()
    fun centerPoint(): LatLng? = view?.let { pointAt(it.width / 2f, it.height / 2f) }

    fun openAttribution(): Boolean {
        val v = view ?: return false
        if (!ready) return false
        val dialog = attributionDialog ?: return false
        dialog.showAttribution(v.attribution.getMapAttributionDelegate())
        return true
    }

    fun attach(context: Context, token: String): MapView {
        destroying = false
        submittedCamera = null
        MapboxOptions.accessToken = token
        val mapView = MapView(context, MapInitOptions(context, textureView = true, styleUri = null))
        view = mapView
        mapView.setMaximumFps(60)
        attributionDialog = AttributionDialogManagerImpl(context)
        val map = mapView.mapboxMap
        map.setPrefetchZoomDelta(2)
        mapView.logo.enabled = false
        mapView.attribution.enabled = false
        idleSubscription = map.subscribeMapIdle {
            val expected = model.glide.followingCamera
            val center = expected?.target
            val actual = map.cameraState
            val now = android.os.SystemClock.elapsedRealtime()
            if (expected != null && center != null && now - lastCameraCorrection >= 350L &&
                NavGlide.needsCameraCorrection(actual.center.kite(), center.kite(), actual.zoom, expected.zoom)) {
                lastCameraCorrection = now
                submitCamera(expected, force = true)
            }
            if (movingFromTouch && model.mapNavigator?.following != true) {
                copyCameraToKite(mapView)
                val camera = mapView.mapboxMap.cameraState
                model.noteSearchArea(camera.center.kite(), camera.zoom)
                movingFromTouch = false
            }
            refreshLamps()
        }
        errorSubscription = map.subscribeMapLoadingError { error ->
            if (error.type.name.startsWith("STYLE") && style == null) failStyle()
        }
        map.addOnMapClickListener { point ->
            if (model.streetViewMapTapped(point.kite()) || model.positionEndpointPin(point.kite())) true
            else if (model.stopSearch != null) {
                val search = model.stopSearch
                val pixel = map.pixelForCoordinate(point)
                val pad = 13.0 * context.resources.displayMetrics.density
                val hitbox = ScreenBox(ScreenCoordinate(pixel.x - pad, pixel.y - pad), ScreenCoordinate(pixel.x + pad, pixel.y + pad))
                map.queryRenderedFeatures(RenderedQueryGeometry(hitbox), RenderedQueryOptions(listOf("kite-stop-hit"), null)) { result ->
                    if (search != null && model.stopSearch?.results === search.results) model.selectStopPin(
                        result.value?.firstOrNull()?.queriedFeature?.feature?.getStringProperty("id"))
                }
                true
            } else if (model.nav != null && !model.placingStop) {
                navigationPlaceAt(mapView, point, longPress = false)
                true
            } else if (!model.placingStop && !model.isGuiding && model.directions == null) {
                val pixel = map.pixelForCoordinate(point)
                map.queryRenderedFeatures(RenderedQueryGeometry(pixel), RenderedQueryOptions(listOf("kite-vela-selected", "kite-search-hit", "kite-vela-results",
                    KiteMap.TRANSIT_STOPS, GOOGLE_PLACES, OpenMapStyle.POIS, KiteMap.GOOGLE_UNREVIEWED), null)) { result ->
                    val feature = result.value?.firstOrNull()?.queriedFeature?.feature
                    val loc = feature?.geometry() as? Point
                    if (feature == null || loc == null) kite.sceneTap(point.kite())
                    else {
                        fun str(key: String) = feature.getProperty(key)?.takeIf { it.isJsonPrimitive }?.asString
                        val id = str("id")
                        if (id != null && id == model.selected?.id) return@queryRenderedFeatures
                        if (!kite.openSearchResult(id) && !kite.openOutdoorPlace(id) && !kite.openGooglePlace(id)) {
                            val subclass = str("subclass")
                            val klass = str("class")
                            val name = OpenMapStyle.title(str("name"), subclass, klass)
                            model.select(Place("osm:${loc.latitude()},${loc.longitude()}:$name", name, loc.kite(), "osm",
                                category = subclass ?: klass))
                        }
                    }
                }
                true
            } else if (model.directions?.route != null && !model.placingStop) {
                val plan = model.directions
                val pixel = map.pixelForCoordinate(point)
                map.queryRenderedFeatures(RenderedQueryGeometry(pixel), RenderedQueryOptions(listOf("kite-route", "kite-edge"), null)) { result ->
                    if (model.directions !== plan) return@queryRenderedFeatures
                    if (result.value?.isNotEmpty() == true) model.askAvoid(point.kite()) else kite.sceneTap(point.kite())
                }
                true
            } else kite.sceneTap(point.kite())
        }
        map.addOnMapLongClickListener { point ->
            if (model.stopSearch == null && model.streetView == null) {
                if (model.nav != null && !model.placingStop) navigationPlaceAt(mapView, point, longPress = true)
                else kite.scenePress(point.kite())
            }
            true
        }
        load()
        return mapView
    }

    private fun navigationPlaceAt(mapView: MapView, point: Point, longPress: Boolean) {
        val nav = model.nav ?: return
        val map = mapView.mapboxMap
        val pixel = map.pixelForCoordinate(point)
        val pad = 12.0 * mapView.resources.displayMetrics.density
        val hitbox = ScreenBox(ScreenCoordinate(pixel.x - pad, pixel.y - pad), ScreenCoordinate(pixel.x + pad, pixel.y + pad))
        val layers = buildList {
            if (!longPress) addAll(listOf("kite-vela-waze", "kite-vela-waze-group"))
            if (AppSettings.navigationPlaces) addAll(listOf(GOOGLE_PLACES, KiteMap.GOOGLE_UNREVIEWED, OpenMapStyle.POIS))
        }
        if (layers.isEmpty()) return
        map.queryRenderedFeatures(RenderedQueryGeometry(hitbox), RenderedQueryOptions(layers, null)) { result ->
            if (view !== mapView || model.nav !== nav || model.stopSearch != null || model.placingStop) return@queryRenderedFeatures
            for (hit in result.value.orEmpty()) {
                val feature = hit.queriedFeature.feature
                fun str(key: String) = feature.getProperty(key)?.takeIf { it.isJsonPrimitive }?.asString
                if (!longPress && kite.openWazeAlert(str("id"))) return@queryRenderedFeatures
                val at = feature.geometry() as? Point ?: continue
                val group = str("class")
                val subclass = str("subclass")
                val place = kite.googlePlace(str("id")) ?: if (subclass != null || group != null) {
                    val name = OpenMapStyle.title(str("name") ?: str("name:en"), subclass, group)
                    Place("osm:${at.latitude()},${at.longitude()}:$name", name, at.kite(), "osm", category = subclass ?: group)
                } else continue
                if (longPress) {
                    mapView.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
                    model.addNavigationPlace(place)
                } else model.showNavigationPlace(place)
                return@queryRenderedFeatures
            }
            if (!longPress) model.showNavigationPlace(null)
        }
    }

    fun touch(event: MotionEvent) {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                if (cameraEase != null) {
                    cancelCameraEase()
                    view?.let(::copyCameraToKite)
                }
                downX = event.x
                downY = event.y
                movingFromTouch = false
                submittedCamera = null
                model.glide.mapTouched = true
            }
            MotionEvent.ACTION_MOVE -> if (event.pointerCount > 1 || abs(event.x - downX) + abs(event.y - downY) > 10f) {
                movingFromTouch = true
                model.mapNavigator?.following = false
                model.transitGuidance?.following = false
                model.stopTransitOverview()
                model.browseFollowing = false
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                model.glide.mapTouched = false
                if (movingFromTouch) view?.let { active ->
                    copyCameraToKite(active)
                    val camera = active.mapboxMap.cameraState
                    model.noteSearchArea(camera.center.kite(), camera.zoom)
                }
            }
        }
    }

    private fun failStyle() {
        if (destroying || failed || style != null) return
        watchdog?.cancel()
        ready = false
        failed = true
        view?.context?.let { Toast.makeText(it, "Mapbox style unavailable. Using the fallback map.", Toast.LENGTH_LONG).show() }
        Log.w("KiteScenery", "Mapbox style unavailable")
    }

    fun setLook(value: Look) {
        val previous = look
        if (previous == value) return
        look = value
        if (previous.satellite != value.satellite) load()
        else style?.let { applyLook(it, previous) }
    }

    fun syncFromKite(camera: CameraPosition) {
        if (model.mapNavigator?.following == true || cameraEase != null || movingFromTouch && model.glide.mapTouched) return
        submitCamera(camera, force = false)
    }

    fun followCamera(camera: CameraPosition, takeover: Boolean) {
        val mapView = view ?: return
        if (takeover || cameraEase != null) {
            cancelCameraEase()
            mapView.camera.cancelAllAnimators()
        }
        submitCamera(camera, force = takeover)
        if (takeover) {
            val guide = model.mapNavigator ?: return
            // Check the applied position once the SDK has processed that frame.
            mapView.postOnAnimation {
                if (view !== mapView || model.mapNavigator !== guide || !guide.following) return@postOnAnimation
                val expected = model.glide.followingCamera ?: return@postOnAnimation
                val center = expected.target ?: return@postOnAnimation
                val actual = mapView.mapboxMap.cameraState
                if (NavGlide.needsCameraCorrection(actual.center.kite(), center.kite(), actual.zoom, expected.zoom)) {
                    submitCamera(expected, force = true)
                }
            }
        }
    }

    private fun submitCamera(camera: CameraPosition, force: Boolean) {
        val map = view?.mapboxMap ?: return
        val at = camera.target ?: return
        val insets = camera.padding ?: DoubleArray(4)
        val previous = submittedCamera
        if (previous != null && !force) {
            val p = previous.padding ?: DoubleArray(4)
            if (abs(previous.zoom - camera.zoom) < 0.0007 && abs(previous.tilt - camera.tilt) < 0.05 &&
                abs((previous.bearing - camera.bearing + 540) % 360 - 180) < 0.06 &&
                insets.indices.all { abs(p[it] - insets[it]) < 0.4 } &&
                previous.target?.kite()?.distanceTo(at.kite())?.let { it < 0.14 } == true) return
        }
        movingFromTouch = false
        submittedCamera = camera
        cameraOptions(camera)?.let(map::setCamera)
    }

    private fun cameraOptions(camera: CameraPosition): CameraOptions? {
        val at = camera.target ?: return null
        val padding = camera.padding ?: DoubleArray(4)
        return CameraOptions.Builder().center(Point.fromLngLat(at.longitude, at.latitude))
            .zoom(camera.zoom).pitch(camera.tilt.coerceIn(0.0, 60.0)).bearing(camera.bearing)
            .padding(EdgeInsets(padding[1], padding[0], padding[3], padding[2])).build()
    }

    fun animateCamera(position: CameraPosition, duration: Int): Boolean {
        val mapView = view ?: return false
        if (model.mapNavigator?.following == true) return false
        val target = cameraOptions(position) ?: return false
        cancelCameraEase()
        model.map?.cancelTransitions()
        movingFromTouch = false
        submittedCamera = position
        if (duration <= 0) {
            mapView.mapboxMap.setCamera(target)
            copyCameraToKite(mapView)
            return true
        }
        cameraEase = mapView.mapboxMap.easeTo(target, mapAnimationOptions { duration(duration.toLong()) })
        cameraEaseSync = model.scope.launch {
            delay(duration + 32L)
            cameraEase = null
            if (view === mapView && model.mapNavigator?.following != true) copyCameraToKite(mapView)
        }
        return true
    }

    private fun cancelCameraEase() {
        cameraEaseSync?.cancel()
        cameraEaseSync = null
        cameraEase?.cancel()
        cameraEase = null
    }

    fun cameraPosition(): CameraPosition? = view?.let(::cameraPosition)

    private fun cameraPosition(mapView: MapView): CameraPosition {
        val c = mapView.mapboxMap.cameraState
        val p = c.padding
        return CameraPosition.Builder().target(c.center.kite().ml())
            .zoom(c.zoom).bearing(c.bearing).tilt(c.pitch).padding(p.left, p.top, p.right, p.bottom).build()
    }

    private fun copyCameraToKite(mapView: MapView) = kite.syncFromScenery(cameraPosition(mapView))

    fun updateOverlay(id: String, json: () -> String) {
        if (id !in overlaySources || view == null) return
        pendingOverlays[id] = json
        if (overlayJob?.isActive == true) return
        overlayJob = model.scope.launch {
            while (pendingOverlays.isNotEmpty() && view != null) {
                val batch = pendingOverlays.entries.take(5).associate { it.key to it.value }
                batch.keys.forEach(pendingOverlays::remove)
                val encoded = withContext(Dispatchers.Default) { batch.mapValues { (_, encode) -> encode() } }
                for ((source, value) in encoded) {
                    if (source in pendingOverlays) continue
                    if (overlayData.put(source, value) != value) style?.getSourceAs<GeoJsonSource>(source)?.data(value)
                }
                if (pendingOverlays.isNotEmpty()) delay(16) else yield()
            }
        }
    }

    fun updatePosition(fix: Fix) {
        val navigating = model.mapNavigator != null || model.cruise != null
        updateOverlay(LOCATION) {
            if (navigating) EMPTY else Feature.fromGeometry(Point.fromLngLat(fix.lng, fix.lat)).toJson()
        }
    }

    fun detach(mapView: MapView) {
        if (view !== mapView) return
        destroying = true
        cancelCameraEase()
        attributionDialog?.onStop()
        attributionDialog = null
        idleSubscription?.cancel()
        errorSubscription?.cancel()
        lampJob?.cancel()
        watchdog?.cancel()
        styleRequest++
        lastLampCell = null
        lastLampCenter = null
        lampRequestAt = 0L
        model.glide.mapTouched = false
        movingFromTouch = false
        ready = false
        style = null
        view = null
        overlayJob?.cancel()
        pendingOverlays.clear()
        overlayData.clear()
        prepareRoute(null, 0)
        lampRequests.values.forEach { it.cancel() }
        lampRequests.clear()
        routeTileDescriptor = null
    }

    private fun load() {
        val v = view ?: return
        cancelCameraEase()
        style = null
        lampJob?.cancel()
        lastLampCell = null
        lastLampCenter = null
        lampRequestAt = 0L
        val payload = if (look.satellite) SatelliteStyle.json(mapbox = true) else org.json.JSONObject()
            .put("version", 8).put("sources", org.json.JSONObject()).put("layers", org.json.JSONArray())
            .put("glyphs", "mapbox://fonts/mapbox/{fontstack}/{range}.pbf")
            .put("imports", org.json.JSONArray().put(org.json.JSONObject().put("id", "basemap").put("url", Style.STANDARD)
                .put("config", org.json.JSONObject().put("lightPreset", if (look.dark) "night" else "day"))))
            .toString()
        submittedCamera = null
        val request = ++styleRequest
        watchdog?.cancel()
        watchdog = model.scope.launch {
            delay(15_000)
            if (request == styleRequest) failStyle()
        }
        v.mapboxMap.loadStyle(payload) { loaded ->
            if (destroying || failed || view !== v || request != styleRequest) return@loadStyle
            watchdog?.cancel()
            try {
                addBasemapDetails(loaded)
                addOverlays(loaded)
                addPlaces(loaded)
                addSelectionAndStreetView(loaded)
                applyOutdoorLayers(loaded)
                addTraffic(loaded)
                if (!look.satellite) addLamps(loaded)
                applyLook(loaded)
                applyPinSizes(loaded)
                style = loaded
                val guidanceCamera = model.glide.followingCamera
                val latestCamera = guidanceCamera ?: submittedCamera ?: model.map?.cameraPosition
                submittedCamera = null
                if (guidanceCamera != null) followCamera(guidanceCamera, takeover = true)
                else latestCamera?.let { submitCamera(it, force = true) }
                LocationService.last?.let(::updatePosition)
                ready = true
                kite.refreshScenery()
                refreshLamps()
            } catch (e: Exception) {
                style = null
                Log.w("KiteScenery", "Mapbox style setup failed", e)
                failStyle()
            }
        }
    }

    private fun applyLook(st: Style, previous: Look? = null) {
        val themeChanged = previous == null || previous.dark != look.dark
        if (themeChanged) {
            val text = if (look.dark) "#F0F4FC" else "#202124"
            val halo = if (look.dark) "#172235" else "#FFFFFF"
            for (id in listOf(OpenMapStyle.POIS, GOOGLE_PLACES, KiteMap.GOOGLE_UNREVIEWED, KiteMap.TRANSIT_STOPS, "kite-vela-mine", "kite-vela-results", "kite-vela-selected")) {
                st.setStyleLayerProperty(id, "text-color", Value.valueOf(text))
                st.setStyleLayerProperty(id, "text-halo-color", Value.valueOf(halo))
            }
            if (previous == null) MapIcons.registerImages(look.dark) { id, bitmap -> st.addImage(id, bitmap) }
            else st.addImage("puck", MapIcons.puck(look.dark))
        }
        val paletteChanged = previous?.palette != look.palette
        if (themeChanged || paletteChanged || previous.satellite != look.satellite) {
            val configs = hashMapOf(
                "lightPreset" to Value.valueOf(if (look.dark && !look.satellite) "night" else "day"),
                "showPointOfInterestLabels" to Value.valueOf(false),
            )
            configs["show3dObjects"] = Value.valueOf(!look.satellite)
            if (!look.satellite) {
                configs["show3dTrees"] = Value.valueOf(true)
                configs["show3dLandmarks"] = Value.valueOf(true)
                configs["showHdRoads"] = Value.valueOf(true)
                for (field in MapColor.entries) field.styleKey?.let { configs[it] = Value.valueOf(look.palette[field]) }
                configs["colorTrunks"] = Value.valueOf(look.palette[MapColor.HIGHWAYS])
            }
            if (!look.satellite) st.setStyleImportConfigProperties("basemap", configs)
        }
        if (themeChanged || previous.satellite != look.satellite || previous.driving != look.driving) {
            fun visible(id: String, on: Boolean) {
                st.setStyleLayerProperty(id, "visibility", Value.valueOf(if (on) "visible" else "none"))
            }
            visible("kite-driving-side-streets", look.driving && !look.satellite)
            visible("kite-oneway", look.driving)
            st.setStyleLayerProperty("kite-driving-side-streets", "line-color", Value.valueOf(if (look.dark) "#74839C" else "#FFFFFF"))
            st.setStyleLayerProperty("kite-oneway", "text-color", Value.valueOf(if (look.dark || look.satellite) "#F4F7FF" else "#40536A"))
            st.setStyleLayerProperty("kite-oneway", "text-halo-color", Value.valueOf(if (look.dark || look.satellite) "#203045" else "#FFFFFF"))
        }
        if (paletteChanged) {
            val color = look.palette[MapColor.ROUTE]
            st.setStyleLayerProperty("kite-route", "line-color", Value.valueOf(color))
            val rgb = Color.parseColor(color)
            val edge = Color.rgb(Color.red(rgb) / 3, Color.green(rgb) / 3, Color.blue(rgb) / 3)
            st.setStyleLayerProperty("kite-edge", "line-color", Value.valueOf(String.format(java.util.Locale.US, "#%06X", edge and 0xFFFFFF)))
        }
        if (themeChanged || previous.shadows != look.shadows) {
            val ambient = if (look.dark) 0.24 else 0.8
            val sunlight = if (look.dark) 0.33 else 0.35
            val ambientColor = if (look.dark) "#A6BCEB" else "#FFF5E6"
            val lightColor = if (look.dark) "#D9D3FF" else "#FFF5E6"
            val pitch = if (look.dark) 62 else 48
            val lights = """[{"id":"kite-ambient","type":"ambient","properties":{"color":"$ambientColor","intensity":$ambient}},{"id":"kite-sun","type":"directional","properties":{"color":"$lightColor","direction":[210,$pitch],"intensity":$sunlight,"cast-shadows":${look.shadows},"shadow-intensity":0.48}}]"""
            Value.fromJson(lights).value?.let(st::setStyleLights)
        }
        if (!look.satellite && (look.terrain || look.shade) && !st.styleSourceExists(DEM)) {
            st.addSource(RasterDemSource.Builder(DEM)
                .tiles(listOf("https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"))
                .encoding(Encoding.TERRARIUM).tileSize(256).maxzoom(13).attribution("Terrain Tiles: Mapzen, AWS Open Data").build())
        }
        if (previous?.terrain != look.terrain) {
            if (look.terrain && !look.satellite) st.setTerrain(Terrain(DEM).exaggeration(1.15)) else st.removeTerrain()
        }
        if (previous?.shade != look.shade) {
            if (look.shade && !look.satellite && !st.styleLayerExists(SHADE))
                st.addLayer(HillshadeLayer(SHADE, DEM).slot("bottom").hillshadeExaggeration(0.32))
            if (st.styleLayerExists(SHADE))
                st.setStyleLayerProperty(SHADE, "visibility", Value.valueOf(if (look.shade) "visible" else "none"))
        }
        if (!look.satellite && (themeChanged || previous.lamps != look.lamps)) {
            for (id in listOf(LAMP_POST, LAMP_LENS, LAMP_POOL)) {
                st.setStyleLayerProperty(id, "visibility", Value.valueOf(
                    if (look.lamps && (id != LAMP_POOL || look.dark)) "visible" else "none"))
            }
            st.setStyleLayerProperty(LAMP_LENS, "model-emissive-strength", Value.valueOf(if (look.dark) 1.0 else 0.15))
            if (!look.lamps) {
                lampJob?.cancel()
                lampRequests.values.toList().forEach { it.cancel() }
                lampRequests.clear()
                lastLampCell = null
                lastLampCenter = null
                lampRequestAt = 0L
            } else refreshLamps()
        }
        if (previous?.traffic != look.traffic)
            st.setStyleLayerProperty(TRAFFIC, "visibility", Value.valueOf(if (look.traffic) "visible" else "none"))
    }

    private fun addBasemapDetails(st: Style) {
        st.addSource(VectorSource.Builder("kite-streets-details").url("mapbox://mapbox.mapbox-streets-v8").build())
        val street = """["all",["==",["geometry-type"],"LineString"],
            ["match",["get","class"],["street","street_limited","tertiary","service","secondary"],true,false]]"""
        st.addLayer(LineLayer("kite-driving-side-streets", "kite-streets-details").sourceLayer("road").slot("middle")
            .minZoom(14.5).filter(Expression.fromRaw(street)).lineCap(LineCap.ROUND).lineEmissiveStrength(0.35)
            .lineWidth(Expression.fromRaw("""["interpolate",["linear"],["zoom"],14,1.3,16,2.7,19,5.0]"""))
            .lineOpacity(0.68).visibility(Visibility.NONE))
        st.addLayer(SymbolLayer("kite-oneway", "kite-streets-details").sourceLayer("road").slot("top")
            .minZoom(15.7).filter(Expression.fromRaw("""["all",$street,["==",["to-string",["get","oneway"]],"true"]]"""))
            .symbolPlacement(SymbolPlacement.LINE).symbolSpacing(110.0).textField("→").textSize(15.0)
            .textKeepUpright(false).textRotationAlignment(TextRotationAlignment.MAP).textHaloWidth(0.8)
            .textHaloColor(if (look.dark) "#203045" else "#FFFFFF").visibility(Visibility.NONE))
    }

    private fun addOverlays(st: Style) {
        for (id in overlaySources) st.addSource(GeoJsonSource.Builder(id).data(overlayData[id] ?: EMPTY).build())
        fun line(id: String, source: String, color: Int, width: Double) = LineLayer(id, source).slot("middle")
            .lineColor(color).lineWidth(width).lineCap(LineCap.ROUND).lineJoin(LineJoin.ROUND).lineEmissiveStrength(0.9)
        st.addLayer(HeatmapLayer("kite-police-density", "vela-waze-heat").slot("middle").minZoom(5.0)
            .heatmapRadius(Expression.fromRaw("""["interpolate",["linear"],["zoom"],5,13,13,32,17,42]"""))
            .heatmapIntensity(1.3).heatmapOpacity(0.75)
            .heatmapColor(Expression.fromRaw("""["interpolate",["linear"],["heatmap-density"],0,"rgba(66,98,240,0)",0.2,"#5374F4",0.55,"#9259EC",1,"#EF76D9"]""")))
        st.addLayer(line("kite-alt", "vela-route-alt", 0xFF90BCD1.toInt(), 6.0))
        st.addLayer(line("kite-edge", "vela-route", 0xFF075964.toInt(), 13.0))
        st.addLayer(line("kite-route", "vela-route", 0xFF2DD4BF.toInt(), 8.0))
        st.addLayer(line("kite-path-section-edge", "kite-path-section", Color.WHITE, 15.0))
        st.addLayer(line("kite-path-section-fill", "kite-path-section", 0xFFE56C16.toInt(), 9.0))
        st.addLayer(SymbolLayer("kite-current-road-name", "vela-road-name").slot("top")
            .symbolPlacement(SymbolPlacement.LINE_CENTER).textField(Expression.get("label"))
            .textSize(16.0).textColor(Color.WHITE).textHaloColor(0xFF163242.toInt()).textHaloWidth(1.3))
        st.addLayer(line("kite-transit", "vela-transit", 0xFF377BE7.toInt(), 7.0)
            .lineColor(Expression.toColor(Expression.get("color")))
            .filter(Expression.fromRaw("""["==",["get","walk"],0]""")))
        st.addLayer(line("kite-transit-walk", "vela-transit", 0xFF64748B.toInt(), 5.0)
            .lineDasharray(listOf(0.4, 1.5)).filter(Expression.fromRaw("""["==",["get","walk"],1]""")))
        st.addLayer(line("kite-traffic-route", "vela-route-traffic", Color.RED, 8.0)
            .lineColor(Expression.fromRaw("""["match",["get","level"],1,"#F59E0B",2,"#EF4444",3,"#B91C1C","#EF4444"]""")))
        st.addLayer(line("kite-measure", "kite-measure", 0xFF8C61EF.toInt(), 3.3)
            .slot("top").lineDasharray(listOf(2.0, 1.4)))
        st.addLayer(CircleLayer("kite-measure-points", "kite-measure").slot("top")
            .filter(Expression.fromRaw("""["==",["geometry-type"],"Point"]""")).circleRadius(5.0)
            .circleColor("#8C61EF").circleStrokeColor(Color.WHITE).circleStrokeWidth(2.0).circleEmissiveStrength(1.0))
        st.addLayer(line("kite-rail", "vela-rail", 0xFF4D66BB.toInt(), 3.2)
            .lineColor(Expression.toColor(Expression.get("color"))).minZoom(10.0)
            .visibility(if (AppSettings.transitLines && model.nav == null) Visibility.VISIBLE else Visibility.NONE))
        st.addLayer(CircleLayer(KiteMap.RIDE_STOPS, KiteMap.RIDE_STOPS).slot("top").circleRadius(5.5)
            .circleColor(Expression.toColor(Expression.get("color"))).circleStrokeColor(Color.WHITE).circleStrokeWidth(2.0).circleEmissiveStrength(1.0))
        val vehicles = KiteMap.TRANSIT_VEHICLES
        st.addLayer(CircleLayer(vehicles, vehicles).slot("top").circleRadius(13.0)
            .circleColor(Expression.toColor(Expression.get("color"))).circleStrokeColor(Color.WHITE)
            .circleStrokeWidth(2.0).circleEmissiveStrength(1.0))
        st.addLayer(SymbolLayer("$vehicles-label", vehicles).slot("top")
            .textField(Expression.get("line")).textSize(11.0).textColor(Color.WHITE).textAllowOverlap(true)
            .textEmissiveStrength(1.0))
        st.addLayer(line("kite-turn-arrow", "vela-turn-arrow", Color.WHITE, 4.0))
        st.addLayer(CircleLayer("kite-search-hit", "vela-results").slot("top").circleRadius(14.0)
            .circleColor("#164B9F").circleOpacity(0.12).circleEmissiveStrength(1.0)
            .circlePitchAlignment(CirclePitchAlignment.VIEWPORT).circlePitchScale(CirclePitchScale.VIEWPORT))
        val iconSources = mapOf(
            "vela-mine" to null, "vela-results" to null, "vela-waze" to null,
            "vela-waze-group" to null, "vela-cameras" to null, "vela-livecams" to null,
            "vela-signals" to null, "vela-turn-head" to "turn-head", NavGlide.PUCK to null,
        )
        for ((source, image) in iconSources) {
            val layer = SymbolLayer("kite-$source", source).slot("top").iconSize(when (source) {
                NavGlide.PUCK -> 0.68
                "vela-results" -> 0.72
                "vela-signals", "vela-waze", "vela-waze-group", "vela-cameras" -> 1.17
                else -> 0.78
            }).iconAllowOverlap(source in setOf(NavGlide.PUCK, "vela-results", "vela-selected", "vela-waze", "vela-turn-head"))
            when {
                source == NavGlide.PUCK -> layer.iconImage(Expression.fromRaw("""["coalesce",["get","icon"],"puck"]"""))
                image == null -> layer.iconImage(Expression.get("icon"))
                else -> layer.iconImage(image)
            }
            if (source == "vela-signals") layer.minZoom(13.3).iconAllowOverlap(true)
            if (source == "vela-waze-group") layer.iconAllowOverlap(true)
            if (source == NavGlide.PUCK || source == "vela-turn-head") layer
                .iconRotate(Expression.get("bearing")).iconRotationAlignment(IconRotationAlignment.MAP)
            if (source == "vela-mine" || source == "vela-results" || source == "vela-selected") layer
                .textField(Expression.get("label")).textSize(if (source == "vela-results") 12.5 else 12.0)
                .textAnchor(TextAnchor.TOP).textOffset(listOf(0.0, if (source == "vela-results") 1.15 else 1.4))
                .textOptional(true)
                .textColor(if (look.dark) Color.WHITE else 0xFF23364B.toInt())
                .textHaloColor(if (look.dark) 0xFF21304A.toInt() else Color.WHITE).textHaloWidth(1.5)
            st.addLayer(layer)
        }
        st.addLayer(CircleLayer("kite-stop-hit", StopSearch.PINS).slot("top").circleRadius(12.0)
            .circleColor(Expression.fromRaw("""["case",["==",["get","selected"],true],"#B9384A","#115D65"]"""))
            .circleSortKey(Expression.fromRaw("""["case",["==",["get","selected"],true],1,0]"""))
            .circleStrokeColor(Color.WHITE).circleStrokeWidth(2.0).circleEmissiveStrength(1.0)
            .circlePitchAlignment(CirclePitchAlignment.VIEWPORT).circlePitchScale(CirclePitchScale.VIEWPORT))
        st.addLayer(SymbolLayer(StopSearch.PINS, StopSearch.PINS).slot("top").textAllowOverlap(true).textIgnorePlacement(true)
            .textField(Expression.fromRaw("""["to-string",["get","rank"]]""")).textSize(12.0).textColor(Color.WHITE))
        st.addLayer(CircleLayer("kite-current", LOCATION).slot("top").circleRadius(7.0).circleColor(0xFF00A8C5.toInt())
            .circleStrokeColor(Color.WHITE).circleStrokeWidth(2.5).circleEmissiveStrength(1.0))
    }

    private fun addPlaces(st: Style) {
        MapIcons.registerMapPlaces(look.satellite) { id, bitmap -> st.addImage(id, bitmap) }
        st.addSource(VectorSource.Builder(OpenMapStyle.SOURCE).url(OpenMapStyle.TILEJSON).build())
        fun marker(id: String, src: String) = SymbolLayer(id, src).slot("top")
            .iconSize(if (id == GOOGLE_PLACES || id == KiteMap.GOOGLE_UNREVIEWED) 1.01 else 0.74).iconPadding(4.0).textOptional(true).textAnchor(TextAnchor.TOP)
            .textOffset(listOf(0.0, 1.05)).textSize(12.0).textField(Expression.fromRaw("""["step",["zoom"],"",15,["get","name"]]"""))
            .textColor(if (look.dark) Color.WHITE else 0xFF263A4F.toInt())
            .textHaloColor(if (look.dark) 0xFF151F2A.toInt() else Color.WHITE).textHaloWidth(0.8).textHaloBlur(0.5).minZoom(13.0)
        st.addLayer(marker(KiteMap.GOOGLE_UNREVIEWED, "kite-google-places").iconImage(Expression.get("icon"))
            .filter(Expression.fromRaw("""["==",["get","reviewed"],false]""")))
        st.addLayer(marker(OpenMapStyle.POIS, OpenMapStyle.SOURCE).sourceLayer("poi")
            .symbolSortKey(Expression.fromRaw("""["coalesce",["get","rank"],9]"""))
            .iconImage(Expression.fromRaw(OpenMapStyle.icon)))
        for ((id, kind) in listOf(OpenMapStyle.HIKING to "hiking", OpenMapStyle.CYCLING to "cycling")) {
            st.addSource(RasterSource.Builder(id).tiles(listOf(OpenMapStyle.trailTile(kind)))
                .tileSize(256).minzoom(6).maxzoom(18).attribution(OpenMapStyle.ATTRIBUTION).build())
            st.addLayer(RasterLayer(id, id).slot("middle").rasterOpacity(0.9).visibility(Visibility.NONE))
        }
        for ((id, definition) in OpenMapStyle.pathLayers) {
            val (filter, tint) = definition
            st.addLayer(LineLayer(id, OpenMapStyle.SOURCE).sourceLayer("transportation").slot("middle")
                .filter(Expression.fromRaw(filter)).minZoom(14.0).lineColor(tint.toInt())
                .lineWidth(Expression.fromRaw("""["interpolate",["linear"],["zoom"],14,1.4,19,3.2]"""))
                .lineOpacity(0.82).lineCap(LineCap.ROUND).lineEmissiveStrength(0.65).visibility(Visibility.NONE))
        }
        st.addLayer(marker(GOOGLE_PLACES, "kite-google-places").iconImage(Expression.get("icon"))
            .filter(Expression.fromRaw("""["==",["get","reviewed"],true]""")))
        st.addLayer(marker(KiteMap.TRANSIT_STOPS, KiteMap.TRANSIT_STOPS).iconImage(Expression.get("icon"))
            .textField(Expression.get("name")).minZoom(11.5))
    }

    private fun addSelectionAndStreetView(st: Style) {
        val pano = KiteMap.STREET_VIEW
        st.addLayer(FillLayer("$pano-cone", pano).slot("top")
            .fillColor(0xFF0EA5A4.toInt()).fillOpacity(0.35).fillOutlineColor(0xFF15807C.toInt()).fillEmissiveStrength(1.0))
        for ((role, radius) in listOf("link" to 5.0, "position" to 8.0)) {
            st.addLayer(CircleLayer("$pano-$role", pano).slot("top").circleRadius(radius)
                .filter(Expression.fromRaw("""["==",["get","role"],"$role"]"""))
                .circleColor(0xFF127A79.toInt()).circleStrokeColor(Color.WHITE).circleStrokeWidth(2.0)
                .circlePitchAlignment(CirclePitchAlignment.VIEWPORT).circleEmissiveStrength(1.0))
        }
        val selected = "vela-selected"
        st.addLayer(SymbolLayer("kite-vela-selected", selected).slot("top").iconImage(Expression.get("icon"))
            .iconAnchor(Expression.fromRaw("""["coalesce",["get","anchor"],"center"]"""))
            .iconSize(0.95).iconAllowOverlap(true).iconIgnorePlacement(true)
            .iconEmissiveStrength(1.0).textOptional(true).textAnchor(TextAnchor.TOP).textOffset(listOf(0.0, 0.75))
            .textField(Expression.get("label")).textSize(12.0).textHaloWidth(1.5))
    }

    private fun addTraffic(st: Style) {
        st.addSource(VectorSource.Builder(TRAFFIC).url("mapbox://mapbox.mapbox-traffic-v1").build())
        st.addLayer(LineLayer(TRAFFIC, TRAFFIC).sourceLayer("traffic").slot("middle").minZoom(9.0)
            .visibility(if (look.traffic) Visibility.VISIBLE else Visibility.NONE)
            .lineColor(Expression.fromRaw("""["match",["get","congestion"],"moderate","#F59E0B","heavy","#EF4444","severe","#B91C1C","rgba(0,0,0,0)"]"""))
            .lineWidth(Expression.fromRaw("""["interpolate",["linear"],["zoom"],9,1,17,3]""")).lineOffset(1.5)
            .lineEmissiveStrength(0.7))
    }

    private fun addLamps(st: Style) {
        st.addSource(GeoJsonSource.Builder(LAMPS).data(EMPTY).build())
        st.addSource(GeoJsonSource.Builder(LAMP_GLOWS).data(EMPTY).build())
        st.addStyleModel("kite-model-post", "asset://models/lamp.glb")
        st.addStyleModel("kite-model-lens", "asset://models/lamp_lens.glb")
        st.addLayer(CircleLayer(LAMP_POOL, LAMP_GLOWS).slot("middle").circleColor("#FFCA78").circleBlur(0.95)
            .circleOpacity(0.62).circlePitchAlignment(CirclePitchAlignment.MAP).circlePitchScale(CirclePitchScale.MAP)
            .circleEmissiveStrength(1.0).circleRadius(Expression.fromRaw("""["interpolate",["exponential",2],["zoom"],14.3,5,21,280]""")).minZoom(14.3))
        for ((layer, id) in listOf(LAMP_POST to "kite-model-post", LAMP_LENS to "kite-model-lens")) {
            st.addLayer(ModelLayer(layer, LAMPS).slot("middle").modelId(id).modelType(ModelType.COMMON_3D)
                .modelScale(listOf(2.2, 2.2, 2.2)).modelRotation(Expression.get("rotation"))
                .modelAllowDensityReduction(false).modelCastShadows(false).modelReceiveShadows(false).minZoom(14.3))
        }
    }

    /** Keep one small Mapbox tile region and the nearest lamp cells ready ahead of the driver. */
    fun prepareRoute(route: Route?, section: Int) {
        val mapView = view
        if (route == null || route.mode != TravelMode.DRIVE || mapView == null || !ready || look.satellite) {
            if (routeTileKey != null) {
                routeTileLoad?.cancel()
                routeTileLoad = null
                routeTileKey = null
                runCatching { tileStore.removeTileRegion(ROUTE_TILE_REGION) }
            }
            return
        }
        val from = section * 1_800.0
        if (look.lamps) requestLampArea(lampCell(Geo.point(route.polyline, from + 720.0)))
        val key = route.id to section
        if (key == routeTileKey) return
        val corridor = Geo.slice(route.polyline, from, from + 2_250.0)
        if (corridor.size < 2) return
        routeTileLoad?.cancel()
        routeTileKey = key
        runCatching {
            val descriptor = routeTileDescriptor ?: OfflineManager().createTilesetDescriptor(
                TilesetDescriptorOptions.Builder().styleURI(Style.STANDARD).minZoom(15).maxZoom(17)
                    .pixelRatio(mapView.resources.displayMetrics.density).build()
            ).also { routeTileDescriptor = it }
            routeTileLoad = tileStore.loadTileRegion(ROUTE_TILE_REGION, TileRegionLoadOptions.Builder()
                .geometry(LineString.fromLngLats(corridor.map { Point.fromLngLat(it.lng, it.lat) }))
                .descriptors(listOf(descriptor)).acceptExpired(true)
                .networkRestriction(NetworkRestriction.DISALLOW_EXPENSIVE).build()
            ) { result ->
                if (result.isError) Log.d("KiteScenery", "Route tile prefetch unavailable")
            }
        }.onFailure { Log.d("KiteScenery", "Route tile prefetch unavailable", it) }
    }

    private fun lampCell(at: LatLng): Pair<Int, Int> =
        floor(at.lat / 0.01).toInt() to floor(at.lng / 0.01).toInt()

    private fun requestLampArea(cell: Pair<Int, Int>): Deferred<LampArea?>? {
        if (cell in lampCache) return null
        lampRequests[cell]?.let { return it }
        if (lampRequests.size >= 2) return null
        return model.scope.async {
            try {
                val mid = LatLng((cell.first + 0.5) * 0.01, (cell.second + 0.5) * 0.01)
                val lngSpan = 0.012 / cos(Math.toRadians(mid.lat)).coerceAtLeast(0.35)
                val box = "${(mid.lat - 0.012).coerceAtLeast(-90.0)},${(mid.lng - lngSpan).coerceAtLeast(-180.0)}," +
                    "${(mid.lat + 0.012).coerceAtMost(90.0)},${(mid.lng + lngSpan).coerceAtMost(180.0)}"
                val raw = Overpass.queryLocal(
                    """[out:json][timeout:9];node["highway"="street_lamp"]($box);out body 2000;way["highway"]["lit"="yes"]($box);out tags geom($box) 600;way["highway"~"^(residential|living_street)$"]["lit"!~"^(no|disused)$"]["access"!~"^(no|private)$"]($box);out tags geom($box) 420;"""
                ) ?: return@async null
                withContext(Dispatchers.Default) { parseLamps(raw, mid) }.also { lampCache[cell] = it }
            } finally { lampRequests.remove(cell) }
        }.also { lampRequests[cell] = it }
    }

    fun refreshLamps() {
        val map = view?.mapboxMap ?: return
        val st = style ?: return
        if (!ready || look.satellite || !look.lamps || model.glide.mapTouched || model.placingStop || model.stopSearch != null) return
        val cam = map.cameraState
        if (cam.zoom < 14.3) return
        val center = cam.center.kite()
        val cell = lampCell(center)
        val currentTime = android.os.SystemClock.elapsedRealtime()
        if (lastLampCell == cell && lampJob?.isActive == true) return
        val cached = lampCache[cell]
        if (lastLampCell == cell && cached != null && lastLampCenter?.distanceTo(center)?.let { it < 180 } == true) return
        val interval = if (lastLampCell == cell && cached == null) 15_000 else 1_100
        if (lampRequestAt != 0L && currentTime - lampRequestAt < interval) return
        lampRequestAt = currentTime
        lastLampCell = cell
        lastLampCenter = center
        lampJob?.cancel()
        lampJob = model.scope.launch {
            val lamps = cached ?: requestLampArea(cell)?.await()
                ?: lampCache.entries.firstOrNull { (key, _) ->
                    abs(key.first - cell.first) <= 1 && abs(key.second - cell.second) <= 1
                }?.value ?: return@launch
            val budget = if (look.shadows && model.mapNavigator?.following == true) 44 else 65
            val (features, pools) = withContext(Dispatchers.Default) {
                val actual = lamps.mapped.filter { center.distanceTo(it.at) < 1_300 }
                val nearby = (actual + lamps.inferred.filter { center.distanceTo(it.at) < 1_000 })
                    .sortedBy { center.distanceTo(it.at) }.take(budget)
                val models = nearby.map { lamp ->
                    Feature.fromGeometry(Point.fromLngLat(lamp.at.lng, lamp.at.lat)).apply {
                        addProperty("rotation", com.google.gson.JsonArray().apply {
                            add(0.0); add(0.0); add(lamp.bearing)
                        })
                    }
                }
                FeatureCollection.fromFeatures(models).toJson() to FeatureCollection.fromFeatures(
                    nearby.map { Feature.fromGeometry(Point.fromLngLat(it.pool.lng, it.pool.lat)) }
                ).toJson()
            }
            if (lastLampCell != cell || style !== st || !look.lamps) return@launch
            st.getSourceAs<GeoJsonSource>(LAMPS)?.data(features)
            st.getSourceAs<GeoJsonSource>(LAMP_GLOWS)?.data(pools)
        }
    }

    private fun parseLamps(raw: ByteArray, center: LatLng): LampArea {
        fun point(item: Map<String, Any?>): LatLng? {
            val lat = item["lat"].num() ?: return null
            val lng = item["lon"].num() ?: return null
            return LatLng(lat, lng)
        }
        val elements = Json.obj(raw)?.get("elements").asMaps().orEmpty()
        val mapped = elements.filter { it["type"] == "node" }.mapNotNull(::point)
        val roads = elements.filter { it["type"] == "way" }.distinctBy { it["id"] }.flatMap { way ->
            val lit = way["tags"].asMap()?.get("lit") == "yes"
            val runs = mutableListOf<List<LatLng>>()
            var run = mutableListOf<LatLng>()
            for (item in way["geometry"].asList().orEmpty()) {
                val next = item.asMap()?.let(::point)
                if (next != null) run += next
                else {
                    if (run.size > 1) runs += run
                    run = mutableListOf()
                }
            }
            if (run.size > 1) runs += run
            runs.map { lit to it }
        }.sortedByDescending { it.first }
        val latScale = 111_320.0
        val lngScale = latScale * cos(Math.toRadians(center.lat)).coerceAtLeast(0.1)
        fun square(at: LatLng) = floor(at.lat * latScale / 38).toInt() to floor(at.lng * lngScale / 38).toInt()
        val grid = mutableMapOf<Pair<Int, Int>, MutableList<LatLng>>()
        fun occupy(at: LatLng) { grid.getOrPut(square(at)) { mutableListOf() }.add(at) }
        mapped.forEach(::occupy)
        val inferred = mutableListOf<Lamp>()
        for ((lit, road) in roads) {
            if (!lit && (mapped.size >= 24 || inferred.size >= 90)) continue
            val cum = Geo.cumulative(road)
            var distance = 22.0
            while (distance < cum.last() - 8.0) {
                val onRoad = Geo.point(road, distance, cum)
                val dir = Geo.bearing(Geo.point(road, distance - 5.0, cum), Geo.point(road, distance + 5.0, cum))
                val side = Math.toRadians(dir + if (Geo.drivesOnLeft(onRoad)) 90 else -90)
                val at = LatLng(onRoad.lat + 4 * cos(side) / latScale, onRoad.lng + 4 * kotlin.math.sin(side) / lngScale)
                val (x, y) = square(at)
                val taken = (-1..1).any { dx -> (-1..1).any { dy ->
                    grid[x + dx to y + dy]?.any { it.distanceTo(at) < 36 } == true
                } }
                if (!taken) {
                    occupy(at)
                    inferred += Lamp(at, Math.toDegrees(side) + 180, onRoad)
                }
                distance += 46.0
            }
        }
        return LampArea(mapped.map(::Lamp), inferred)
    }

    private fun Point.kite() = LatLng(latitude(), longitude())

    companion object {
        private const val ROUTE_TILE_REGION = "kite-driving-ahead"
        private const val EMPTY = """{"type":"FeatureCollection","features":[]}"""
        private const val GOOGLE_PLACES = "kite-standard-google-places"
        private const val LOCATION = "kite-location"
        private const val TRAFFIC = "kite-standard-traffic"
        private const val DEM = "kite-dem"
        private const val SHADE = "kite-hillshade"
        private const val LAMPS = "kite-lamps"
        private const val LAMP_GLOWS = "kite-lamp-glows"
        private const val LAMP_POST = "kite-lamp-post"
        private const val LAMP_LENS = "kite-lamp-lens"
        private const val LAMP_POOL = "kite-lamp-pool"
        private val overlaySources = setOf(LOCATION, NavGlide.PUCK, "vela-route", "vela-route-alt", "kite-path-section",
            "vela-route-traffic", "vela-turn-arrow", "vela-turn-head", "vela-transit", "vela-results", "vela-selected",
            "vela-road-name", "vela-mine", "vela-waze", "vela-waze-group", "vela-cameras", "vela-livecams", "vela-signals", "vela-waze-heat", "kite-google-places", "kite-measure", "vela-rail", KiteMap.TRANSIT_STOPS, KiteMap.RIDE_STOPS, KiteMap.TRANSIT_VEHICLES, KiteMap.STREET_VIEW, StopSearch.PINS)
    }
}
