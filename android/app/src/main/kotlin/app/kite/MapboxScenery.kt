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
import com.mapbox.maps.plugin.attribution.AttributionDialogManagerImpl
import com.mapbox.maps.plugin.attribution.attribution
import com.mapbox.maps.plugin.gestures.addOnMapClickListener
import com.mapbox.maps.plugin.gestures.addOnMapLongClickListener
import com.mapbox.maps.plugin.logo.logo
import kotlinx.coroutines.Dispatchers
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
    private var watchdog: Job? = null
    private var styleRequest = 0
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

    fun showTransit(show: Boolean) {
        style?.setStyleLayerProperty("kite-rail", "visibility", Value.valueOf(if (show) "visible" else "none"))
    }

    fun applyOutdoorLayers() { style?.let(::applyOutdoorLayers) }

    private fun applyOutdoorLayers(st: Style) {
        val s = AppSettings
        fun show(id: String, enabled: Boolean) {
            st.setStyleLayerProperty(id, "visibility", Value.valueOf(if (enabled) "visible" else "none"))
        }
        show(OpenMapStyle.POIS, s.openMapPlaces && model.nav == null && model.transitGuidance == null)
        show(OpenMapStyle.HIKING, s.hikingTrails)
        show(OpenMapStyle.CYCLING, s.bikeTrails)
        Value.fromJson(OpenMapStyle.filter(s.openPlaceGroups)).value?.let {
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
        MapboxOptions.accessToken = token
        val mapView = MapView(context, MapInitOptions(context, textureView = true))
        view = mapView
        attributionDialog = AttributionDialogManagerImpl(context)
        val map = mapView.mapboxMap
        mapView.logo.enabled = false
        mapView.attribution.enabled = false
        idleSubscription = map.subscribeMapIdle {
            if (movingFromTouch) {
                copyCameraToKite(mapView)
                movingFromTouch = false
            }
            refreshLamps()
        }
        errorSubscription = map.subscribeMapLoadingError { error ->
            if (error.type.name.startsWith("STYLE") && !ready) failStyle()
        }
        map.addOnMapClickListener { point ->
            if (model.stopSearch != null) {
                val search = model.stopSearch
                val pixel = map.pixelForCoordinate(point)
                val pad = 13.0 * context.resources.displayMetrics.density
                val hitbox = ScreenBox(ScreenCoordinate(pixel.x - pad, pixel.y - pad), ScreenCoordinate(pixel.x + pad, pixel.y + pad))
                map.queryRenderedFeatures(RenderedQueryGeometry(hitbox), RenderedQueryOptions(listOf("kite-stop-hit"), null)) { result ->
                    if (model.stopSearch === search) model.selectStopPin(
                        result.value?.firstOrNull()?.queriedFeature?.feature?.getStringProperty("id"))
                }
                true
            } else if (model.nav != null && !model.placingStop) {
                map.queryRenderedFeatures(RenderedQueryGeometry(map.pixelForCoordinate(point)),
                    RenderedQueryOptions(listOf("kite-vela-waze", "kite-vela-waze-group"), null)) { result ->
                    val hit = result.value?.firstOrNull()?.queriedFeature?.feature
                    if (hit != null) kite.openWazeAlert(hit.getStringProperty("id"))
                }
                true
            } else if (!model.placingStop && model.nav == null && model.directions == null) {
                val pixel = map.pixelForCoordinate(point)
                map.queryRenderedFeatures(RenderedQueryGeometry(pixel), RenderedQueryOptions(listOf("kite-search-hit", "kite-vela-results", KiteMap.TRANSIT_STOPS, GOOGLE_PLACES, OpenMapStyle.POIS, KiteMap.GOOGLE_UNREVIEWED), null)) { result ->
                    val feature = result.value?.firstOrNull()?.queriedFeature?.feature
                    val loc = feature?.geometry() as? Point
                    if (feature == null || loc == null) kite.sceneTap(point.kite())
                    else {
                        fun str(key: String) = feature.getProperty(key)?.takeIf { it.isJsonPrimitive }?.asString
                        val id = str("id")
                        if (!kite.openSearchResult(id) && !kite.openOutdoorPlace(id) && !kite.openGooglePlace(id)) {
                            val subclass = str("subclass")
                            val klass = str("class")
                            val name = OpenMapStyle.title(str("name"), subclass, klass)
                            model.select(Place("osm:${loc.latitude()},${loc.longitude()}:$name", name, loc.kite(), "osm",
                                category = subclass ?: klass), focus = false)
                        }
                    }
                }
                true
            } else kite.sceneTap(point.kite())
        }
        map.addOnMapLongClickListener { point ->
            if (model.stopSearch == null) kite.scenePress(point.kite())
            true
        }
        load()
        return mapView
    }

    fun touch(event: MotionEvent) {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                movingFromTouch = false
                model.glide.mapTouched = true
            }
            MotionEvent.ACTION_MOVE -> if (event.pointerCount > 1 || abs(event.x - downX) + abs(event.y - downY) > 10f) {
                movingFromTouch = true
                model.nav?.following = false
                model.transitGuidance?.following = false
                model.stopTransitOverview()
                model.browseFollowing = false
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                model.glide.mapTouched = false
                if (movingFromTouch) view?.let(::copyCameraToKite)
            }
        }
    }

    private fun failStyle() {
        if (destroying || ready || failed) return
        style = null
        failed = true
        view?.context?.let { Toast.makeText(it, "Mapbox Standard unavailable. Using the classic map.", Toast.LENGTH_LONG).show() }
        Log.w("KiteScenery", "Standard style unavailable")
    }

    fun setLook(value: Look) {
        val previous = look
        if (previous == value) return
        look = value
        style?.let { applyLook(it, previous) }
    }

    fun syncFromKite(camera: CameraPosition) {
        val map = view?.mapboxMap ?: return
        if (movingFromTouch && model.glide.mapTouched) return
        val at = camera.target ?: return
        val current = map.cameraState
        val pitch = camera.tilt.coerceIn(0.0, 60.0)
        val insets = camera.padding ?: DoubleArray(4)
        val p = current.padding
        if (abs(current.zoom - camera.zoom) < 0.0001 && abs(current.pitch - pitch) < 0.01 &&
            abs((current.bearing - camera.bearing + 540) % 360 - 180) < 0.01 &&
            abs(p.left - insets[0]) + abs(p.top - insets[1]) + abs(p.right - insets[2]) + abs(p.bottom - insets[3]) < 0.3 &&
            current.center.kite().distanceTo(at.kite()) < 0.1) return
        movingFromTouch = false
        map.setCamera(CameraOptions.Builder().center(Point.fromLngLat(at.longitude, at.latitude))
            .zoom(camera.zoom).pitch(pitch).bearing(camera.bearing)
            .padding(EdgeInsets(insets[1], insets[0], insets[3], insets[2])).build())
    }

    private fun copyCameraToKite(mapView: MapView) {
        val c = mapView.mapboxMap.cameraState
        val p = c.padding
        kite.syncFromScenery(CameraPosition.Builder().target(c.center.kite().ml())
            .zoom(c.zoom).bearing(c.bearing).tilt(c.pitch).padding(p.left, p.top, p.right, p.bottom).build())
    }

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
        val navigating = model.nav != null
        updateOverlay(LOCATION) {
            if (navigating) EMPTY else Feature.fromGeometry(Point.fromLngLat(fix.lng, fix.lat)).toJson()
        }
    }

    fun detach(mapView: MapView) {
        if (view !== mapView) return
        destroying = true
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
    }

    private fun load() {
        val v = view ?: return
        ready = false
        style = null
        lastLampCell = null
        lastLampCenter = null
        lampRequestAt = 0L
        val uri = Style.STANDARD
        val request = ++styleRequest
        watchdog?.cancel()
        watchdog = model.scope.launch {
            delay(15_000)
            if (request == styleRequest) failStyle()
        }
        v.mapboxMap.loadStyle(uri) { loaded ->
            if (destroying || failed || view !== v || request != styleRequest) return@loadStyle
            watchdog?.cancel()
            try {
                style = loaded
                addBasemapDetails(loaded)
                addOverlays(loaded)
                addPlaces(loaded)
                applyOutdoorLayers(loaded)
                addTraffic(loaded)
                addLamps(loaded)
                applyLook(loaded)
                model.map?.cameraPosition?.let(::syncFromKite)
                LocationService.last?.let(::updatePosition)
                ready = true
                kite.refreshScenery()
                refreshLamps()
            } catch (e: Exception) {
                Log.w("KiteScenery", "Standard map setup failed", e)
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
        if (themeChanged || paletteChanged || previous.satellite != look.satellite || previous.driving != look.driving) {
            val configs = hashMapOf(
                "lightPreset" to Value.valueOf(if (look.dark && !look.satellite) "night" else "day"),
                "showPointOfInterestLabels" to Value.valueOf(false),
            )
            for (key in listOf("show3dObjects", "show3dTrees", "show3dLandmarks"))
                configs[key] = Value.valueOf(!look.satellite)
            configs["showHdRoads"] = Value.valueOf(look.driving && !look.satellite)
            if (!look.satellite) {
                for (field in MapColor.entries) field.styleKey?.let { configs[it] = Value.valueOf(look.palette[field]) }
                configs["colorTrunks"] = Value.valueOf(look.palette[MapColor.HIGHWAYS])
            }
            st.setStyleImportConfigProperties("basemap", configs)
            fun visible(id: String, on: Boolean) {
                st.setStyleLayerProperty(id, "visibility", Value.valueOf(if (on) "visible" else "none"))
            }
            visible("kite-satellite-imagery", look.satellite)
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
        if ((look.terrain || look.shade) && !st.styleSourceExists(DEM)) {
            st.addSource(RasterDemSource.Builder(DEM)
                .tiles(listOf("https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"))
                .encoding(Encoding.TERRARIUM).tileSize(256).maxzoom(13).attribution("Terrain Tiles: Mapzen, AWS Open Data").build())
        }
        if (previous?.terrain != look.terrain) {
            if (look.terrain) st.setTerrain(Terrain(DEM).exaggeration(1.15)) else st.removeTerrain()
        }
        if (previous?.shade != look.shade) {
            if (look.shade && !st.styleLayerExists(SHADE))
                st.addLayer(HillshadeLayer(SHADE, DEM).slot("bottom").hillshadeExaggeration(0.32))
            if (st.styleLayerExists(SHADE))
                st.setStyleLayerProperty(SHADE, "visibility", Value.valueOf(if (look.shade) "visible" else "none"))
        }
        if (themeChanged || previous.lamps != look.lamps) {
            for (id in listOf(LAMP_POST, LAMP_LENS, LAMP_POOL)) {
                st.setStyleLayerProperty(id, "visibility", Value.valueOf(
                    if (look.lamps && (id != LAMP_POOL || look.dark)) "visible" else "none"))
            }
            st.setStyleLayerProperty(LAMP_LENS, "model-emissive-strength", Value.valueOf(if (look.dark) 1.0 else 0.15))
            if (!look.lamps) {
                lampJob?.cancel()
                lastLampCell = null
                lastLampCenter = null
                lampRequestAt = 0L
            } else refreshLamps()
        }
        if (previous?.traffic != look.traffic)
            st.setStyleLayerProperty(TRAFFIC, "visibility", Value.valueOf(if (look.traffic) "visible" else "none"))
    }

    private fun addBasemapDetails(st: Style) {
        st.addSource(RasterSource.Builder("kite-satellite-imagery").url("mapbox://mapbox.satellite").tileSize(256).build())
        st.addLayer(RasterLayer("kite-satellite-imagery", "kite-satellite-imagery").slot("middle").visibility(Visibility.NONE))
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
        st.addLayer(line("kite-done", "vela-route-done", 0xFF68778E.toInt(), 7.0))
        st.addLayer(line("kite-alt", "vela-route-alt", 0xFF90BCD1.toInt(), 6.0))
        st.addLayer(line("kite-edge", "vela-route", 0xFF075964.toInt(), 13.0))
        st.addLayer(line("kite-route", "vela-route", 0xFF2DD4BF.toInt(), 8.0))
        st.addLayer(line("kite-transit", "vela-transit", 0xFF377BE7.toInt(), 6.0).lineColor(Expression.toColor(Expression.get("color"))))
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
            .circleColor("#3659B0").circleStrokeColor(Color.WHITE).circleStrokeWidth(2.0).circleEmissiveStrength(1.0))
        st.addLayer(line("kite-turn-arrow", "vela-turn-arrow", Color.WHITE, 4.0))
        st.addLayer(CircleLayer("kite-search-hit", "vela-results").slot("top").circleRadius(22.0)
            .circleColor("#164B9F").circleStrokeColor("#C4E1FF").circleStrokeWidth(3.0).circleEmissiveStrength(1.0)
            .circlePitchAlignment(CirclePitchAlignment.VIEWPORT).circlePitchScale(CirclePitchScale.VIEWPORT))
        val iconSources = mapOf(
            "vela-mine" to null, "vela-results" to null, "vela-selected" to null, "vela-waze" to null,
            "vela-waze-group" to null, "vela-cameras" to null, "vela-livecams" to null,
            "vela-signals" to null, "vela-turn-head" to "turn-head", NavGlide.PUCK to "puck",
        )
        for ((source, image) in iconSources) {
            val layer = SymbolLayer("kite-$source", source).slot("top").iconSize(when (source) {
                NavGlide.PUCK -> 0.68
                "vela-results", "vela-signals", "vela-waze", "vela-waze-group", "vela-cameras" -> 1.17
                else -> 0.78
            }).iconAllowOverlap(source in setOf(NavGlide.PUCK, "vela-results", "vela-selected", "vela-waze", "vela-turn-head"))
            if (image == null) layer.iconImage(Expression.get("icon")) else layer.iconImage(image)
            if (source == "vela-signals") layer.minZoom(13.3).iconAllowOverlap(true)
            if (source == "vela-waze-group") layer.iconAllowOverlap(true)
            if (source == NavGlide.PUCK || source == "vela-turn-head") layer
                .iconRotate(Expression.get("bearing")).iconRotationAlignment(IconRotationAlignment.MAP)
            if (source == "vela-mine" || source == "vela-results" || source == "vela-selected") layer
                .textField(Expression.get("label")).textSize(if (source == "vela-results") 14.0 else 12.0)
                .textAnchor(TextAnchor.TOP).textOffset(listOf(0.0, if (source == "vela-results") 1.9 else 1.4))
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
        st.addLayer(marker(GOOGLE_PLACES, "kite-google-places").iconImage(Expression.get("icon"))
            .filter(Expression.fromRaw("""["==",["get","reviewed"],true]""")))
        st.addLayer(marker(KiteMap.TRANSIT_STOPS, KiteMap.TRANSIT_STOPS).iconImage(Expression.get("icon"))
            .textField(Expression.get("name")).minZoom(11.5))
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

    fun refreshLamps() {
        val map = view?.mapboxMap ?: return
        val st = style ?: return
        if (!ready || !look.lamps || model.glide.mapTouched || model.placingStop || model.stopSearch != null) return
        val cam = map.cameraState
        if (cam.zoom < 14.3) return
        val center = cam.center.kite()
        val cell = floor(center.lat / 0.01).toInt() to floor(center.lng / 0.01).toInt()
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
            val lamps = cached ?: run {
                delay(250)
                val mid = LatLng((cell.first + 0.5) * 0.01, (cell.second + 0.5) * 0.01)
                val lngSpan = 0.012 / cos(Math.toRadians(mid.lat)).coerceAtLeast(0.35)
                val box = "${(mid.lat - 0.012).coerceAtLeast(-90.0)},${(mid.lng - lngSpan).coerceAtLeast(-180.0)}," +
                    "${(mid.lat + 0.012).coerceAtMost(90.0)},${(mid.lng + lngSpan).coerceAtMost(180.0)}"
                val raw = Overpass.query(
                    """[out:json][timeout:18];node["highway"="street_lamp"]($box);out body 2500;way["highway"]["lit"="yes"]($box);out tags geom($box) 850;way["highway"~"^(residential|living_street)$"]["lit"!~"^(no|disused)$"]["access"!~"^(no|private)$"]($box);out tags geom($box) 700;"""
                ) ?: return@launch
                withContext(Dispatchers.Default) { parseLamps(raw, mid) }.also { lampCache[cell] = it }
            }
            val budget = if (look.shadows && model.nav?.following == true) 44 else 65
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
                models to nearby.map { Feature.fromGeometry(Point.fromLngLat(it.pool.lng, it.pool.lat)) }
            }
            if (lastLampCell != cell || style !== st || !look.lamps) return@launch
            st.getSourceAs<GeoJsonSource>(LAMPS)?.data(FeatureCollection.fromFeatures(features).toJson())
            st.getSourceAs<GeoJsonSource>(LAMP_GLOWS)?.data(FeatureCollection.fromFeatures(pools).toJson())
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
        private val overlaySources = setOf(LOCATION, NavGlide.PUCK, "vela-route", "vela-route-done", "vela-route-alt",
            "vela-route-traffic", "vela-turn-arrow", "vela-turn-head", "vela-transit", "vela-results", "vela-selected",
            "vela-mine", "vela-waze", "vela-waze-group", "vela-cameras", "vela-livecams", "vela-signals", "vela-waze-heat", "kite-google-places", "kite-measure", "vela-rail", KiteMap.TRANSIT_STOPS, KiteMap.RIDE_STOPS, StopSearch.PINS)
    }
}
