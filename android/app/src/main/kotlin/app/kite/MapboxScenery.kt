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
import org.maplibre.android.camera.CameraPosition
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor

/** Mapbox Standard paints the map and mirrors Kite's existing route, alert and place overlays. */
class MapboxScenery(private val model: AppModel, private val kite: KiteMap) {
    data class Look(val dark: Boolean, val satellite: Boolean, val terrain: Boolean, val shade: Boolean,
                    val shadows: Boolean, val lamps: Boolean, val traffic: Boolean = true,
                    val palette: MapPalette = MapPalette.default(dark))

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
    private data class Lamp(val at: LatLng, val bearing: Double = 0.0)
    private data class LampArea(val mapped: List<Lamp>, val inferred: List<Lamp>)
    private var lastLampCenter: LatLng? = null
    private var lampRequestAt = 0L
    private val lampCache = object : LinkedHashMap<Pair<Int, Int>, LampArea>(12, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<Pair<Int, Int>, LampArea>?) = size > 12
    }
    private val overlayData = mutableMapOf<String, String>()
    var ready by mutableStateOf(false)
        private set
    var failed by mutableStateOf(false)
        private set

    fun allowRetry() { failed = false }

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
                map.queryRenderedFeatures(RenderedQueryGeometry(hitbox), RenderedQueryOptions(listOf(StopSearch.PINS), null)) { result ->
                    if (model.stopSearch === search) model.selectStopPin(
                        result.value?.firstOrNull()?.queriedFeature?.feature?.getStringProperty("id"))
                }
                true
            } else if (model.nav == null && model.directions == null) {
                val pixel = map.pixelForCoordinate(point)
                map.queryRenderedFeatures(RenderedQueryGeometry(pixel), RenderedQueryOptions(listOf(GOOGLE_PLACES, POI), null)) { result ->
                    val feature = result.value?.firstOrNull()?.queriedFeature?.feature
                    val loc = feature?.geometry() as? Point
                    val name = feature?.getStringProperty("name")
                    if (name.isNullOrBlank() || loc == null) kite.sceneTap(point.kite())
                    else if (!kite.openGooglePlace(feature.getStringProperty("id")))
                        model.resolveTapped(name, loc.kite(), feature.getStringProperty("category_en"), "mapbox")
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
        if (previous.satellite != value.satellite) load() else style?.let { applyLook(it, previous) }
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
        val value = json()
        if (overlayData.put(id, value) == value) return
        style?.getSourceAs<GeoJsonSource>(id)?.data(value)
    }

    fun updatePosition(fix: Fix) {
        updateOverlay(LOCATION) {
            if (model.nav != null) EMPTY else Feature.fromGeometry(Point.fromLngLat(fix.lng, fix.lat)).toJson()
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
        overlayData.clear()
    }

    private fun load() {
        val v = view ?: return
        ready = false
        style = null
        lastLampCell = null
        lastLampCenter = null
        lampRequestAt = 0L
        val uri = if (look.satellite) Style.STANDARD_SATELLITE else Style.STANDARD
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
                addOverlays(loaded)
                addPlaces(loaded)
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
            for (id in listOf(POI, GOOGLE_PLACES, StopSearch.PINS, "kite-vela-mine", "kite-vela-results", "kite-vela-selected")) {
                st.setStyleLayerProperty(id, "text-color", Value.valueOf(text))
                st.setStyleLayerProperty(id, "text-halo-color", Value.valueOf(halo))
            }
            if (previous == null) MapIcons.registerImages(look.dark) { id, bitmap -> st.addImage(id, bitmap) }
            else st.addImage("puck", MapIcons.puck(look.dark))
        }
        val paletteChanged = previous?.palette != look.palette
        if (themeChanged || (paletteChanged && !look.satellite)) {
            val configs = hashMapOf(
                "lightPreset" to Value.valueOf(if (look.dark) "night" else "day"),
                "showPointOfInterestLabels" to Value.valueOf(false),
            )
            if (!look.satellite) {
                for (key in listOf("show3dObjects", "show3dTrees", "show3dLandmarks"))
                    configs[key] = Value.valueOf(true)
                for (field in MapColor.entries) field.styleKey?.let { configs[it] = Value.valueOf(look.palette[field]) }
                configs["colorTrunks"] = Value.valueOf(look.palette[MapColor.HIGHWAYS])
            }
            st.setStyleImportConfigProperties("basemap", configs)
        }
        if (paletteChanged) {
            val color = look.palette[MapColor.ROUTE]
            st.setStyleLayerProperty("kite-route", "line-color", Value.valueOf(color))
            val rgb = Color.parseColor(color)
            val edge = Color.rgb(Color.red(rgb) / 3, Color.green(rgb) / 3, Color.blue(rgb) / 3)
            st.setStyleLayerProperty("kite-edge", "line-color", Value.valueOf(String.format(java.util.Locale.US, "#%06X", edge and 0xFFFFFF)))
        }
        if (themeChanged || previous.shadows != look.shadows) {
            val ambient = if (look.dark) 0.58 else 0.8
            val sunlight = if (look.dark) 0.28 else 0.35
            val lightColor = if (look.dark) "#D4E1FF" else "#FFF5E6"
            val lights = """[{"id":"kite-ambient","type":"ambient","properties":{"color":"$lightColor","intensity":$ambient}},{"id":"kite-sun","type":"directional","properties":{"color":"$lightColor","direction":[210,48],"intensity":$sunlight,"cast-shadows":${look.shadows},"shadow-intensity":0.48}}]"""
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

    private fun addOverlays(st: Style) {
        for (id in overlaySources) st.addSource(GeoJsonSource.Builder(id).data(overlayData[id] ?: EMPTY).build())
        fun line(id: String, source: String, color: Int, width: Double) = LineLayer(id, source).slot("middle")
            .lineColor(color).lineWidth(width).lineCap(LineCap.ROUND).lineJoin(LineJoin.ROUND).lineEmissiveStrength(0.9)
        st.addLayer(line("kite-done", "vela-route-done", 0xFF68778E.toInt(), 7.0))
        st.addLayer(line("kite-alt", "vela-route-alt", 0xFF90BCD1.toInt(), 6.0))
        st.addLayer(line("kite-edge", "vela-route", 0xFF075964.toInt(), 13.0))
        st.addLayer(line("kite-route", "vela-route", 0xFF2DD4BF.toInt(), 8.0))
        st.addLayer(line("kite-transit", "vela-transit", 0xFF377BE7.toInt(), 6.0).lineColor(Expression.toColor(Expression.get("color"))))
        st.addLayer(line("kite-traffic-route", "vela-route-traffic", Color.RED, 8.0)
            .lineColor(Expression.fromRaw("""["match",["get","level"],1,"#F59E0B",2,"#EF4444",3,"#B91C1C","#EF4444"]""")))
        st.addLayer(line("kite-turn-arrow", "vela-turn-arrow", Color.WHITE, 4.0))
        val iconSources = mapOf(
            "vela-mine" to null, "vela-results" to null, "vela-selected" to null, "vela-waze" to null,
            "vela-waze-group" to null, "vela-cameras" to null, "vela-livecams" to null,
            "vela-signals" to "traffic-light", "vela-turn-head" to "turn-head", NavGlide.PUCK to "puck",
        )
        for ((source, image) in iconSources) {
            val layer = SymbolLayer("kite-$source", source).slot("top").iconSize(if (source == NavGlide.PUCK) 0.68 else 0.78)
                .iconAllowOverlap(source in setOf(NavGlide.PUCK, "vela-selected", "vela-waze", "vela-turn-head"))
            if (image == null) layer.iconImage(Expression.get("icon")) else layer.iconImage(image)
            if (source == NavGlide.PUCK || source == "vela-turn-head") layer
                .iconRotate(Expression.get("bearing")).iconRotationAlignment(IconRotationAlignment.MAP)
            if (source == "vela-mine" || source == "vela-results" || source == "vela-selected") layer
                .textField(Expression.get("label")).textSize(12.0).textAnchor(TextAnchor.TOP).textOffset(listOf(0.0, 1.4))
                .textColor(if (look.dark) Color.WHITE else 0xFF23364B.toInt())
                .textHaloColor(if (look.dark) 0xFF21304A.toInt() else Color.WHITE).textHaloWidth(1.5)
            st.addLayer(layer)
        }
        st.addLayer(SymbolLayer(StopSearch.PINS, StopSearch.PINS).slot("top").iconImage(Expression.get("icon"))
            .iconAllowOverlap(true).iconIgnorePlacement(true).textOptional(true)
            .textField(Expression.get("label")).textSize(12.0).textAnchor(TextAnchor.TOP)
            .textOffset(listOf(0.0, 1.3)).textHaloWidth(1.0).textHaloBlur(0.4))
        st.addLayer(CircleLayer("kite-current", LOCATION).slot("top").circleRadius(7.0).circleColor(0xFF00A8C5.toInt())
            .circleStrokeColor(Color.WHITE).circleStrokeWidth(2.5).circleEmissiveStrength(1.0))
    }

    private fun addPlaces(st: Style) {
        MapIcons.registerMapPlaces(look.satellite) { id, bitmap -> st.addImage(id, bitmap) }
        st.addSource(VectorSource.Builder("kite-places-streets").url("mapbox://mapbox.mapbox-streets-v8").build())
        fun marker(id: String, src: String) = SymbolLayer(id, src).slot("top")
            .iconSize(if (id == GOOGLE_PLACES) 0.92 else 0.82).iconPadding(4.0).textOptional(true).textAnchor(TextAnchor.TOP)
            .textOffset(listOf(0.0, 1.05)).textSize(12.0).textField(Expression.fromRaw("""["step",["zoom"],"",15,["get","name"]]"""))
            .textColor(if (look.dark) Color.WHITE else 0xFF263A4F.toInt())
            .textHaloColor(if (look.dark) 0xFF151F2A.toInt() else Color.WHITE).textHaloWidth(0.8).textHaloBlur(0.5).minZoom(13.0)
        st.addLayer(marker(POI, "kite-places-streets").sourceLayer("poi_label")
            .filter(Expression.has("name")).symbolSortKey(Expression.fromRaw("""["coalesce",["get","filterrank"],5]"""))
            .iconImage(Expression.fromRaw(POI_ICON)))
        st.addLayer(marker(GOOGLE_PLACES, "kite-google-places").iconImage(Expression.get("icon")))
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
        st.addStyleModel("kite-model-post", "asset://models/lamp.glb")
        st.addStyleModel("kite-model-lens", "asset://models/lamp_lens.glb")
        st.addLayer(CircleLayer(LAMP_POOL, LAMPS).slot("middle").circleColor("#FFD9A0").circleBlur(1.0)
            .circleOpacity(0.38).circlePitchAlignment(CirclePitchAlignment.MAP).circlePitchScale(CirclePitchScale.MAP)
            .circleEmissiveStrength(1.0).circleRadius(Expression.fromRaw("""["interpolate",["exponential",2],["zoom"],14.3,3,21,256]""")).minZoom(14.3))
        for ((layer, id) in listOf(LAMP_POST to "kite-model-post", LAMP_LENS to "kite-model-lens")) {
            st.addLayer(ModelLayer(layer, LAMPS).slot("middle").modelId(id).modelType(ModelType.COMMON_3D)
                .modelScale(listOf(2.2, 2.2, 2.2)).modelRotation(Expression.get("rotation"))
                .modelAllowDensityReduction(false).modelCastShadows(false).modelReceiveShadows(false).minZoom(14.3))
        }
    }

    fun refreshLamps() {
        val map = view?.mapboxMap ?: return
        val st = style ?: return
        if (!ready || !look.lamps) return
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
                    """[out:json][timeout:18];node["highway"="street_lamp"]($box);out body 2500;way["highway"]["lit"="yes"]($box);out tags geom($box) 1200;"""
                ) ?: return@launch
                withContext(Dispatchers.Default) { parseLamps(raw, mid) }.also { lampCache[cell] = it }
            }
            val features = withContext(Dispatchers.Default) {
                val actual = lamps.mapped.filter { center.distanceTo(it.at) < 1_300 }
                val nearby = (actual + lamps.inferred.filter { center.distanceTo(it.at) < 1_000 })
                    .sortedBy { center.distanceTo(it.at) }.take(90)
                nearby.map { lamp ->
                    Feature.fromGeometry(Point.fromLngLat(lamp.at.lng, lamp.at.lat)).apply {
                        addProperty("rotation", com.google.gson.JsonArray().apply {
                            add(0.0); add(0.0); add(lamp.bearing)
                        })
                    }
                }
            }
            if (lastLampCell != cell || style !== st || !look.lamps) return@launch
            st.getSourceAs<GeoJsonSource>(LAMPS)?.data(FeatureCollection.fromFeatures(features).toJson())
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
        val roads = elements.filter { it["type"] == "way" }.flatMap { way ->
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
            runs
        }
        val latScale = 111_320.0
        val lngScale = latScale * cos(Math.toRadians(center.lat)).coerceAtLeast(0.1)
        fun square(at: LatLng) = floor(at.lat * latScale / 38).toInt() to floor(at.lng * lngScale / 38).toInt()
        val grid = mutableMapOf<Pair<Int, Int>, MutableList<LatLng>>()
        fun occupy(at: LatLng) { grid.getOrPut(square(at)) { mutableListOf() }.add(at) }
        mapped.forEach(::occupy)
        val inferred = mutableListOf<Lamp>()
        for (road in roads) {
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
                    inferred += Lamp(at, Math.toDegrees(side) + 180)
                }
                distance += 46.0
            }
        }
        return LampArea(mapped.map(::Lamp), inferred)
    }

    private fun Point.kite() = LatLng(latitude(), longitude())

    companion object {
        private const val EMPTY = """{"type":"FeatureCollection","features":[]}"""
        private const val POI = "kite-standard-places"
        private const val GOOGLE_PLACES = "kite-standard-google-places"
        private const val LOCATION = "kite-location"
        private const val TRAFFIC = "kite-standard-traffic"
        private const val DEM = "kite-dem"
        private const val SHADE = "kite-hillshade"
        private const val LAMPS = "kite-lamps"
        private const val LAMP_POST = "kite-lamp-post"
        private const val LAMP_LENS = "kite-lamp-lens"
        private const val LAMP_POOL = "kite-lamp-pool"
        private val overlaySources = setOf(LOCATION, NavGlide.PUCK, "vela-route", "vela-route-done", "vela-route-alt",
            "vela-route-traffic", "vela-turn-arrow", "vela-turn-head", "vela-transit", "vela-results", "vela-selected",
            "vela-mine", "vela-waze", "vela-waze-group", "vela-cameras", "vela-livecams", "vela-signals", "kite-google-places", StopSearch.PINS)
        private const val POI_ICON = """["match",["get","maki"],"cafe","poi-coffee","bakery","poi-coffee","fuel","poi-gas","charging-station","poi-gas","parking","poi-parking","rail","poi-transit","bank","poi-money","pharmacy","poi-health",["match",["get","class"],"food_and_drink","poi-food","food_and_drink_stores","poi-shop","store_like","poi-shop","medical","poi-health","lodging","poi-hotel","park_like","poi-park","education","poi-edu","public_facilities","poi-civic","arts_and_entertainment","poi-culture","sport_and_leisure","poi-sport","poi-default"]]"""
    }
}
