package app.kite

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.PointF
import android.graphics.RectF
import android.location.Location
import android.util.Log
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.widget.Toast
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.maplibre.android.MapLibre
import org.maplibre.android.WellKnownTileServer
import app.kite.core.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.location.LocationComponentActivationOptions
import org.maplibre.android.location.LocationComponentOptions
import org.maplibre.android.location.modes.CameraMode
import org.maplibre.android.location.modes.RenderMode
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.expressions.Expression
import org.maplibre.android.style.expressions.Expression.*
import org.maplibre.android.style.layers.*
import org.maplibre.android.style.layers.PropertyFactory.*
import org.maplibre.android.style.sources.GeoJsonOptions
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.android.style.sources.RasterSource
import org.maplibre.android.style.sources.TileSet
import org.maplibre.android.style.sources.VectorSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point
import org.maplibre.geojson.Polygon
import kotlin.math.*

/**
 * The full-screen map: OpenFreeMap Liberty painted in Kite's colors, plus Kite's own layers
 * (result pins, routes with traffic, the navigation puck, live traffic, satellite). The same
 * layers, in the same order, as the iPhone app's map.
 */
class KiteMap(private val model: AppModel, private val context: Context) {
    companion object {
        const val INDOOR = "kite-indoor"
        const val PROFILE_PROBE = "kite-profile-probe"
        const val STREET_VIEW = "kite-street-view"
        const val STYLE_URL = "https://tiles.openfreemap.org/styles/liberty"
        /** How see-through cameras and reports off your route are while driving. */
        const val OFF_ROUTE_OPACITY = 0.3
        /** Reports that always keep their own icon, never joining a numbered bubble. */
        val NEVER_GROUPED = setOf(WazeAlert.Kind.POLICE, WazeAlert.Kind.ACCIDENT)
        const val GOOGLE_UNREVIEWED = "kite-google-unreviewed"
        const val TRANSIT_STOPS = "kite-transit-stops"
        const val RIDE_STOPS = "kite-ride-stops"
        const val TRANSIT_VEHICLES = "kite-transit-vehicles"
        private val classicHitSources = setOf("vela-route-alt", "vela-route-bubbles", "vela-mine", "vela-selected",
            "vela-results", "vela-waze", "vela-waze-group", "vela-cameras", "vela-livecams")
        private val STOCK_POI = listOf("poi_r1", "poi_r7", "poi_r20", "poi_transit", "airport")
        private fun c(hex: Long, a: Float = 1f) = Color.argb((a * 255).toInt(), ((hex shr 16) and 0xFF).toInt(), ((hex shr 8) and 0xFF).toInt(), (hex and 0xFF).toInt())
        private fun hex(l: Long) = String.format("#%06X", l and 0xFFFFFF)
    }

    var scenery: MapboxScenery? = null
    private var syncingClassic = false
    private var lastClassicCamera = 0L

    private fun driveCamera(camera: CameraPosition, synchronize: Boolean) {
        if (synchronize) map?.cancelTransitions()
        val native = scenery?.takeIf { it.ready }
        if (native == null) {
            syncFromScenery(camera)
            return
        }
        native.followCamera(camera, synchronize)
        val time = android.os.SystemClock.elapsedRealtime()
        if (synchronize || time - lastClassicCamera >= 950L) {
            lastClassicCamera = time
            syncFromScenery(camera)
            native.refreshLamps()
        }
    }

    fun syncFromScenery(camera: CameraPosition) {
        val m = map ?: return
        if (m.cameraPosition == camera) return
        syncingClassic = true
        try {
            m.moveCamera(org.maplibre.android.camera.CameraUpdateFactory.newCameraPosition(camera))
        } finally { syncingClassic = false }
    }

    fun refreshProfileProbe() {
        val style = map?.style?.takeIf { styleReady }
        setShape(style, PROFILE_PROBE, listOfNotNull((model.profileProbe ?: model.stationEntrance)?.let { point(it, emptyMap()) }))
    }

    fun refreshIndoor() {
        val style = map?.style?.takeIf { styleReady }
        val view = model.indoorView
        val features = if (view == null) emptyList() else buildList {
            for (item in view.plan.features) {
                if (view.floor !in item.floors) continue
                val geometry = item.geometry
                val props = mapOf("role" to "area", "kind" to item.kind)
                if (geometry.size >= 4 && geometry.first() == geometry.last()) {
                    add(Feature.fromGeometry(Polygon.fromLngLats(listOf(geometry.map { Point.fromLngLat(it.lng, it.lat) }))).also {
                        it.addStringProperty("role", "area")
                        it.addStringProperty("kind", item.kind)
                    })
                } else if (geometry.size > 1) add(polyline(geometry, props))
                val label = item.name ?: continue
                val center = LatLng(geometry.map { it.lat }.average(), geometry.map { it.lng }.average())
                add(point(center, mapOf("role" to "label", "label" to label)))
            }
        }
        setShape(style, INDOOR, features)
    }

    fun refreshStreetView() {
        val style = map?.style?.takeIf { styleReady }
        val frame = model.streetViewFrame
        val features = if (frame == null) emptyList() else buildList {
            val sweep = (-30..30 step 10).map { angle ->
                Geo.destination(frame.at, frame.heading + angle.toDouble(), 38.0)
            }
            val ring = (listOf(frame.at) + sweep + frame.at).map { Point.fromLngLat(it.lng, it.lat) }
            add(Feature.fromGeometry(Polygon.fromLngLats(listOf(ring))))
            add(point(frame.at, mapOf("role" to "position")))
            frame.links.forEach { add(point(it, mapOf("role" to "link"))) }
        }
        setShape(style, STREET_VIEW, features)
    }

    fun pointAt(x: Float, y: Float): LatLng? = map?.projection?.fromScreenLocation(PointF(x, y))?.kite()
    fun centerPoint(): LatLng? = view?.let { pointAt(it.width / 2f, it.height / 2f) }

    fun sceneTap(point: LatLng): Boolean = map?.let { tapped(it, point.ml()) } ?: false
    fun openWazeAlert(id: String?): Boolean {
        val alert = model.nav?.routeWaze?.firstOrNull { it.alert.id == id }?.alert
            ?: model.nav?.liveAlerts?.firstOrNull { it.id == id } ?: wazeAlerts.firstOrNull { it.id == id } ?: return false
        if (!(if (model.nav == null) AppSettings.shows(alert) else AppSettings.showsOnRoad(alert))) return false
        model.wazeInfo = alert
        return true
    }

    fun scenePress(point: LatLng) { map?.let { pressed(it, point.ml()) } }

    fun refreshScenery() {
        routeContext = ""
        lastRoadNameKey = ""
        transitStopsKey = ""
        vehicleKey = ""
        layerOptions = null
        policeHeatKey = null
        lastResultsKey = ""; lastRouteKey = ""; lastMineKey = ""; lastCameraKey = ""
        lastWazeKey = ""; lastLiveKey = ""; lastSignalsKey = ""; lastHeadKey = ""; lastNextRoadKey = ""; lastPuckKey = ""
        shownStopPins = null
        shownMeasurement = null
        shownGooglePlaces = null
        shownTransitStops = null
        map?.let(::loadGooglePlaces)
        map?.style?.let { setShape(it, "vela-rail", railFeatures) }
        if (model.streetViewFrame != null) refreshStreetView()
        refreshProfileProbe()
        refreshIndoor()
        render()
    }

    fun openSearchResult(id: String?): Boolean {
        val place = model.visibleResults.firstOrNull { it.id == id } ?: return false
        model.select(place)
        return true
    }

    fun googlePlace(id: String?): Place? = googlePlaces.firstOrNull { it.id == id }

    fun openGooglePlace(id: String?): Boolean {
        val place = googlePlaces.firstOrNull { it.id == id } ?: return false
        model.select(place)
        return true
    }

    var dark = true
        private set
    private var map: MapLibreMap? = null
    private var view: MapView? = null
    private val scope get() = model.scope
    private var styleReady = false
    private var selectedStyle: Basemap? = null
    private var loadingStyle: Basemap? = null
    var showingMapbox by mutableStateOf(false)
        private set
    private val overlayFont get() = arrayOf(if (showingMapbox) "Open Sans Bold" else "Noto Sans Bold")

    private data class Basemap(val url: String, val token: String? = null, val json: String? = null)
    private var movedToUser = false
    private var pinDroppedAt = 0L
    private val originalLabels = mutableMapOf<String, Triple<PropertyValue<*>, PropertyValue<*>, PropertyValue<*>>>()
    private var lastResultsKey = ""
    private var lastRouteKey = ""
    private var lastMineKey = ""
    private var lastPuckKey = ""
    private var lastHeadKey = ""
    private var lastNextRoadKey = ""
    private var lastRoadNameKey = ""
    private var styledDriving: Boolean? = null
    private var lastCameraKey = ""
    private var lastSignalsKey = ""
    private val cameras = mutableMapOf<Long, RoadCamera>()
    private val cameraCells = mutableSetOf<String>()
    private var cameraFetch: Job? = null
    private var wazeCameraFetch: Job? = null
    private var surveillanceFetch: Job? = null
    private var surveillanceWasOn = false
    private val surveillanceCells = mutableSetOf<String>()
    private val surveillance = mutableMapOf<Long, SurveillanceCamera>()
    private var railFetch: Job? = null
    private var wazeAlerts: List<WazeAlert> = emptyList()
    /** Screenshot runs only: made-up reports stay put instead of being replaced by live ones. */
    private var fakeWaze = false

    fun showDemoWaze(list: List<WazeAlert>) {
        fakeWaze = true
        wazeAlerts = list
        wazeAt = now()
        model.wazeLiveCount = list.size
        model.updateAreaRisk(list)
        lastWazeKey = ""
        render()
    }
    private var wazeBox: Box? = null
    private var wazeAt = 0L
    private var wazeFetch: Job? = null
    private var wazeFailedAt = 0L
    private var wazeAskedAt = 0L
    val heatTiles = HighwayHeat(model.scope)
    private var wazeRetryQueued = false
    private var lastWazeKey = ""
    private var googlePlaces = emptyList<Place>()
    private var shownGooglePlaces: List<Place>? = null
    private var shownTransitStops: List<Place>? = null
    private var layerOptions: List<Any>? = null
    private var railFeatures = emptyList<Feature>()
    private var transitStops = emptyList<Place>()
    private var transitStopsJob: Job? = null
    private data class ViewRequest(val center: LatLng, val at: Long)
    private var stopRequest: ViewRequest? = null
    private var shownStopPins: Pair<List<StopCandidate>, String?>? = null
    private var googlePlacesJob: Job? = null
    private var googlePlacesCenter: LatLng? = null
    private data class PlaceBatch(val places: List<Place>, val complete: Boolean)
    private val googlePlacesCache = object : LinkedHashMap<LatLng, PlaceBatch>(8, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<LatLng, PlaceBatch>?) = size > 8
    }
    private data class RailBox(val s: Double, val w: Double, val n: Double, val e: Double, val z: Int)
    private var railBox: RailBox? = null
    private var locationOn = false

    private fun now() = System.currentTimeMillis()

    fun attach(v: MapView) {
        view = v
        model.glide.cameraOutput = ::driveCamera
        model.glide.mapTouched = false
        // Pause frame-by-frame camera writes before the SDK has recognized the gesture.
        v.setOnTouchListener { _, event ->
            model.glide.mapTouched = when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> true
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> false
                else -> model.glide.mapTouched
            }
            false
        }
        v.getMapAsync { m ->
            if (view !== v) return@getMapAsync
            map = m
            model.map = m
            model.nativeCamera = { camera, duration ->
                scenery?.takeIf { it.ready }?.animateCamera(camera, duration) == true
            }
            model.visibleCamera = { scenery?.takeIf { it.ready }?.cameraPosition() ?: m.cameraPosition }
            m.uiSettings.isCompassEnabled = false
            m.uiSettings.isLogoEnabled = false
            m.uiSettings.setAttributionMargins(24, 0, 0, 24)
            m.uiSettings.isAttributionEnabled = true
            if (model.glide.followingCamera != null) model.glide.restoreFollowingCamera()
            else m.cameraPosition = CameraPosition.Builder().target(org.maplibre.android.geometry.LatLng(51.5074, -0.1278))
                .zoom(11.0).tilt(if (model.browseLook == MapLook.TILTED) 48.0 else 0.0).build()
            v.addOnDidFailLoadingMapListener {
                if (loadingStyle?.token != null) {
                    Toast.makeText(context, "Mapbox map unavailable. Using OpenFreeMap.", Toast.LENGTH_LONG).show()
                    loadBasemap(m, Basemap(STYLE_URL))
                }
            }
            if (selectedStyle == null) applyBasemap(dark, model.nav?.route?.mode == TravelMode.DRIVE,
                AppSettings.satellite, AppSettings.activeMapboxToken)
            else loadBasemap(m, checkNotNull(selectedStyle))
            m.addOnMapClickListener { tapped(m, it) }
            m.addOnMapLongClickListener { pressed(m, it); true }
            var searchMapDragged = false
            fun stopFollowing() {
                if (!model.glide.mapTouched || syncingClassic) return
                searchMapDragged = true
                model.mapNavigator?.following = false
                model.transitGuidance?.following = false
                model.stopTransitOverview()
            }
            m.addOnCameraMoveStartedListener { reason ->
                if (reason == MapLibreMap.OnCameraMoveStartedListener.REASON_API_GESTURE) stopFollowing()
            }
            // Off a route in 3D or 2D, dragging or turning the map stops following; zooming doesn't.
            m.addOnMoveListener(object : MapLibreMap.OnMoveListener {
                override fun onMoveBegin(detector: org.maplibre.android.gestures.MoveGestureDetector) {
                    stopFollowing()
                    if (model.nav == null) model.browseFollowing = false
                }
                override fun onMove(detector: org.maplibre.android.gestures.MoveGestureDetector) {}
                override fun onMoveEnd(detector: org.maplibre.android.gestures.MoveGestureDetector) {}
            })
            m.addOnRotateListener(object : MapLibreMap.OnRotateListener {
                override fun onRotateBegin(detector: org.maplibre.android.gestures.RotateGestureDetector) {
                    stopFollowing()
                    if (model.nav == null) model.browseFollowing = false
                }
                override fun onRotate(detector: org.maplibre.android.gestures.RotateGestureDetector) {}
                override fun onRotateEnd(detector: org.maplibre.android.gestures.RotateGestureDetector) {}
            })
            m.addOnScaleListener(object : MapLibreMap.OnScaleListener {
                override fun onScaleBegin(detector: org.maplibre.android.gestures.StandardScaleGestureDetector) { stopFollowing() }
                override fun onScale(detector: org.maplibre.android.gestures.StandardScaleGestureDetector) {}
                override fun onScaleEnd(detector: org.maplibre.android.gestures.StandardScaleGestureDetector) {}
            })
            m.addOnShoveListener(object : MapLibreMap.OnShoveListener {
                override fun onShoveBegin(detector: org.maplibre.android.gestures.ShoveGestureDetector) { stopFollowing() }
                override fun onShove(detector: org.maplibre.android.gestures.ShoveGestureDetector) {}
                override fun onShoveEnd(detector: org.maplibre.android.gestures.ShoveGestureDetector) {}
            })
            var lastFollowingRefresh = 0L
            m.addOnCameraIdleListener {
                if (searchMapDragged) {
                    searchMapDragged = false
                    val camera = m.cameraPosition
                    camera.target?.let { model.noteSearchArea(it.kite(), camera.zoom) }
                }
                // Camera writes during following can fire idle every frame. Layer queries and
                // network scheduling should run at a much lower rate during those updates.
                if (model.mapNavigator?.following == true) {
                    val at = android.os.SystemClock.elapsedRealtime()
                    if (at - lastFollowingRefresh < 1_400L) return@addOnCameraIdleListener
                    lastFollowingRefresh = at
                }
                loadCameras(m); loadWazeCameras(m); loadSurveillance(m); loadWaze(m); loadLiveCams(m); render(); updateHeat(m); loadRail(m); noteHeading(m)
                loadGooglePlaces(m)
                loadOutdoor(m)
            }
            m.addOnCameraMoveListener {
                if (!syncingClassic) {
                    noteHeading(m)
                    if (model.mapNavigator?.following != true || scenery?.ready != true) scenery?.syncFromKite(m.cameraPosition)
                }
            }
            WazeHistory.onChange = { render() }
            LiveCamStore.onChange = { render() }
            LocationService.last?.let { moveToUserOnce(it) }
        }
    }

    fun detach(v: MapView) {
        if (view !== v) return
        if (model.map === map) {
            model.glide.cameraOutput = null
            model.nativeCamera = null
            model.visibleCamera = null
            model.map = null
        }
        map = null
        view = null
        styleReady = false
    }

    fun refreshWaze() {
        val m = map ?: return
        loadWaze(m)
        loadWazeCameras(m)
        render()
    }

    // Style

    fun applyBasemap(dark: Boolean, driving: Boolean, satellite: Boolean, token: String?) {
        val darkChanged = this.dark != dark
        this.dark = dark
        val id = when {
            driving && dark -> "navigation-night-v1"
            driving -> "navigation-day-v1"
            dark -> "dark-v11"
            else -> "streets-v12"
        }
        val wanted = when {
            satellite -> Basemap("satellite", json = SatelliteStyle.json(mapbox = false))
            token == null -> Basemap(STYLE_URL)
            else -> Basemap("mapbox://styles/mapbox/$id", token)
        }
        if (wanted != selectedStyle) {
            selectedStyle = wanted
            map?.let { loadBasemap(it, wanted) }
        } else if (darkChanged) {
            repaint()
            render()
        }
    }

    private fun loadBasemap(m: MapLibreMap, basemap: Basemap) {
        val pending = basemap.copy()
        loadingStyle = pending
        styleReady = false
        MapLibre.getInstance(context, basemap.token, WellKnownTileServer.Mapbox)
        val builder = Style.Builder().apply {
            if (basemap.json == null) fromUri(basemap.url) else fromJson(basemap.json)
        }
        m.setStyle(builder) { style ->
            if (loadingStyle !== pending) return@setStyle
            loadingStyle = null
            showingMapbox = basemap.token != null
            styleLoaded(m, style)
        }
    }

    private fun styleLoaded(m: MapLibreMap, style: Style) {
        originalLabels.clear()
        for (l in style.layers) if (l is SymbolLayer) originalLabels[l.id] = Triple(l.textColor, l.textHaloColor, l.textHaloWidth)
        MapStyler.reset()
        MapIcons.register(style, dark)
        if (showingMapbox) addMapboxLayers(style)
        addVelaLayers(style)
        styleReady = true
        if (model.streetViewFrame != null) refreshStreetView()
        refreshProfileProbe()
        refreshIndoor()
        applyPinSizes(style)
        heatTiles.styleReloaded()
        styledDriving = null
        repaint()
        routeContext = ""
        lastRoadNameKey = ""
        transitStopsKey = ""
        vehicleKey = ""
        layerOptions = null
        policeHeatKey = null
        lastResultsKey = ""; lastRouteKey = ""; lastMineKey = ""; lastPuckKey = ""; lastHeadKey = ""; lastNextRoadKey = ""; lastCameraKey = ""; lastSignalsKey = ""; lastWazeKey = ""; lastLiveKey = ""
        enableLocation(style)
        model.glide.restoreFollowingCamera()
        shownStopPins = null
        shownMeasurement = null
        shownGooglePlaces = null
        shownTransitStops = null
        layerOptions = null
        setShape(style, "vela-rail", railFeatures)
        render()
        loadCameras(m); loadWazeCameras(m); loadWaze(m); loadLiveCams(m); updateHeat(m)
        loadGooglePlaces(m)
        loadOutdoor(m)
    }

    @SuppressLint("MissingPermission")
    private fun enableLocation(style: Style) {
        val m = map ?: return
        if (!LocationService.authorized) return
        val lc = m.locationComponent
        if (!lc.isLocationComponentActivated) {
            val opts = LocationComponentOptions.builder(context)
                .foregroundTintColor(c(0x14B8A6)).backgroundTintColor(Color.WHITE)
                .accuracyColor(c(0x14B8A6)).accuracyAlpha(0.15f)
                .bearingTintColor(c(0x14B8A6)).pulseEnabled(false).build()
            lc.activateLocationComponent(LocationComponentActivationOptions.builder(context, style)
                .locationComponentOptions(opts).useDefaultLocationEngine(false).build())
        }
        lc.isLocationComponentEnabled = model.mapNavigator == null && model.cruise == null
        lc.cameraMode = CameraMode.NONE
        lc.renderMode = RenderMode.NORMAL
        locationOn = true
        LocationService.last?.let { pushFix(it) }
    }

    /** Hands a GPS fix to the map's own blue dot. */
    fun pushFix(f: Fix) {
        scenery?.updatePosition(f)
        val m = map ?: return
        val style = m.style ?: return
        if (!locationOn) { if (LocationService.authorized) enableLocation(style); if (!locationOn) return }
        val lc = m.locationComponent
        if (!lc.isLocationComponentActivated) return
        lc.forceLocationUpdate(Location("kite").apply {
            latitude = f.lat; longitude = f.lng; accuracy = f.accuracy.toFloat(); time = f.timeMillis
            if (f.courseKnown) bearing = f.course.toFloat()
            if (f.speedKnown) speed = f.speed.toFloat()
        })
        moveToUserOnce(f)
    }

    /** Screenshot runs: the demo has put the map somewhere, so the first fix mustn't move it back. */
    fun keepCamera() { movedToUser = true }

    private fun moveToUserOnce(f: Fix) {
        val m = map ?: return
        if (movedToUser) return
        movedToUser = true
        if (model.streetView != null || model.isGuiding || model.results.isNotEmpty() || model.selected != null || model.directions != null) return
        m.moveCamera(org.maplibre.android.camera.CameraUpdateFactory.newLatLngZoom(f.coord.ml(), 15.0))
    }

    private fun repaint() {
        val style = map?.style ?: return
        if (!styleReady) return
        if (!dark) {
            for (l in style.layers) if (l is SymbolLayer) originalLabels[l.id]?.let { l.setProperties(it.first, it.second, it.third) }
        }
        if (!showingMapbox && style.getSource("kite-imagery") == null) MapStyler.apply(style, dark)
        MapIcons.swapPuck(style, dark)
        (style.getLayer("vela-rail-case") as? LineLayer)?.setProperties(lineColor(if (dark) c(0x000000, 0.9f) else c(0xFFFFFF, 0.9f)))
        val text = if (dark) c(0xE8EAED) else c(0x202124)
        val halo = if (dark) c(0x0B1526) else Color.WHITE
        for (id in listOf("kite-google-places", GOOGLE_UNREVIEWED, OpenMapStyle.POIS, TRANSIT_STOPS)) {
            (style.getLayer(id) as? SymbolLayer)?.setProperties(textColor(text), textHaloColor(halo),
                textHaloWidth(0.85f), textHaloBlur(0.55f))
        }
        for (id in listOf("vela-mine", "vela-results", "vela-selected")) {
            (style.getLayer(id) as? SymbolLayer)?.setProperties(textColor(text), textHaloColor(halo), textHaloWidth(1.5f))
        }
        lastResultsKey = ""
        lastRouteKey = ""
    }

    private fun firstSymbolLayer(style: Style): String? = style.layers.firstOrNull { it is SymbolLayer }?.id

    private fun line(id: String, src: String, color: Int, width: Float) = LineLayer(id, src).withProperties(
        lineColor(color), lineWidth(width), lineCap(Property.LINE_CAP_ROUND), lineJoin(Property.LINE_JOIN_ROUND))

    /** Icons close together join into one bubble up to zoom 13 (a whole town in view); closer in, every icon shows. */
    private fun Style.groupedSource(id: String) {
        if (getSource(id) == null) addSource(GeoJsonSource(id, FeatureCollection.fromFeatures(emptyList()),
            GeoJsonOptions().withCluster(true).withClusterRadius(44).withClusterMaxZoom(13)))
    }

    /** The numbered bubble for a group: a dark circle with a colored ring, bigger for more. */
    private fun groupBubbles(style: Style, id: String, ring: Int, from: Float = 11f) {
        val count = get("point_count")
        style.addLayer(CircleLayer("$id-bubble", id).withProperties(
            circleColor(Color.rgb(0x0F, 0x17, 0x2A)), circleOpacity(0.92f),
            circleStrokeColor(Color.rgb(ring shr 16 and 0xFF, ring shr 8 and 0xFF, ring and 0xFF)), circleStrokeWidth(3f),
            circleRadius(step(count, literal(14f), stop(10, 17f), stop(50, 21f)))).apply { minZoom = from; setFilter(has("point_count")) })
        style.addLayer(SymbolLayer("$id-count", id).withProperties(
            textField(Expression.toString(count)), textFont(overlayFont), textSize(13f),
            textColor(Color.WHITE), textAllowOverlap(true), textIgnorePlacement(true)).apply { minZoom = from; setFilter(has("point_count")) })
    }

    private fun mapboxTrafficLayers(style: Style) =
        style.layers.filterIsInstance<LineLayer>().filter { it.sourceLayer == "traffic" }

    private fun addMapboxLayers(style: Style) {
        val labels = firstSymbolLayer(style)
        val building = style.layers.filterIsInstance<FillLayer>().firstOrNull { it.sourceLayer == "building" }
        val extrusions = style.layers.filterIsInstance<FillExtrusionLayer>().filter { it.sourceLayer == "building" }
        if (!AppSettings.satellite && dark) {
            // Slate ground and lighter blue roofs make the building forms read above the roads.
            style.layers.filterIsInstance<BackgroundLayer>().forEach { it.setProperties(backgroundColor(c(0x263348))) }
            extrusions.forEach { it.setProperties(fillExtrusionColor(c(0x5B7191))) }
        }
        if (!AppSettings.satellite && building != null && extrusions.isEmpty()) {
            val extrusion = FillExtrusionLayer("kite-mapbox-buildings", building.sourceId).withSourceLayer("building")
                .withFilter(eq(get("extrude"), literal("true")))
                .withProperties(
                    fillExtrusionColor(c(if (dark) 0x5B7191 else 0xD8DFE7)),
                    fillExtrusionHeight(toNumber(get("height"))),
                    fillExtrusionBase(toNumber(get("min_height"))),
                )
            extrusion.minZoom = 15f
            if (labels == null) style.addLayer(extrusion) else style.addLayerBelow(extrusion, labels)
        }


        if (mapboxTrafficLayers(style).isEmpty()) {
            val id = "kite-mapbox-traffic"
            style.addSource(VectorSource(id, "mapbox://mapbox.mapbox-traffic-v1"))
            val traffic = LineLayer(id, id).withSourceLayer("traffic")
                .withFilter(neq(get("congestion"), literal("low")))
                .withProperties(
                    lineColor(match(get("congestion"), color(Color.TRANSPARENT),
                        stop("moderate", color(c(0xF59E0B))), stop("heavy", color(c(0xEF4444))),
                        stop("severe", color(c(0xB91C1C))))),
                    lineWidth(interpolate(linear(), zoom(), stop(8, 1.5f), stop(16, 3.5f))),
                    lineOffset(interpolate(linear(), zoom(), stop(8, 0.5f), stop(16, 2.5f))),
                    visibility(Property.NONE),
                )
            traffic.minZoom = 8f
            if (labels == null) style.addLayer(traffic) else style.addLayerBelow(traffic, labels)
        }
    }

    private fun googlePlacesEnabled() = !AppSettings.noGoogle && AppSettings.welcomed &&
        (AppSettings.googleMapPlaces || OpenMapStyle.googleNavigationActive(model))

    private var googlePlaceTerms = emptyList<String>()

    private fun showGooglePlaces(style: Style) {
        val s = model.settings
        val browsing = model.results.isEmpty() && !model.isGuiding && model.selected == null &&
            model.directions == null && model.tab == AppTab.MAP && (map?.cameraPosition?.zoom ?: 0.0) >= 14.5
        val driving = OpenMapStyle.googleNavigationActive(model) && model.stopSearch == null && !model.placingStop
        val googleVisible = when {
            !googlePlacesEnabled() -> emptyList()
            driving -> googlePlaces.filter { OpenMapStyle.groupFor(it) in s.navigationPlaceGroups }
            browsing && s.googleMapPlaces -> googlePlaces
            else -> emptyList()
        }
        val native = scenery?.ready == true
        val groups = OpenMapStyle.visibleGroups(model)
        val config = listOf(groups, s.hikingTrails, s.bikeTrails, native)
        if (layerOptions != config) {
            layerOptions = config
            for (id in STOCK_POI) visible(style, id, false)
            visible(style, OpenMapStyle.POIS, !native && groups.isNotEmpty())
            (style.getLayer(OpenMapStyle.POIS) as? SymbolLayer)?.setFilter(raw(OpenMapStyle.filter(groups)))
            visible(style, OpenMapStyle.HIKING, !native && s.hikingTrails)
            visible(style, OpenMapStyle.CYCLING, !native && s.bikeTrails)
            visible(style, OpenMapStyle.WALK_PATHS, !native && s.hikingTrails)
            visible(style, OpenMapStyle.BIKE_PATHS, !native && s.bikeTrails)
            scenery?.applyOutdoorLayers()
        }
        fun features(places: List<Place>) = places.map { place ->
            val icon = when {
                place.id.startsWith("transit:") -> "osm-transit"
                OutdoorData.kind(place.category.orEmpty()) == OutdoorData.WATER -> "osm-drinking_water"
                OutdoorData.kind(place.category.orEmpty()) == "bicycle_parking" -> "osm-bicycle_parking"
                else -> MapIcons.ambientName(place)
            }
            point(place.location, mapOf("id" to place.id, "icon" to icon, "name" to place.name,
                "category_en" to place.category, "reviewed" to (place.rating != null || (place.reviewCount ?: 0) > 0)))
        }
        if (shownGooglePlaces != googleVisible) {
            shownGooglePlaces = googleVisible
            setShape(style, "kite-google-places", features(googleVisible))
        }
        val stops = if (!model.isGuiding && s.transitLines) transitStops else emptyList()
        if (shownTransitStops != stops) {
            shownTransitStops = stops
            setShape(style, TRANSIT_STOPS, features(stops))
        }
    }

    fun refreshMarkerTheme() {
        val style = map?.style?.takeIf { styleReady } ?: return
        MapIcons.register(style, dark)
        MapIcons.registerMapPlaces(style, selectedStyle?.json != null)
    }

    fun refreshPinSizes() { map?.style?.let(::applyPinSizes) }

    private fun applyPinSizes(style: Style) {
        val waze = AppSettings.wazeMapPercent.coerceIn(60, 160) / 100f
        for (id in listOf("vela-waze", "vela-waze-group")) {
            (style.getLayer(id) as? SymbolLayer)?.setProperties(iconSize(
                interpolate(linear(), zoom(), stop(11, 0.62f * waze), stop(15, 0.95f * waze))))
        }
        val sizes = MapPinSizes.read()
        for (id in listOf("kite-google-places", GOOGLE_UNREVIEWED))
            (style.getLayer(id) as? SymbolLayer)?.setProperties(iconSize(sizes.google.toFloat()))
        (style.getLayer(OpenMapStyle.POIS) as? SymbolLayer)?.setProperties(iconSize((0.55 * sizes.osm).toFloat()))
        (style.getLayer("vela-results") as? SymbolLayer)?.setProperties(iconSize((0.72 * sizes.search).toFloat()),
            textOffset(arrayOf((1.45 * sizes.search).toFloat(), 0f)))
        (style.getLayer("kite-search-hit") as? CircleLayer)?.setProperties(circleRadius((14 * sizes.search).toFloat()))
    }

    fun seedRoadAhead(nav: Navigator) {
        val reports = wazeAlerts.takeIf { wazeAt > 0 && now() - wazeAt <= 180_000 && !fakeWaze }.orEmpty()
        nav.seedWazeReports(reports)
    }

    fun refreshGooglePlaces() {
        val m = map ?: return
        m.style?.let(::showGooglePlaces)
        loadGooglePlaces(m)
        loadOutdoor(m)
        loadRail(m)
    }

    fun openOutdoorPlace(id: String?): Boolean {
        val place = transitStops.firstOrNull { it.id == id } ?: return false
        model.select(place)
        return true
    }

    private fun loadOutdoor(m: MapLibreMap) {
        val s = model.settings
        if (model.tab != AppTab.MAP || model.nav != null || model.transitGuidance != null) return
        val camera = m.cameraPosition
        val center = camera.target?.kite() ?: return
        val time = now()
        fun due(request: ViewRequest?, distance: Double) =
            request == null || (time - request.at >= 1_200 &&
                (request.center.distanceTo(center) > distance || time - request.at >= 240_000))
        if (s.transitLines && camera.zoom >= 11.5 && transitStopsJob?.isActive != true && due(stopRequest, 850.0)) {
            val request = ViewRequest(center, time)
            stopRequest = request
            transitStopsJob = scope.launch {
                delay(300)
                val found = withContext(Dispatchers.Default) {
                    Transitous.stops(OutdoorData.bounds(center, 2200.0), grouped = true)?.sortedBy { it.at.distanceTo(center) }
                        ?.distinctBy { it.parentId ?: it.id }?.take(240)?.map {
                            Place("transit:${it.parentId ?: it.id}", it.name, it.at, "transitous", category = "Transit stop")
                        }
                }
                if (stopRequest != request) return@launch
                if (found != null) transitStops = found
                m.style?.let(::showGooglePlaces)
            }
        }
    }

    private fun loadGooglePlaces(m: MapLibreMap) {
        val driving = OpenMapStyle.googleNavigationActive(model) && model.stopSearch == null && !model.placingStop
        val browsing = !model.isGuiding && model.cruise == null && AppSettings.googleMapPlaces &&
            model.results.isEmpty() && model.selected == null && model.directions == null
        if (!googlePlacesEnabled() || m.cameraPosition.zoom < (if (driving) 13.0 else 14.0) || !(driving || browsing) || model.tab != AppTab.MAP) {
            if (googlePlacesJob?.isActive == true) {
                googlePlacesJob?.cancel()
                googlePlacesCenter = null
            }
            m.style?.let(::showGooglePlaces)
            return
        }
        val terms = if (driving) OpenMapStyle.navigationGoogleQueries() else listOf("places", "restaurants", "coffee", "shops", "gas stations")
        if (terms != googlePlaceTerms) {
            googlePlaceTerms = terms
            googlePlacesCache.clear()
            googlePlacesCenter = null
        }
        if (terms.isEmpty()) return
        val center = m.cameraPosition.target?.kite() ?: return
        val refreshDistance = if (driving) 1_200.0 else 650.0
        if (googlePlacesCenter?.distanceTo(center)?.let { it < refreshDistance } == true) {
            m.style?.let(::showGooglePlaces)
            return
        }
        googlePlacesCenter = center
        googlePlacesJob?.cancel()
        val cached = googlePlacesCache.keys.minByOrNull { it.distanceTo(center) }?.takeIf { it.distanceTo(center) < 650 }
            ?.let { googlePlacesCache[it] }
        if (cached != null && cached.complete) {
            googlePlaces = cached.places
            m.style?.let(::showGooglePlaces)
            return
        }
        googlePlaces = cached?.places ?: googlePlaces.filter { it.location.distanceTo(center) < 1_600 }
        m.style?.let(::showGooglePlaces)
        googlePlacesJob = scope.launch {
            val found = cached?.places.orEmpty().toMutableList()
            val batches = Channel<List<Place>>(terms.size)
            val limit = Semaphore(if (driving) 3 else terms.size)
            for (term in terms) {
                launch(Dispatchers.Default) {
                    val places = try {
                        limit.withPermit { GoogleClient.shared.search(term, center, if (driving) 5_500.0 else 4_000.0, pages = 1) }
                    }
                    catch (e: CancellationException) { throw e }
                    catch (_: Exception) { emptyList() }
                    batches.send(places)
                }
            }
            repeat(terms.size) {
                val places = batches.receive().filter { it.location.distanceTo(center) <= 2_200 }
                if (places.isEmpty()) return@repeat
                found += places
                val seen = withContext(Dispatchers.Default) {
                    val near = mutableListOf<Place>()
                    for (place in found.distinctBy { it.id }.sortedBy { it.location.distanceTo(center) }) {
                        if (near.none { it.matchesNearby(place) }) near += place
                        if (near.size >= 60) break
                    }
                    near
                }
                googlePlaces = seen
                googlePlacesCache[center] = PlaceBatch(seen, complete = false)
                m.style?.let(::showGooglePlaces)
            }
            if (found.isNotEmpty()) googlePlacesCache[center] = PlaceBatch(googlePlaces, complete = true)
            else googlePlacesCenter = null
        }
    }

    private fun addVelaLayers(style: Style) {
        fun grouped(id: String) = style.groupedSource(id)
        fun src(id: String, metrics: Boolean = false) {
            if (style.getSource(id) == null) style.addSource(GeoJsonSource(id, FeatureCollection.fromFeatures(emptyList()),
                GeoJsonOptions().withLineMetrics(metrics)))
        }
        MapIcons.registerMapPlaces(style, AppSettings.satellite)
        src("kite-google-places")
        fun googleMarkers(id: String, reviewed: Boolean) = SymbolLayer(id, "kite-google-places").withProperties(
            iconImage(get("icon")), iconSize(1.0f), textOptional(true), textField(get("name")), textFont(overlayFont),
            textSize(12f), textColor(c(if (dark) 0xE8EAED else 0x202124)),
            textHaloColor(if (dark) c(0x101A29) else Color.WHITE), textHaloWidth(0.85f), textHaloBlur(0.55f),
            textAnchor(Property.TEXT_ANCHOR_TOP), textOffset(arrayOf(0f, 1.0f)),
        ).also { it.minZoom = 14.5f; it.setFilter(eq(get("reviewed"), literal(reviewed))) }
        style.addLayer(googleMarkers(GOOGLE_UNREVIEWED, false))
        src(RIDE_STOPS)
        style.addLayer(CircleLayer(RIDE_STOPS, RIDE_STOPS).withProperties(
            circleRadius(5.5f), circleColor(toColor(get("color"))), circleStrokeColor(Color.WHITE), circleStrokeWidth(2f)))
        src(TRANSIT_VEHICLES)
        style.addLayer(CircleLayer(TRANSIT_VEHICLES, TRANSIT_VEHICLES).withProperties(
            circleRadius(13f), circleColor(toColor(get("color"))), circleStrokeWidth(2f), circleStrokeColor(Color.WHITE)))
        style.addLayer(SymbolLayer("$TRANSIT_VEHICLES-label", TRANSIT_VEHICLES).withProperties(
            textField(get("line")), textFont(overlayFont), textSize(11f), textColor(Color.WHITE), textAllowOverlap(true)))
        src(TRANSIT_STOPS)
        style.addLayer(SymbolLayer(TRANSIT_STOPS, TRANSIT_STOPS).withProperties(
            iconImage(get("icon")), iconSize(0.86f), textField(get("name")), textFont(overlayFont),
            textSize(11f), textOptional(true), textAnchor(Property.TEXT_ANCHOR_TOP), textOffset(arrayOf(0f, 1.0f))
        ).also { it.minZoom = 11.5f })
        val openSource = if (style.getSource("openmaptiles") != null) "openmaptiles" else OpenMapStyle.SOURCE.also {
            style.addSource(VectorSource(it, OpenMapStyle.TILEJSON))
        }
        style.addLayer(SymbolLayer(OpenMapStyle.POIS, openSource).withSourceLayer("poi").withProperties(
            iconImage(raw(OpenMapStyle.icon)), iconSize(0.73f), iconPadding(4f), textOptional(true),
            textField(step(zoom(), literal(""), stop(15, coalesce(get("name"), literal(""))))),
            textFont(overlayFont), textSize(11f), textAnchor(Property.TEXT_ANCHOR_TOP), textOffset(arrayOf(0f, 1f))
        ).also { it.minZoom = 13f })
        style.addLayer(googleMarkers("kite-google-places", true))
        for ((id, kind) in listOf(OpenMapStyle.HIKING to "hiking", OpenMapStyle.CYCLING to "cycling")) {
            style.addSource(RasterSource(id, TileSet("tiles", OpenMapStyle.trailTile(kind)).apply {
                minZoom = 6f; maxZoom = 18f; attribution = OpenMapStyle.ATTRIBUTION
            }, 256))
            val layer = RasterLayer(id, id).withProperties(rasterOpacity(0.9f), visibility(Property.NONE))
            firstSymbolLayer(style)?.let { style.addLayerBelow(layer, it) } ?: style.addLayer(layer)
        }
        for ((id, definition) in OpenMapStyle.pathLayers) {
            val (filter, tint) = definition
            val path = LineLayer(id, openSource).withSourceLayer("transportation")
                .withFilter(raw(filter)).withProperties(
                    lineColor(tint.toInt()), lineWidth(interpolate(linear(), zoom(), stop(14, 1.4f), stop(19, 3.2f))),
                    lineOpacity(0.82f), lineCap(Property.LINE_CAP_ROUND), visibility(Property.NONE),
                )
            path.minZoom = 14f
            firstSymbolLayer(style)?.let { style.addLayerBelow(path, it) } ?: style.addLayer(path)
        }
        style.addSource(RasterSource("vela-terrain", TileSet("tiles", "https://services.arcgisonline.com/ArcGIS/rest/services/Elevation/World_Hillshade/MapServer/tile/{z}/{y}/{x}")
            .apply { maxZoom = 16f; attribution = "Hillshade © Esri" }, 256))
        val hill = RasterLayer("vela-terrain", "vela-terrain").withProperties(rasterOpacity(if (dark) 0.22f else 0.32f), visibility(Property.NONE))
        style.layers.firstOrNull { it.id.startsWith("tunnel_") || it.id.startsWith("road_") || (it is LineLayer && it.sourceLayer == "road") }?.let { style.addLayerBelow(hill, it.id) } ?: style.addLayer(hill)

        // Google's live traffic tiles, the same keyless overlay Vela draws.
        val trafficURL = "https://www.google.com/maps/vt/pb=!1m4!1m3!1i{z}!2i{x}!3i{y}!2m9!1e2!2straffic!3i999999" +
            "!4m2!1sincidents!2s1!4m2!1sincidents_text!2s1!3m8!2sen!3sus!5e1105!12m4!1e68!2m2!1sset!2sRoadmap!4e0!5m1!1e0"
        style.addSource(RasterSource("vela-traffic", TileSet("tiles", trafficURL).apply { maxZoom = 16f }, 256))
        val trafficLayer = RasterLayer("vela-traffic", "vela-traffic").withProperties(rasterOpacity(0.6f), rasterFadeDuration(900f), visibility(Property.NONE))
        (style.getLayer("building-3d") ?: style.getLayer("building"))?.let { style.addLayerAbove(trafficLayer, it.id) } ?: style.addLayer(trafficLayer)

        val labels = if (showingMapbox) null else firstSymbolLayer(style)
        fun insert(l: Layer) { if (labels != null) style.addLayerBelow(l, labels) else style.addLayer(l) }
        src("vela-route-alt"); src("vela-route", metrics = true); src("vela-route-traffic")

        val altEdge = line("vela-route-alt-edge", "vela-route-alt", c(0x115E59), 11f).withProperties(lineOpacity(0.6f))
        val altFill = line("vela-route-alt", "vela-route-alt", c(0x5EEAD4), 7f).withProperties(lineOpacity(0.6f))
        // The light look: one plain teal line, no darker edge and no chevrons along it.
        val edge = line("vela-route-edge", "vela-route", c(if (showingMapbox) 0x075964 else 0x0F766E), 15f)
            .withProperties(lineOpacity(if (showingMapbox) 0.95f else 0f))
        val fill = line("vela-route-line", "vela-route", c(0x2DD4BF), 10f).withProperties(
            lineGradient(interpolate(linear(), lineProgress(), stop(0, color(c(0x2DD4BF))), stop(1, color(c(0x22D3EE))))))
        val chevrons = SymbolLayer("vela-route-chevrons", "vela-route").withProperties(
            symbolPlacement(Property.SYMBOL_PLACEMENT_LINE), symbolSpacing(70f), iconImage("route-chevron"),
            iconRotationAlignment(Property.ICON_ROTATION_ALIGNMENT_MAP), iconAllowOverlap(true), iconIgnorePlacement(true),
            iconKeepUpright(false), iconOpacity(0.55f), visibility(Property.NONE)).apply { minZoom = 13f }
        listOf(altEdge, altFill, edge, fill, chevrons).forEach { insert(it) }
        src("kite-path-section")
        listOf(line("kite-path-section-edge", "kite-path-section", Color.WHITE, 16f),
            line("kite-path-section-fill", "kite-path-section", c(0xE56C16), 10f)).forEach { insert(it) }

        src("vela-transit")
        val walk = line("vela-transit-walk", "vela-transit", c(0x5F6368), 5f).withProperties(lineDasharray(arrayOf(0.1f, 1.8f)))
        walk.setFilter(eq(get("walk"), literal(1)))
        val rideEdge = line("vela-transit-edge", "vela-transit", c(0x1A1A1A, 0.55f), 10f)
        rideEdge.setFilter(eq(get("walk"), literal(0)))
        val ride = line("vela-transit-ride", "vela-transit", c(0x1F6FEB), 7f).withProperties(lineColor(toColor(get("color"))))
        ride.setFilter(eq(get("walk"), literal(0)))
        listOf(walk, rideEdge, ride).forEach { insert(it) }
        for ((level, col) in listOf(1 to 0xF59E0BL, 2 to 0xEF4444L, 3 to 0xB91C1CL)) {
            val l = line("vela-route-traffic-$level", "vela-route-traffic", c(col), 10f)
            l.setFilter(eq(get("level"), literal(level)))
            insert(l)
        }

        src("vela-rail")
        val railCase = line("vela-rail-case", "vela-rail", if (dark) c(0x000000, 0.9f) else c(0xFFFFFF, 0.9f), 5.5f)
        val rail = line("vela-rail", "vela-rail", Color.GRAY, 3.2f).withProperties(lineColor(toColor(get("color"))))
        for (l in listOf(railCase, rail)) { l.minZoom = 10f; l.setProperties(visibility(Property.NONE)); insert(l) }

        src("kite-measure")
        style.addLayer(line("kite-measure", "kite-measure", c(0x8C61EF), 3.3f).withProperties(lineDasharray(arrayOf(2f, 1.4f))))
        style.addLayer(CircleLayer("kite-measure-points", "kite-measure").withFilter(eq(geometryType(), literal("Point")))
            .withProperties(circleColor(c(0x8C61EF)), circleRadius(5f), circleStrokeColor(Color.WHITE), circleStrokeWidth(2f)))

        src("vela-signals")
        style.addLayer(SymbolLayer("vela-signals", "vela-signals").withProperties(
            iconImage(get("icon")), iconAllowOverlap(true), iconAnchor(Property.ICON_ANCHOR_BOTTOM),
            iconSize(interpolate(linear(), zoom(), stop(14, 1.05f), stop(17, 1.25f)))).apply { minZoom = 14f })

        // Live camera photos, under the speed cameras: Windy webcams from zoom 6 (a region), road
        // cameras from zoom 9 (a city). Zoomed out over a busy city (central London) they join into
        // numbered blue bubbles, like the speed cameras (Matteo, 2026-11-13).
        grouped("vela-livecams")
        style.addLayer(SymbolLayer("vela-livecams", "vela-livecams").withProperties(
            iconImage(get("icon")), iconAllowOverlap(false), iconPadding(2f),
            iconSize(interpolate(linear(), zoom(), stop(6, 0.6f), stop(9, 0.7f), stop(13, 0.9f), stop(16, 1.05f))))
            .apply { minZoom = LiveCams.WEBCAM_MIN_ZOOM.toFloat(); setFilter(not(has("point_count"))) })
        groupBubbles(style, "vela-livecams", 0x3B82F6, LiveCams.WEBCAM_MIN_ZOOM.toFloat())

        // Zoomed out over a busy city, cameras close together join into one bubble with a number.
        grouped("vela-cameras")
        val big = eq(get("big"), literal(1))
        style.addLayer(SymbolLayer("vela-cameras", "vela-cameras").withProperties(
            iconImage(get("icon")), iconAllowOverlap(true),
            iconSize(interpolate(linear(), zoom(),
                stop(11, switchCase(big, literal(1.0), literal(0.7))),
                stop(14, switchCase(big, literal(1.33), literal(0.92))),
                stop(17, switchCase(big, literal(1.65), literal(1.15))))),
            // While driving, cameras off your route fade back (see renderCameras).
            iconOpacity(coalesce(get("op"), literal(1.0)))).apply { minZoom = 11f; setFilter(not(has("point_count"))) })
        groupBubbles(style, "vela-cameras", 0xFF8A00)

        src("vela-waze-heat")
        val heat = HeatmapLayer("vela-waze-heat", "vela-waze-heat").withProperties(
            visibility(Property.NONE), heatmapRadius(interpolate(linear(), zoom(), stop(5, 13f), stop(13, 32f), stop(17, 42f))),
            heatmapIntensity(1.3f), heatmapOpacity(0.7f),
            heatmapColor(interpolate(linear(), heatmapDensity(), stop(0, rgba(66, 98, 240, 0f)),
                stop(0.2, rgb(83, 116, 244)), stop(0.55, rgb(146, 89, 236)), stop(1, rgb(239, 118, 217)))))
            .apply { minZoom = 5f }
        style.getLayer("vela-route-alt-edge")?.let { style.addLayerBelow(heat, "vela-route-alt-edge") } ?: insert(heat)
        src("vela-waze")
        style.addLayer(SymbolLayer("vela-waze", "vela-waze").withProperties(
            iconImage(get("icon")), iconAllowOverlap(true),
            iconSize(interpolate(linear(), zoom(), stop(11, 0.62f), stop(15, 0.95f))),
            iconOpacity(get("op"))).apply { minZoom = 11f })
        // Every other report (closures, hazards, jams) joins into numbered bubbles when zoomed
        // out, so a busy city stays readable. Police and crashes above always stay on their own.
        grouped("vela-waze-group")
        style.addLayerBelow(SymbolLayer("vela-waze-group", "vela-waze-group").withProperties(
            iconImage(get("icon")), iconAllowOverlap(true),
            iconSize(interpolate(linear(), zoom(), stop(11, 0.62f), stop(15, 0.95f))),
            iconOpacity(get("op"))).apply { minZoom = 11f; setFilter(not(has("point_count"))) }, "vela-waze")
        groupBubbles(style, "vela-waze-group", 0xEF4444)

        src("vela-mine")
        style.addLayer(SymbolLayer("vela-mine", "vela-mine").withProperties(
            iconImage(get("icon")), iconAllowOverlap(true), textField(get("label")), textFont(overlayFont),
            textSize(11f), textAnchor(Property.TEXT_ANCHOR_TOP), textOffset(arrayOf(0f, 1.1f)), textOptional(true),
            textMaxWidth(8f)).apply { minZoom = 9f })

        src("vela-results")
        style.addLayer(CircleLayer("kite-search-hit", "vela-results").withProperties(circleRadius(14f),
            circleColor(c(0x164B9F, 0.12f))))
        style.addLayer(SymbolLayer("vela-results", "vela-results").withProperties(
            iconImage(get("icon")), iconSize(0.72f), iconAllowOverlap(true), textField(get("label")), textFont(overlayFont),
            textSize(12.5f), textAnchor(Property.TEXT_ANCHOR_LEFT), textOffset(arrayOf(1.45f, 0f)), textOptional(true),
            textMaxWidth(8f), textJustify(Property.TEXT_JUSTIFY_LEFT), symbolSortKey(get("rank"))))

        src(StopSearch.PINS)
        style.addLayer(CircleLayer(StopSearch.PINS, StopSearch.PINS).withProperties(
            circleColor(switchCase(eq(get("selected"), literal(true)), rgb(185, 56, 74), rgb(17, 93, 101))),
            circleStrokeColor(Color.WHITE), circleStrokeWidth(2f), circleRadius(12f),
            circleSortKey(switchCase(eq(get("selected"), literal(true)), literal(1), literal(0)))))
        style.addLayer(SymbolLayer("kite-stop-numbers", StopSearch.PINS).withProperties(
            textField(toString(get("rank"))), textFont(overlayFont), textSize(12f), textColor(Color.WHITE),
            textAllowOverlap(true), textIgnorePlacement(true)))

        src(INDOOR)
        style.addLayer(FillLayer("$INDOOR-fill", INDOOR).withProperties(
            fillColor(0xFFE0DFEC.toInt()), fillOpacity(0.92f), fillOutlineColor(0xFF665886.toInt())))
        style.addLayer(LineLayer("$INDOOR-lines", INDOOR).withFilter(eq(get("role"), literal("area"))).withProperties(
            lineColor(0xFF706384.toInt()), lineWidth(1.6f)))
        style.addLayer(SymbolLayer("$INDOOR-labels", INDOOR).withFilter(eq(get("role"), literal("label"))).withProperties(
            textField(get("label")), textFont(overlayFont), textSize(12f), textColor(0xFF352746.toInt()), textHaloColor(Color.WHITE), textHaloWidth(1.3f)))
        src(PROFILE_PROBE)
        style.addLayer(CircleLayer(PROFILE_PROBE, PROFILE_PROBE).withProperties(
            circleRadius(8f), circleColor(0xFF7C3AED.toInt()), circleStrokeColor(Color.WHITE), circleStrokeWidth(3f)))
        src(STREET_VIEW)
        style.addLayer(FillLayer("$STREET_VIEW-cone", STREET_VIEW).withProperties(
            fillColor(c(0x0EA5A4)), fillOpacity(0.35f), fillOutlineColor(c(0x15807C))))
        style.addLayer(CircleLayer("$STREET_VIEW-walk", STREET_VIEW).withFilter(eq(get("role"), literal("link"))).withProperties(
            circleRadius(5f), circleColor(c(0x0EA5A4)), circleStrokeColor(Color.WHITE), circleStrokeWidth(1.7f)))
        style.addLayer(CircleLayer("$STREET_VIEW-position", STREET_VIEW).withFilter(eq(get("role"), literal("position"))).withProperties(
            circleRadius(8f), circleColor(c(0x127A79)), circleStrokeColor(Color.WHITE), circleStrokeWidth(2.4f)))
        src("vela-selected")
        style.addLayer(SymbolLayer("vela-selected", "vela-selected").withProperties(
            iconImage(get("icon")), iconAnchor(get("anchor")), iconAllowOverlap(true), textAllowOverlap(false),
            textField(get("label")), textFont(overlayFont), textSize(13f), textAnchor(Property.TEXT_ANCHOR_TOP),
            textOffset(arrayOf(0f, 0.4f)), textOptional(true)))

        src("vela-route-bubbles")
        for (selected in listOf(false, true)) {
            val b = SymbolLayer("vela-route-bubble-${if (selected) 1 else 0}", "vela-route-bubbles").withProperties(
                iconImage(if (selected) "bubble-sel" else "bubble-alt"), iconTextFit(Property.ICON_TEXT_FIT_BOTH),
                iconTextFitPadding(arrayOf(6f, 12f, 6f, 12f)), textField(get("label")), textFont(overlayFont),
                textSize(15f), textColor(if (selected) Color.WHITE else c(0x202124)), iconAllowOverlap(true), textAllowOverlap(true))
            b.setFilter(eq(get("sel"), literal(if (selected) 1 else 0)))
            style.addLayer(b)
        }

        src("vela-turn-arrow")
        val shaft = eq(get("part"), literal("shaft"))
        val arrowShadow = line("vela-turn-arrow-shadow", "vela-turn-arrow", Color.BLACK, 22f).withProperties(
            lineOpacity(0.35f), lineBlur(4f), lineTranslate(arrayOf(0f, 2f)))
        arrowShadow.setFilter(shaft)
        // A big white arrow with a teal edge, like Waze's, so it's clear at a glance.
        val arrowEdge = line("vela-turn-arrow-edge", "vela-turn-arrow", c(0x0F766E), 23f); arrowEdge.setFilter(shaft)
        val arrowLine = line("vela-turn-arrow", "vela-turn-arrow", Color.WHITE, 15f); arrowLine.setFilter(shaft)
        // The head has a source of its own, updated only when the turn changes: the map fades a symbol
        // in afresh each time its source changes, which would keep the head see-through.
        src("vela-turn-head")
        val head = SymbolLayer("vela-turn-arrow-head", "vela-turn-head").withProperties(
            iconImage("turn-head"), iconRotate(get("bearing")), iconRotationAlignment(Property.ICON_ROTATION_ALIGNMENT_MAP),
            iconAllowOverlap(true), iconIgnorePlacement(true))
        listOf(arrowShadow, arrowEdge, arrowLine, head).forEach { style.addLayer(it) }

        // The name of the road you're about to turn onto, lit up in a teal pill on the road itself.
        // Its own source, updated only when the turn changes, like the head.
        src("vela-next-road")
        style.addLayer(SymbolLayer("vela-next-road", "vela-next-road").withProperties(
            iconImage("road-pill"), iconTextFit(Property.ICON_TEXT_FIT_BOTH), iconTextFitPadding(arrayOf(5f, 11f, 5f, 11f)),
            textField(get("label")), textFont(overlayFont), textSize(16f), textColor(c(0x06201C)),
            textPitchAlignment(Property.TEXT_PITCH_ALIGNMENT_VIEWPORT), iconAllowOverlap(true), textAllowOverlap(true)))

        // The road you're on, written on the road just ahead of the car like a painted marking
        // (Matteo's pick over a box on the screen). Lies flat and follows the road's bends.
        // The map's own named roads, drawn too faintly to see: read back in the driving view with no
        // route, so the name follows the road you're on round its bends.
        if (style.getSource("openmaptiles") != null) {
            style.addLayer(LineLayer("vela-road-query", "openmaptiles").apply {
                sourceLayer = "transportation_name"
                // Not quite 0: a layer that draws nothing at all can't be asked what's under it.
                setProperties(lineOpacity(0.01f), lineWidth(3f))
            })
        }
        src("vela-road-name")
        style.addLayer(SymbolLayer("vela-road-name", "vela-road-name").withProperties(
            textField(get("label")), symbolPlacement(Property.SYMBOL_PLACEMENT_LINE_CENTER),
            textPitchAlignment(Property.TEXT_PITCH_ALIGNMENT_MAP), textRotationAlignment(Property.TEXT_ROTATION_ALIGNMENT_MAP),
            textKeepUpright(true), textFont(arrayOf("Noto Sans Bold")),
            textSize(interpolate(linear(), zoom(), stop(13, 15f), stop(15, 18f), stop(17, 22f), stop(18, 26f))),
            textLetterSpacing(0.08f), textTransform(Property.TEXT_TRANSFORM_UPPERCASE), textColor(c(0x0E3B36)),
            textHaloColor("rgba(255,255,255,0.95)"), textHaloWidth(2f), textAllowOverlap(true), textIgnorePlacement(true)))

        src(NavGlide.PUCK)
        style.addLayer(SymbolLayer(NavGlide.PUCK, NavGlide.PUCK).withProperties(
            iconImage(coalesce(get("icon"), literal("puck"))), iconRotate(get("bearing")), iconRotationAlignment(Property.ICON_ROTATION_ALIGNMENT_MAP),
            iconPitchAlignment(Property.ICON_PITCH_ALIGNMENT_MAP), iconAllowOverlap(true), iconIgnorePlacement(false)))
    }

    // Render

    /** The road a turn goes onto, for the pill on the map: "Stoneham Way" from "Turn left onto Stoneham Way". */
    private fun nextRoadName(m: Maneuver): String? {
        val text = SpokenText.forScreen(m.instruction)
        val at = text.lastIndexOf(" onto ")
        val road = m.road
        val name = when {
            at >= 0 -> text.substring(at + 6)
            !road.isNullOrEmpty() && text.contains(road) -> SpokenText.forScreen(road)
            else -> null
        }?.trim()?.trimEnd('.')?.trim()
        return name?.takeIf { it.isNotEmpty() && it.length <= 40 }
    }

    private fun setShape(style: Style?, id: String, features: List<Feature>) {
        val collection = FeatureCollection.fromFeatures(features)
        val native = scenery
        if (native?.ready != true || !native.renders(id) || id in classicHitSources)
            (style?.getSource(id) as? GeoJsonSource)?.setGeoJson(collection)
        native?.updateOverlay(id) { collection.toJson() }
    }

    private fun point(p: LatLng, props: Map<String, Any?> = emptyMap()) = Feature.fromGeometry(Point.fromLngLat(p.lng, p.lat)).also { f ->
        props.forEach { (k, v) -> when (v) {
            is String -> f.addStringProperty(k, v)
            is Number -> f.addNumberProperty(k, v)
            is Boolean -> f.addBooleanProperty(k, v)
        } }
    }

    fun polyline(pts: List<LatLng>, props: Map<String, Any?> = emptyMap()) =
        Feature.fromGeometry(LineString.fromLngLats(pts.map { Point.fromLngLat(it.lng, it.lat) })).also { f ->
            props.forEach { (k, v) -> when (v) { is String -> f.addStringProperty(k, v); is Number -> f.addNumberProperty(k, v) } }
        }

    private fun visible(style: Style, id: String, on: Boolean) {
        val layer = style.getLayer(id) ?: return
        val value = if (on) Property.VISIBLE else Property.NONE
        if (layer.visibility.value != value) layer.setProperties(visibility(value))
    }

    private var renderPosted = false
    fun render() {
        val target = view ?: return
        if (renderPosted) return
        renderPosted = true
        target.postOnAnimation {
            renderPosted = false
            if (target === view) renderNow()
        }
    }

    private fun renderNow() {
        val m = map ?: return
        val style = if (styleReady) m.style else null
        if (style == null) {
            if (scenery?.ready == true) {
                renderResults(null)
                renderStopPins(null)
                renderRoutes(null)
                renderSignals(null)
                renderRoadName(null)
            }
            return
        }
        val s = model.settings
        val navigating = model.isGuiding
        val showPosition = model.mapNavigator == null && model.cruise == null
        val driving = model.nav?.route?.mode == TravelMode.DRIVE || model.cruise != null
        if (m.locationComponent.isLocationComponentActivated) {
            if (m.locationComponent.isLocationComponentEnabled != showPosition) m.locationComponent.isLocationComponentEnabled = showPosition
        } else if (LocationService.authorized) enableLocation(style)
        // Not before the welcome screen's choice: "Open data only" means nothing ever went to Google.
        visible(style, "vela-traffic", !showingMapbox && s.traffic && !navigating && !s.noGoogle && s.welcomed)
        if (showingMapbox) {
            mapboxTrafficLayers(style).forEach { visible(style, it.id, s.traffic && !navigating) }
        }
        // The Surveillance layer just switched on: fetch it now, not at the next pan (only on the
        // switch, so a failed fetch keeps its 30-second pause).
        if (s.surveillanceCameras && !surveillanceWasOn) loadSurveillance(m)
        surveillanceWasOn = s.surveillanceCameras
        visible(style, "vela-terrain", s.terrain && !s.satellite)
        for (id in listOf("vela-rail", "vela-rail-case")) visible(style, id, s.transitLines && !navigating)
        if (styledDriving != driving) {
            if (!showingMapbox) MapStyler.drive(style, driving)
            styledDriving = driving
            (style.getLayer("vela-route-line") as? LineLayer)?.setProperties(lineWidth(if (navigating) 12f else 10f))
            (style.getLayer("vela-route-edge") as? LineLayer)?.setProperties(lineWidth(if (navigating) 17f else 15f))
            visible(style, "vela-route-chevrons", showingMapbox && navigating)
        }
        if (!showingMapbox) for (id in listOf("building", "building-3d")) visible(style, id, !s.satellite && !driving)
        renderResults(style)
        renderStopPins(style)
        renderMeasure(style)
        renderRoutes(style)
        renderPuck(style)
        renderCameras(style)
        renderLiveCams(m, style)
        renderSignals(style)
        renderRoadName(style)
        renderWaze(style)
        updateHeat(m)
        renderMine(style)
        showGooglePlaces(style)
        if (s.transitLines) loadRail(m)
    }

    /**
     * The road's name on the road ahead: 40 to 220 m along the route while navigating (left off
     * when the next turn is close, where the turn arrow and the new road's name need the room),
     * or straight ahead along your heading in the driving view with no route.
     */
    private var cruiseRoadAt = 0L
    private fun renderRoadName(style: Style?) {
        var line: List<LatLng> = emptyList()
        var name: String? = null
        val n = model.nav
        val c = model.cruise
        if (n != null) {
            val p = n.progress
            val road = n.currentRoad
            val next = n.nextManeuver
            if (n.following && !n.arrived && p != null && road != null &&
                (next == null || next.alongMeters - p.alongMeters > 260 || next.type == ManeuverType.STRAIGHT)) {
                val cum = if (routeGeometry === n.route.polyline) routeDistances else Geo.cumulative(n.route.polyline)
                val total = cum.last()
                val a = p.alongMeters + 40; val b = minOf(p.alongMeters + 220, total)
                if (b - a > 80) { line = Geo.slice(n.route.polyline, a, b, cum); name = road }
            }
        } else if (c != null && model.browseFollowing) {
            val time = android.os.SystemClock.elapsedRealtime()
            if (time - cruiseRoadAt < 1_300L) return
            cruiseRoadAt = time
            val f = c.fix
            val road = c.road ?: c.ref
            val m = map
            if (f != null && f.courseKnown && f.speed > 2 && road != null && m != null) {
                // Along the map's own line for the road you're on, so it stays on the road round a bend;
                // nothing when the map doesn't have it here (never floating off over a field).
                val pt = m.projection.toScreenLocation(org.maplibre.android.geometry.LatLng(f.lat, f.lng))
                val density = context.resources.displayMetrics.density
                val box = RectF(pt.x - 300 * density, pt.y - 450 * density, pt.x + 300 * density, pt.y + 250 * density)
                val match = any(eq(get("name"), c.road ?: ""), eq(get("ref"), c.ref ?: ""))
                val lines = mutableListOf<List<LatLng>>()
                for (feat in m.queryRenderedFeatures(box, match, "vela-road-query")) {
                    when (val g = feat.geometry()) {
                        is LineString -> lines.add(g.coordinates().map { LatLng(it.latitude(), it.longitude()) })
                        is org.maplibre.geojson.MultiLineString -> g.coordinates().forEach { l -> lines.add(l.map { LatLng(it.latitude(), it.longitude()) }) }
                    }
                }
                RoadAhead.path(lines, f.coord, f.course)?.let { line = it; name = road }
            }
        }
        val key = (name ?: "") + (line.firstOrNull()?.let { "${(it.lat * 20_000).toInt()},${(it.lng * 20_000).toInt()}" } ?: "")
        if (key == lastRoadNameKey) return
        lastRoadNameKey = key
        setShape(style, "vela-road-name", if (name != null && line.size >= 2) listOf(polyline(line, mapOf("label" to name))) else emptyList())
    }

    private fun renderMine(style: Style) {
        val s = model.settings
        val hidden = model.isGuiding || model.directions != null
        val items = mutableListOf<Triple<Place, String, String>>()
        if (!hidden) {
            s.home?.let { items.add(Triple(it, "mine-home", "Home")) }
            s.work?.let { items.add(Triple(it, "mine-work", "Work")) }
            s.parking?.let { items.add(Triple(it, "mine-parking", "Parked car")) }
            for (p in s.saved.take(200)) if (items.none { it.first.id == p.id }) items.add(Triple(p, "mine-saved", p.name))
        }
        val selected = model.selected
        // The label too, so a renamed place shows its new name.
        val key = items.joinToString(",") { it.first.id + it.second + it.third } + "|" + (selected?.id ?: "")
        if (key == lastMineKey) return
        lastMineKey = key
        setShape(style, "vela-mine", items.filter { selected == null || !it.first.matchesNearby(selected) }.map { (p, icon, label) ->
            point(p.location, mapOf("id" to p.id, "icon" to icon, "label" to label))
        })
    }

    private fun renderCameras(style: Style) {
        val s = model.settings
        val line = model.nav?.route?.polyline ?: model.directions?.route?.polyline ?: emptyList()
        val waze = s.speedCameras && s.wazeOn
        // While driving, only what's on your way stands out: everything off the route fades back.
        val driving = model.nav?.route?.mode == TravelMode.DRIVE
        val onRouteCameras = model.nav?.routeCameras.orEmpty()
        val key = "${s.speedCameras}${s.plateCameras}${s.aheadCameras}${onRouteCameras.hashCode()}${s.surveillanceCameras}${surveillance.size}${cameras.size}${line.size}${line.firstOrNull()?.lat ?: 0}$waze${WazeCameras.shared.version}$driving"
        if (key == lastCameraKey) return
        lastCameraKey = key
        val mapped = (cameras.values + onRouteCameras.map { it.camera }).distinctBy { it.id }
            .filter { if (it.kind == RoadCamera.Kind.SPEED) s.speedCameras else s.plateCameras }
        // Waze's speed cameras join OpenStreetMap's; one both maps hold shows once.
        val shown = if (waze) WazeCameras.merge(mapped, WazeCameras.shared.known()) else mapped
        val routeIds = onRouteCameras.mapTo(HashSet()) { it.camera.id }
        val previewDistances = if (!driving && line.size >= 2) Geo.cumulative(line) else null
        val features = shown.mapNotNull { cam ->
            val onRoute = cam.id in routeIds ||
                (previewDistances != null && Geo.project(cam.location, line, previewDistances).offset < 40)
            if (driving && !s.aheadCameras && onRoute) return@mapNotNull null
            point(cam.location, mapOf("icon" to if (cam.kind == RoadCamera.Kind.SPEED) "cam-speed" else "cam-plate",
                "big" to if (onRoute) 1 else 0, "op" to if (driving && !onRoute) OFF_ROUTE_OPACITY else 1.0,
                "surveillanceId" to if (cam.kind == RoadCamera.Kind.PLATE) cam.id.toString() else ""))
        }.toMutableList()
        if (s.surveillanceCameras) {
            for (camera in surveillance.values) {
                if (camera.isALPR && s.plateCameras && cameras[camera.id] != null) continue
                features.add(point(camera.location, mapOf("icon" to if (camera.isALPR) "cam-plate" else "cam-surveillance", "big" to 0,
                    "op" to if (driving) OFF_ROUTE_OPACITY else 1.0, "surveillanceId" to camera.id.toString())))
            }
        }
        setShape(style, "vela-cameras", features)
    }

    private fun renderSignals(style: Style?) {
        val nav = model.mapNavigator
        val from = nav?.progress?.alongMeters ?: 0.0
        val walking = nav?.route?.mode == TravelMode.WALK
        val range = if (walking) 650 else 5000
        val controls = nav?.roadControls.orEmpty().filter {
            (nav?.progress?.offsetMeters ?: 0.0) <= 120 && model.settings.showsControl(it.kind) &&
                it.along in (from - 12)..(from + range) && (walking || it.kind != Overpass.ControlKind.CROSSING)
        }
        val key = "${nav?.route?.id}|${controls.hashCode()}"
        if (key == lastSignalsKey) return
        lastSignalsKey = key
        val line = nav?.route?.polyline.orEmpty()
        val cum = Geo.cumulative(line)
        val points = controls.map { it.kind to (it.at ?: Geo.point(line, it.along, cum)) }
        setShape(style, "vela-signals", points.map { (kind, at) ->
            val icon = when (kind) {
                Overpass.ControlKind.SIGNAL -> "traffic-light"
                Overpass.ControlKind.STOP -> "road-stop"
                Overpass.ControlKind.RAIL -> "road-crossing"
                Overpass.ControlKind.CROSSING -> "pedestrian-crossing"
            }
            point(at, mapOf("icon" to icon))
        })
    }

    private fun renderWaze(style: Style) {
        val s = model.settings
        val history = WazeHistory.all
        val kinds = (if (model.nav == null) s.wazeKinds else s.roadWazeKinds).map { it.key }.sorted().joinToString("")
        val live = model.nav?.routeWaze.orEmpty().map { it.alert } + model.nav?.liveAlerts.orEmpty() + model.routeReports.takeIf { model.directions != null }.orEmpty()
        // While driving, reports off your route fade back so the ones you'll meet stand out.
        val route = if (model.nav?.route?.mode == TravelMode.DRIVE) model.nav?.route?.polyline ?: emptyList() else emptyList()
        val key = "${s.wazeOn}${s.wazeOnMap}${s.aheadWaze}${s.wazeHeatmap}${s.wazeMaxAge}$kinds$wazeAt${history.size}${live.joinToString("") { it.id }}${model.nav?.routeWaze?.hashCode()}${route.size}${route.firstOrNull()?.lat ?: 0}"
        if (key == lastWazeKey) return
        lastWazeKey = key
        val ids = wazeAlerts.map { it.id }.toSet()
        val all = (wazeAlerts + live.filter { !ids.contains(it.id) }).distinctBy { it.id }
        val shown = if (!s.wazeOnMap) emptyList()
            else if (model.nav != null) all.filter(s::showsOnRoad) else all.filter(s::shows)
        val alertsOnRoute = model.nav?.routeWaze.orEmpty().mapTo(HashSet()) { it.alert.id }
        fun feature(a: WazeAlert): Feature {
            val age = (now() - a.reportedAtMillis) / 1000.0
            var op = max(0.5, 1 - age / 14_400)
            if (route.isNotEmpty() && a.id !in alertsOnRoute) op = OFF_ROUTE_OPACITY
            return point(a.location, mapOf("id" to a.id, "icon" to "waze-${a.kind.key}", "op" to op))
        }
        // Police and crashes matter most, so they never get grouped into a bubble.
        val (alone, grouped) = shown.partition { it.kind in NEVER_GROUPED }
        setShape(style, "vela-waze", alone.map(::feature))
        setShape(style, "vela-waze-group", grouped.map(::feature))
    }

    /** Local Waze report density, plus Highway Radar's coverage on the classic map. */
    private var policeHeatKey: Pair<Boolean, List<WazeHistory.Sighting>>? = null
    fun updateHeat(m: MapLibreMap) {
        val s = model.settings
        val enabled = styleReady && s.wazeOn && s.wazeHeatmap && s.wazePolice
        if (scenery?.ready != true) heatTiles.update(m, enabled, "vela-waze-heat")
        val history = if (enabled) WazeHistory.all else emptyList()
        val key = enabled to history
        if (policeHeatKey == key) return
        policeHeatKey = key
        m.style?.let {
            visible(it, "vela-waze-heat", enabled && scenery?.ready != true)
            setShape(it, "vela-waze-heat", history.takeLast(2500).map { p -> point(LatLng(p.lat, p.lng)) })
        }
    }

    /** Live Waze reports for the view and a margin, asked again after two minutes or when the map leaves the box. */
    fun loadWaze(m: MapLibreMap) {
        val s = model.settings
        if (s.wazeOn && (s.wazeHeatmap || s.policeRisk)) {
            // Only around where you are: Waze is never asked about saved Home and Work.
            val places = listOfNotNull(LocationService.last?.coord)
            WazeHistory.sweepIfDue(places, scope)
        }
        if (fakeWaze || !s.wazeOn || !(s.wazeOnMap || s.wazeHeatmap) || m.cameraPosition.zoom < 10 || wazeFetch != null || now() - wazeFailedAt <= 60_000) return
        val waitMs = (if (model.nav != null) 90_000 else 5_000) - (now() - wazeAskedAt)
        if (waitMs > 0) {
            if (!wazeRetryQueued) {
                wazeRetryQueued = true
                scope.launch { delay(waitMs + 100); wazeRetryQueued = false; loadWaze(m) }
            }
            return
        }
        val b = m.projection.visibleRegion.latLngBounds
        wazeBox?.let { r ->
            if (b.latitudeSouth >= r.s && b.longitudeWest >= r.w && b.latitudeNorth <= r.n && b.longitudeEast <= r.e && now() - wazeAt < 120_000) return
        }
        val dLat = (b.latitudeNorth - b.latitudeSouth) * 0.3; val dLng = (b.longitudeEast - b.longitudeWest) * 0.3
        val box = Box(b.latitudeSouth - dLat, b.longitudeWest - dLng, b.latitudeNorth + dLat, b.longitudeEast + dLng)
        if (box.n - box.s >= 1.5 || box.e - box.w >= 2.5) return
        val mid = LatLng((b.latitudeNorth + b.latitudeSouth) / 2, (b.longitudeEast + b.longitudeWest) / 2)
        val hLat = min((box.n - box.s) / 2, 0.15); val hLng = min((box.e - box.w) / 2, 0.25)
        val liveBox = Box(mid.lat - hLat, mid.lng - hLng, mid.lat + hLat, mid.lng + hLng)
        val askLive = model.nav == null
        wazeAskedAt = now()
        wazeFetch = scope.launch {
            val closures = async { runCatching { Waze.alerts(box.s, box.w, box.n, box.e) }.getOrNull() }
            val live = if (askLive) runCatching { WazeLive.shared.alerts(listOf(liveBox), mid) }.getOrNull() else null
            val fromMap = closures.await()
            wazeFetch = null
            if (fakeWaze) return@launch
            if (fromMap == null && live == null) { Log.i("KiteTrace", "waze browse: both failed (Waze: ${Waze.lastStatus?.summary ?: "no answer"}; ${WazeWeb.note})"); wazeFailedAt = now(); return@launch }
            val merged = linkedMapOf<String, WazeAlert>()
            for (a in (fromMap ?: emptyList()) + (live ?: emptyList())) merged[a.id] = a
            val found = merged.values.toList()
            Log.i("KiteTrace", "waze browse: live map ${fromMap?.size ?: "failed"}, drivers' reports ${if (askLive) live?.size ?: "failed" else "not asked"}" +
                if (fromMap == null) " (Waze: ${Waze.lastStatus?.summary ?: "no answer"}; ${WazeWeb.note})" else "")
            wazeAlerts = found
            wazeBox = if (live != null) liveBox else box
            wazeAt = now()
            WazeHistory.record(found)
            model.wazeLiveCount = found.count { model.settings.shows(it) }
            model.updateAreaRisk(found)
            render()
        }
    }

    /** Transit lines for the view and a margin around it, when the layer is on. */
    fun loadRail(m: MapLibreMap) {
        if (!model.settings.transitLines || m.cameraPosition.zoom < 10 || railFetch != null || model.isGuiding) return
        val b = m.projection.visibleRegion.latLngBounds
        val z = m.cameraPosition.zoom.toInt()
        railBox?.let { r -> if (b.latitudeSouth >= r.s && b.longitudeWest >= r.w && b.latitudeNorth <= r.n && b.longitudeEast <= r.e && abs(z - r.z) <= 2) return }
        val dLat = (b.latitudeNorth - b.latitudeSouth) * 0.5; val dLng = (b.longitudeEast - b.longitudeWest) * 0.5
        val box = RailBox(b.latitudeSouth - dLat, b.longitudeWest - dLng, b.latitudeNorth + dLat, b.longitudeEast + dLng, z)
        railFetch = scope.launch {
            val lines = withContext(Dispatchers.Default) { Transitous.lines(box.s, box.w, box.n, box.e, min(z, 14)) }
            Log.i("KiteTrace", "transit lines: ${lines?.size ?: "failed"} at zoom $z (${Transitous.linesNote})")
            railFetch = null
            if (lines != null) {
                railBox = box
                railFeatures = withContext(Dispatchers.Default) {
                    lines.take(360).map { l -> polyline(Overpass.thinTo(l.points, 260), mapOf("color" to hex(l.color))) }
                }
                m.style?.let { setShape(it, "vela-rail", railFeatures) }
            }
        }
    }

    private fun cells(m: MapLibreMap, done: Set<String>): List<Pair<Int, Int>>? {
        val b = m.projection.visibleRegion.latLngBounds; val cell = 0.1
        val y0 = floor(b.latitudeSouth / cell).toInt(); val y1 = floor(b.latitudeNorth / cell).toInt()
        val x0 = floor(b.longitudeWest / cell).toInt(); val x1 = floor(b.longitudeEast / cell).toInt()
        if (y1 < y0 || x1 < x0 || (y1 - y0 + 1) * (x1 - x0 + 1) > 12) return null
        val missing = mutableListOf<Pair<Int, Int>>()
        for (y in y0..y1) for (x in x0..x1) if (!done.contains("$y,$x")) missing.add(y to x)
        return missing.ifEmpty { null }
    }

    /** Separate OSM surveillance layer, opt-in; bounded to the same cells as camera lookups. */
    fun loadSurveillance(m: MapLibreMap) {
        if (!model.settings.surveillanceCameras || m.cameraPosition.zoom < 12 || surveillanceFetch != null) return
        val missing = cells(m, surveillanceCells) ?: return
        val ys = missing.map { it.first }; val xs = missing.map { it.second }; val cell = 0.1
        surveillanceFetch = scope.launch {
            val found = runCatching { SurveillanceCameras.inBox(ys.min() * cell, xs.min() * cell, (ys.max() + 1) * cell, (xs.max() + 1) * cell) }.getOrNull()
            surveillanceFetch = null
            if (found == null) { delay(30_000); loadSurveillance(m); return@launch }
            missing.forEach { surveillanceCells.add("${it.first},${it.second}") }
            found.forEach { surveillance[it.id] = it }
            render(); loadSurveillance(m)
        }
    }

    /** Ask Overpass for the cameras in view, a few 0.1° cells at a time, each cell once. */
    fun loadCameras(m: MapLibreMap) {
        val s = model.settings
        if (!(s.speedCameras || s.plateCameras) || m.cameraPosition.zoom < 12 || cameraFetch != null) return
        val missing = cells(m, cameraCells) ?: return
        val ys = missing.map { it.first }; val xs = missing.map { it.second }; val cell = 0.1
        cameraFetch = scope.launch {
            val found = runCatching { Overpass.cameras(ys.min() * cell, xs.min() * cell, (ys.max() + 1) * cell, (xs.max() + 1) * cell, true, true) }.getOrNull()
            cameraFetch = null
            if (found == null) { delay(30_000); loadCameras(m); return@launch }
            missing.forEach { cameraCells.add("${it.first},${it.second}") }
            found.forEach { cameras[it.id] = it }
            render(); loadCameras(m)
        }
    }

    /** Waze's speed cameras for what's on screen, once zoomed in to a town; each piece of its map once a week. */
    fun loadWazeCameras(m: MapLibreMap) {
        val s = model.settings
        WazeCameras.enabled = s.wazeOn
        if (!s.speedCameras || !s.wazeOn || m.cameraPosition.zoom < 13 || wazeCameraFetch != null) return
        val b = m.projection.visibleRegion.latLngBounds
        wazeCameraFetch = scope.launch {
            val fresh = runCatching { WazeCameras.load(b.latitudeSouth, b.longitudeWest, b.latitudeNorth, b.longitudeEast) }.getOrDefault(false)
            wazeCameraFetch = null
            if (fresh) render()
        }
    }

    private var shownMeasurement: Pair<LatLng, LatLng>? = null
    private fun renderMeasure(style: Style) {
        val measure = model.measurement
        if (measure == shownMeasurement) return
        shownMeasurement = measure
        setShape(style, "kite-measure", measure?.let { (a, b) -> listOf(polyline(listOf(a, b)), point(a), point(b)) }.orEmpty())
    }

    private fun renderStopPins(style: Style?) {
        val search = model.stopSearch
        val results = search?.results.orEmpty()
        val selected = search?.selected?.place?.id
        val key = results to selected
        if (shownStopPins == key) return
        shownStopPins = key
        val features = results.mapIndexed { index, (place) ->
            point(place.location, mapOf("id" to place.id, "rank" to index + 1,
                "selected" to (place.id == selected)))
        }
        setShape(style, StopSearch.PINS, features)
    }

    private fun renderResults(style: Style?) {
        val showList = model.directions == null && !model.isGuiding
        val list = if (showList) model.visibleResults else emptyList()
        val directions = model.directions.takeIf { model.nav == null }
        val plan = directions?.orderedPlaces()
        val here = model.userLatLng
        val target = model.mapNavigator?.destination ?: model.transitGuidance?.destination ?:
            if (plan != null) plan.last() else model.selected
        val destination = target?.location ?: here.takeIf { plan != null }
        val origin = plan?.let { it.first()?.location ?: here.takeUnless { directions.missingOrigin } }
        val stops = model.nav?.stops ?: plan?.drop(1)?.dropLast(1)?.filterNotNull().orEmpty()
        val pickedPlace = plan == null && !model.isGuiding && target != null && target.id == model.selected?.id
        fun cell(at: LatLng?) = at?.let { "${(it.lat * 7000).toInt()},${(it.lng * 7000).toInt()}" }
        val destinationKey = "${target?.id}:${cell(destination)}:$pickedPlace"
        val key = "${list.joinToString(",") { it.id }}|$destinationKey|${model.streetView != null}|${cell(origin)}|${stops.joinToString(",") { it.id }}"
        if (key == lastResultsKey) return
        lastResultsKey = key
        setShape(style, "vela-results", list.mapIndexedNotNull { i, p ->
            if (pickedPlace && model.streetView == null && p.id == target.id) return@mapIndexedNotNull null
            val rating = p.rating?.let { String.format(java.util.Locale.US, "%.1f", it) }
            point(p.location, mapOf("id" to p.id, "icon" to MapIcons.searchName(p), "label" to listOfNotNull(p.name, rating).joinToString("\n"), "rank" to i))
        })
        val sel = mutableListOf<Feature>()
        if (destination != null && model.streetView == null) {
            sel.add(point(destination, mapOf("id" to (target?.id ?: "destination"), "icon" to "pin-selected",
                "anchor" to "bottom", "label" to (target?.name ?: "Your location"))))
        }
        stops.forEachIndexed { i, stop -> sel.add(point(stop.location, mapOf("id" to "stop$i", "icon" to "pin-stop", "anchor" to "center", "label" to stop.name))) }
        origin?.let { sel.add(point(it, mapOf("id" to "origin", "icon" to "pin-origin", "anchor" to "center", "label" to ""))) }
        setShape(style, "vela-selected", sel)
    }

    private var routeGeometry: List<LatLng>? = null
    private var routeDistances = DoubleArray(0)
    private var routeContext = ""
    private var transitStopsKey = ""
    private var visiblePathSection: Pair<String, Valhalla.PathSection>? = null

    private var vehicleKey = ""
    private fun renderRoutes(style: Style?) {
        var alts = emptyList<Route>()
        var main: Route? = null
        var from = 0.0
        val n = model.mapNavigator
        val d = model.directions
        val session = model.transitGuidance
        val overview = session?.overviewing == true
        if (n != null && !overview) { main = n.route; from = n.progress?.alongMeters ?: 0.0 }
        else if (d != null && session == null) { main = d.route; alts = d.current.filter { it.id != main?.id } }
        val trip = if (session != null) session.trip else if (n == null) d?.pickedTrip else null
        val vehicleKeyNow = "${trip?.id}|${model.transitLive.hashCode()}"
        if (vehicleKey != vehicleKeyNow) {
            vehicleKey = vehicleKeyNow
            setShape(style, TRANSIT_VEHICLES, trip?.rides.orEmpty().distinctBy { it.tripId }.mapNotNull { leg ->
                val report = model.transitLive[leg.tripId] ?: return@mapNotNull null
                val at = report.position ?: return@mapNotNull null
                val label = (if (report.gps) "" else "≈") + leg.line.take(4)
                point(at, mapOf("color" to hex(leg.mapColor), "line" to label))
            })
        }
        val keyForStops = "${trip?.id}|${session?.legIndex}|${session?.phase}|$overview"
        if (transitStopsKey != keyForStops) {
            transitStopsKey = keyForStops
            val rideLegs = if (overview || session == null) trip?.rides.orEmpty()
                else listOfNotNull(session.leg?.takeUnless { it.isWalk })
            val pins = rideLegs.flatMap { leg ->
                val calls = if (overview || session == null) listOfNotNull(leg.calls.firstOrNull(), leg.calls.lastOrNull()) else leg.calls
                calls.map { it to leg.mapColor }
            }.distinctBy { it.first.at }
            setShape(style, RIDE_STOPS, pins.map { (stop, tint) -> point(stop.at, mapOf("name" to stop.name, "color" to hex(tint))) })
        }
        val traffic = n?.roadTraffic ?: main?.trafficSpans.orEmpty().takeIf { AppSettings.traffic }.orEmpty()
        val context = "${trip?.id}|${session?.legIndex}|$overview|${main?.id}|${alts.joinToString { it.id }}"
        val follows = n?.following == true
        val highlight = model.pathSectionHighlight.takeIf { main != null && it?.first == main.id }
        if (visiblePathSection != highlight || routeContext.isEmpty()) {
            visiblePathSection = highlight
            val points = highlight?.second?.let { section -> main?.let { Geo.slice(it.polyline, section.from, section.to) } }.orEmpty()
            setShape(style, "kite-path-section", if (points.size >= 2) listOf(polyline(points)) else emptyList())
        }
        val key = "$context|${(from / if (n?.route?.mode == TravelMode.WALK) 4 else 6).toInt()}|$follows|" +
            "${n?.nextManeuver?.alongMeters}|${traffic.hashCode()}"
        if (key == lastRouteKey) return
        lastRouteKey = key
        if (routeContext != context) {
            routeContext = context
            setShape(style, "vela-route-alt", alts.map { polyline(it.polyline) })
            val legs = if (session != null && !overview) trip?.legs?.drop(session.legIndex).orEmpty() else trip?.legs.orEmpty()
            setShape(style, "vela-transit", legs.filter { it.path.size >= 2 }.map { leg ->
                polyline(leg.path, mapOf("walk" to if (leg.isWalk) 1 else 0, "color" to hex(leg.mapColor)))
            })
        }
        val r = main
        if (r == null) {
            for (id in listOf("vela-route", "vela-route-traffic", "vela-route-bubbles", "vela-turn-arrow", "vela-turn-head", "vela-next-road")) setShape(style, id, emptyList())
            lastHeadKey = ""; lastNextRoadKey = ""
            return
        }
        if (routeGeometry !== r.polyline) {
            routeGeometry = r.polyline
            routeDistances = Geo.cumulative(r.polyline)
        }
        val cum = routeDistances
        val total = cum.lastOrNull() ?: return
        val to = if (follows) min(total, from + 16_000.0) else total
        val ahead = if (from > 1 || to < total) Geo.slice(r.polyline, from, to, cum) else r.polyline
        setShape(style, "vela-route", if (ahead.size >= 2) listOf(polyline(ahead)) else emptyList())
        setShape(style, "vela-route-traffic", traffic.mapNotNull { s ->
            val a = max(s.startMeters, from); val b = min(s.startMeters + s.lengthMeters, to)
            if (b <= a) return@mapNotNull null
            val piece = Geo.slice(r.polyline, a, b, cum)
            if (piece.size >= 2) polyline(piece, mapOf("level" to min(s.level, 3))) else null
        })
        // Turn arrow: 50 m of road before the next turn and 40 m into the new road.
        val m = n?.nextManeuver
        val p = n?.progress
        var arrow = emptyList<Feature>()
        var head: Pair<LatLng, Double>? = null
        var nextRoad: Pair<LatLng, String>? = null
        if (n != null && m != null && p != null && m.type != ManeuverType.ARRIVE && m.type != ManeuverType.DEPART &&
            m.type != ManeuverType.STRAIGHT && m.alongMeters - p.alongMeters < 600) {
            var end = m.alongMeters + 40
            if (m.type == ManeuverType.ROUNDABOUT) {
                n.route.maneuvers.firstOrNull { it.leavesRoundabout && it.alongMeters > m.alongMeters }?.let {
                    if (it.alongMeters - m.alongMeters < 250) end = it.alongMeters + 40
                }
            }
            val a = max(m.alongMeters - 50, from); val b = min(end, total)
            val shaft = Geo.slice(r.polyline, a, b, cum)
            if (shaft.size >= 2) {
                val tip = shaft.last(); val prev = Geo.point(r.polyline, max(a, b - 4), cum)
                arrow = listOf(polyline(shaft, mapOf("part" to "shaft")))
                head = tip to Geo.bearing(prev, tip)
            }
            // The new road's name, a little way into it, clear of the arrow head.
            nextRoadName(m)?.let { nextRoad = Geo.point(r.polyline, min(end + 55, total), cum) to it }
        }
        setShape(style, "vela-turn-arrow", arrow)
        val headKey = head?.let { (t, b) -> String.format(java.util.Locale.US, "%.6f,%.6f,%.0f", t.lat, t.lng, b) } ?: ""
        if (headKey != lastHeadKey) {
            lastHeadKey = headKey
            setShape(style, "vela-turn-head", head?.let { (t, b) -> listOf(point(t, mapOf("bearing" to b))) } ?: emptyList())
        }
        val nextRoadKey = nextRoad?.let { (at, name) -> String.format(java.util.Locale.US, "%.6f,%.6f,%s", at.lat, at.lng, name) } ?: ""
        if (nextRoadKey != lastNextRoadKey) {
            lastNextRoadKey = nextRoadKey
            setShape(style, "vela-next-road", nextRoad?.let { (at, name) -> listOf(point(at, mapOf("label" to name))) } ?: emptyList())
        }
        if (n != null || d == null) { setShape(style, "vela-route-bubbles", emptyList()); return }
        val bubbles = d.current.mapIndexed { i, route ->
            val others = d.current.filterIndexed { j, _ -> j != i }.map { it.polyline }
            val cc = Geo.cumulative(route.polyline)
            val len = cc.last()
            var spot = Geo.point(route.polyline, len * 0.5, cc)
            for (f in listOf(0.5, 0.6, 0.7, 0.8, 0.9)) {
                val pt = Geo.point(route.polyline, len * f, cc)
                if (others.none { o -> o.any { it.distanceTo(pt) < 120 } }) { spot = pt; break }
            }
            point(spot, mapOf("label" to Fmt.duration(route.durationSeconds), "sel" to if (route.id == r.id) 1 else 0, "idx" to i))
        }
        setShape(style, "vela-route-bubbles", bubbles)
    }

    private fun renderPuck(style: Style) {
        if (model.mapNavigator != null) {
            if (lastPuckKey.startsWith("cruise:")) setShape(style, NavGlide.PUCK, emptyList())
            lastPuckKey = "nav"
            return
        }
        val fix = LocationService.last.takeIf { model.cruise != null }
        val marker = AppSettings.driveMarker.sprite
        val key = fix?.let { "cruise:${it.timeMillis}:$marker" }.orEmpty()
        if (key == lastPuckKey) return
        val points = fix?.let { listOf(point(it.coord, mapOf("icon" to marker, "bearing" to it.course.coerceAtLeast(0.0)))) }
        setShape(style, NavGlide.PUCK, points.orEmpty())
        lastPuckKey = key
    }

    // Gestures

    private fun box(m: MapLibreMap, p: org.maplibre.android.geometry.LatLng): RectF {
        val pt: PointF = m.projection.toScreenLocation(p)
        val r = 22 * context.resources.displayMetrics.density
        return RectF(pt.x - r, pt.y - r, pt.x + r, pt.y + r)
    }

    private var lastLiveKey = ""
    /** The box the drawn live camera dots cover, so panning inside it redraws nothing. */
    private var liveCamBox: Box? = null

    /** Live camera dots for what's on screen (plus a margin), never while driving. */
    private fun renderLiveCams(m: MapLibreMap, style: Style) {
        val s = model.settings
        // Road cameras only from a city's zoom (there are thousands); webcams from a region's.
        val zoom = m.cameraPosition.zoom
        val roadNow = s.showsRoadCams && zoom >= LiveCams.ROAD_MIN_ZOOM
        val webNow = s.showsWebcams && zoom >= LiveCams.WEBCAM_MIN_ZOOM
        val on = model.nav == null && (roadNow || webNow)
        val b = m.projection.visibleRegion.latLngBounds
        val dLat = (b.latitudeNorth - b.latitudeSouth) * 0.5
        val dLng = (b.longitudeEast - b.longitudeWest) * 0.5
        val inside = liveCamBox?.let { b.latitudeSouth >= it.s && b.latitudeNorth <= it.n && b.longitudeWest >= it.w && b.longitudeEast <= it.e } ?: false
        // Switched on from Layers or Settings: ask for the cameras now, not only after the next pan.
        if (on) loadLiveCams(m)
        val key = "$on$roadNow$webNow${LiveCamStore.version}"
        if (key == lastLiveKey && (!on || inside)) return
        lastLiveKey = key
        liveCamBox = if (on) Box(b.latitudeSouth - dLat, b.longitudeWest - dLng, b.latitudeNorth + dLat, b.longitudeEast + dLng) else null
        val lb = liveCamBox
        val features = if (lb == null) emptyList() else
            LiveCamStore.cams(lb.s, lb.w, lb.n, lb.e, roadNow, webNow).map { c ->
                point(c.location, mapOf("id" to c.id, "icon" to if (c.source.isRoad) "livecam-road" else "livecam-web"))
            }
        setShape(style, "vela-livecams", features)
    }

    /** The road camera list (once a day) and Windy's webcams around what's on screen. */
    fun loadLiveCams(m: MapLibreMap) {
        val s = model.settings
        if (model.nav != null || !s.liveCams) return
        if (s.showsRoadCams || s.liveCamsOnRoute) LiveCamStore.ensureLoaded()
        if (!s.showsWebcams || m.cameraPosition.zoom < LiveCams.WEBCAM_MIN_ZOOM) return
        val b = m.projection.visibleRegion.latLngBounds
        val c = LatLng((b.latitudeSouth + b.latitudeNorth) / 2, (b.longitudeWest + b.longitudeEast) / 2)
        val span = LatLng(b.latitudeSouth, b.longitudeWest).distanceTo(LatLng(b.latitudeNorth, b.longitudeEast)) / 1000
        LiveCamStore.loadWindy(c, span)
    }

    private fun str(f: Feature, k: String): String? = f.getProperty(k)?.takeIf { it.isJsonPrimitive }?.asString

    private fun tapped(m: MapLibreMap, at: org.maplibre.android.geometry.LatLng): Boolean {
        if (model.streetViewMapTapped(at.kite()) || model.positionEndpointPin(at.kite())) return true
        if (model.stopSearch != null) {
            val pin = m.queryRenderedFeatures(box(m, at), StopSearch.PINS).firstOrNull()
            model.selectStopPin(pin?.let { str(it, "id") })
            return true
        }
        if (model.placingStop || now() - pinDroppedAt < 1000) return false
        val box = box(m, at)
        if (model.nav != null) {
            val hit = m.queryRenderedFeatures(box, "vela-waze", "vela-waze-group").firstOrNull()
            if (openWazeAlert(hit?.let { str(it, "id") })) return true
            model.showNavigationPlace(navigationPlaceAt(m, at))
            return true
        }
        if (model.directions != null) {
            val hits = m.queryRenderedFeatures(box, "vela-route-bubble-0", "vela-route-alt", "vela-route-alt-edge")
            hits.firstOrNull { it.hasProperty("idx") }?.let { model.selectRoute(it.getNumberProperty("idx").toInt()); return true }
            val d = model.directions ?: return true
            if (hits.isNotEmpty()) {
                val tappedAt = at.kite()
                val i = d.current.indexOfFirst { r -> r.id != d.route?.id && r.polyline.any { it.distanceTo(tappedAt) < 300 } }
                if (i >= 0) { model.selectRoute(i); return true }
            }
            // A tap on the picked route itself: offer to avoid that road (GitHub idea, 0.7.17).
            if (m.queryRenderedFeatures(box, "vela-route-line", "vela-route-edge").isNotEmpty()) model.askAvoid(at.kite())
            return true
        }
        // Police and crashes sit on top and never join a bubble: a tap that touches one opens it,
        // even with a bubble right next to it.
        m.queryRenderedFeatures(box, "vela-waze").firstOrNull()?.let { f ->
            val id = str(f, "id")
            wazeAlerts.firstOrNull { it.id == id }?.let { view?.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK); model.wazeInfo = it; return true }
        }
        // A numbered bubble: zoom in until it splits into its icons.
        m.queryRenderedFeatures(box, "vela-waze-group-bubble", "vela-cameras-bubble", "vela-livecams-bubble").firstOrNull()?.let { f ->
            (f.geometry() as? Point)?.let { p ->
                m.animateCamera(org.maplibre.android.camera.CameraUpdateFactory.newLatLngZoom(
                    org.maplibre.android.geometry.LatLng(p.latitude(), p.longitude()), min(m.cameraPosition.zoom + 2, 15.0)))
                return true
            }
        }
        m.queryRenderedFeatures(box, "vela-waze-group").firstOrNull()?.let { f ->
            val id = str(f, "id")
            wazeAlerts.firstOrNull { it.id == id }?.let { view?.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK); model.wazeInfo = it; return true }
        }
        m.queryRenderedFeatures(box, "vela-livecams").firstOrNull()?.let { f ->
            str(f, "id")?.let { LiveCamStore.cam(it) }?.let {
                view?.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                model.liveCamRoute = emptyList()
                model.liveCam = it
                return true
            }
        }
        m.queryRenderedFeatures(box, "vela-cameras").firstOrNull()?.let { f ->
            str(f, "surveillanceId")?.toLongOrNull()?.let { id -> surveillance[id]?.let { model.surveillanceInfo = it; return true } }
        }
        m.queryRenderedFeatures(box, "vela-mine").firstOrNull()?.let { f ->
            str(f, "id")?.let { model.myPlace(it) }?.let { model.select(it); return true }
        }
        m.queryRenderedFeatures(box, "vela-results", "kite-search-hit").firstOrNull()?.let { f ->
            val id = str(f, "id")
            model.results.firstOrNull { it.id == id }?.let { model.select(it); return true }
        }
        val selectedId = model.selected?.id
        if (selectedId != null && m.queryRenderedFeatures(box, "vela-selected")
                .any { str(it, "id") == selectedId }) return true
        val transitHit = m.queryRenderedFeatures(box, TRANSIT_STOPS).firstOrNull()
        if (transitHit != null && openOutdoorPlace(str(transitHit, "id"))) return true
        val googleHit = m.queryRenderedFeatures(box, "kite-google-places", GOOGLE_UNREVIEWED).firstOrNull()
        if (googleHit != null && openGooglePlace(str(googleHit, "id"))) return true
        val poiLayers = arrayOf(OpenMapStyle.POIS)
        m.queryRenderedFeatures(box, *poiLayers).firstOrNull()?.let { poi ->
            val name = OpenMapStyle.title(str(poi, "name") ?: str(poi, "name:en"), str(poi, "subclass"), str(poi, "class"))
            val g = poi.geometry() as? Point
            model.select(Place("osm:${g?.latitude()},${g?.longitude()}:$name", name,
                g?.let { LatLng(it.latitude(), it.longitude()) } ?: at.kite(), "osm",
                category = str(poi, "subclass") ?: str(poi, "class")))
            return true
        }
        if (model.selected != null) model.closePlace()
        else if (model.results.isNotEmpty()) model.detent = SheetDetent.PEEK
        return true
    }

    private fun navigationPlaceAt(m: MapLibreMap, at: org.maplibre.android.geometry.LatLng): Place? {
        if (!AppSettings.navigationPlaces) return null
        val hits = m.queryRenderedFeatures(box(m, at), "kite-google-places", GOOGLE_UNREVIEWED, OpenMapStyle.POIS)
        for (hit in hits) {
            googlePlace(str(hit, "id"))?.let { return it }
            val group = str(hit, "class")
            val subclass = str(hit, "subclass")
            if (group == null && subclass == null) continue
            val point = hit.geometry() as? Point ?: continue
            val name = OpenMapStyle.title(str(hit, "name") ?: str(hit, "name:en"), subclass, group)
            return Place("osm:${point.latitude()},${point.longitude()}:$name", name,
                LatLng(point.latitude(), point.longitude()), "osm", category = subclass ?: group)
        }
        return null
    }

    private fun pressed(m: MapLibreMap, at: org.maplibre.android.geometry.LatLng) {
        if (model.streetView != null || model.stopSearch != null || model.placingStop) return
        if (model.positionEndpointPin(at.kite())) return
        pinDroppedAt = now()
        if (model.nav != null) {
            val place = navigationPlaceAt(m, at) ?: if (AppSettings.navigationHoldAnywhere) model.navigationPin(at.kite()) else return
            view?.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            model.addNavigationPlace(place)
            return
        }
        if (model.isGuiding || model.directions != null) return
        view?.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        model.dropPin(at.kite())
    }

    private fun noteHeading(m: MapLibreMap) {
        val h = m.cameraPosition.bearing
        val north = (h % 360) == 0.0
        if (abs(h - model.mapHeading) > 2 || north != (model.mapHeading == 0.0)) model.mapHeading = if (north) 0.0 else h
    }
}
