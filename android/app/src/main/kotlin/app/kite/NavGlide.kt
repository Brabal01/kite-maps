package app.kite

import android.view.Choreographer
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.kite.core.*
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.Point
import kotlin.math.*

/**
 * Moves the navigation arrow and the camera every screen frame instead of once per GPS fix.
 * Between fixes it keeps the arrow rolling along the route at the current speed, then eases
 * onto each new fix, so driving looks smooth like Google Maps or Waze.
 */
class NavGlide : Choreographer.FrameCallback {
    var map: MapLibreMap? = null
        set(value) {
            if (field === value) return
            field = value
            if (value == null && cameraOutput == null) pauseFrames()
            else if (nav != null) start()
        }
    var mapTouched = false
    var onMapPuck: ((Feature?) -> Unit)? = null
    var cameraOutput: ((CameraPosition, Boolean) -> Unit)? = null
    private var cameraEntry: CameraPosition? = null
    private var cameraEntryAt = 0L
    private var lastCamera: CameraPosition? = null
    val followingCamera: CameraPosition?
        get() = lastCamera.takeIf { nav?.following == true && !mapTouched }

    fun restoreFollowingCamera() {
        val camera = followingCamera ?: return
        outputCamera(camera, synchronize = true)
    }

    fun easeFromCurrentCamera(current: CameraPosition? = null) {
        mapTouched = false
        cameraEntry = current ?: map?.cameraPosition
        cameraEntryAt = System.nanoTime()
        lastCamera = null
        map?.cancelTransitions()
    }
    /** The map's height in dp. */
    var heightDp = 800f
    var compactViewport = false
    var widthDp = 400f
    /**
     * True while the camera follows the car: the car then always sits at the same spot on screen,
     * so the navigation screen draws it there itself (steady, never fading) instead of the map.
     */
    var carOnScreen by mutableStateOf(false); private set
    private var puckOnMap = false
    private var puckPushedAt = 0L
    private var puckPushed: LatLng? = null
    private var puckPushedBearing = 0.0
    private var puckPushedMarker = DriveMarker.ARROW

    companion object {
        /** Where the car sits on screen while following: 70% of the way down. */
        const val TOP_FRACTION = 0.7f
        fun bottomInset(height: Float, compact: Boolean = false): Float =
            if (compact) height * 0.12f else min(170f, height * 0.34f)
        fun topInset(height: Float, compact: Boolean = false): Float {
            if (compact) return height * 0.43f
            val viewport = min(height, max(48f, height * 0.10f))
            return min(height * TOP_FRACTION, max(0f, height - bottomInset(height) - viewport))
        }
        /** The car's height on a screen [height] dp tall, matching the camera's padded center. */
        fun carY(height: Float, north: Float = 0f, compact: Boolean = false): Float =
            (topInset(height, compact) * (if (compact) 1f else 1 - north) + height - bottomInset(height, compact)) / 2
        const val PUCK = "vela-puck"

        internal fun shortestTurn(from: Double, to: Double): Double = ((to - from + 540) % 360) - 180

        internal fun needsCameraCorrection(
            actual: LatLng, expected: LatLng, actualZoom: Double, expectedZoom: Double,
        ): Boolean = actual.distanceTo(expected) > 5.0 || abs(actualZoom - expectedZoom) > 0.08
    }

    private var nav: Navigator? = null
    private var running = false
    private var lastFrame = 0L

    private var fixAt = 0L
    private var fixAlong = 0.0
    private var fixCoord = LatLng(0.0, 0.0)
    private var fixBearing = 0.0
    private var fixSpeed = 0.0
    private var fixCourse = -1.0
    private var onRoute = false
    private var line: List<LatLng> = emptyList()
    private var cum = DoubleArray(1)
    private var targetAcross = 600.0
    private var targetPitch = 50.0
    /** 3D, 2D or north up, from the map button. */
    var look = MapLook.TILTED
    var deviceHeading: Double? = null
    /** 0 facing the way you go, 1 north up; eased so a tap turns the map rather than jumping. */
    private var northBlend = 0.0

    /**
     * For the car drawn on screen: its position, heading relative to the camera, and tilt.
     * Read inside drawing lambdas, so each frame only redraws the car.
     */
    var carNorth by mutableFloatStateOf(0f); private set
    var carTurn by mutableFloatStateOf(0f); private set
    var carSquash by mutableFloatStateOf(0.64f); private set

    private var shownAlong: Double? = null
    private var shownCoord: LatLng? = null
    private var shownBearing = 0.0
    private var markerBearing = 0.0
    private var shownAcross = 600.0
    private var shownPitch = 50.0

    /** Called on every GPS fix while navigating. */
    fun fix(n: Navigator, loc: Fix, across: Double, pitch: Double) {
        val starting = nav !== n
        if (starting) {
            cameraEntry = null
            lastCamera = null
            shownCoord = null
            shownAlong = null
            map?.cancelTransitions()
        }
        nav = n
        val p = n.progress
        val poly = n.route.polyline
        if (poly !== line) {
            line = poly
            cum = Geo.cumulative(poly)
            shownAlong = null
        }
        onRoute = p?.let { !it.offRoute && it.offsetMeters < if (n.route.mode == TravelMode.WALK) 14 else 40 } ?: false
        fixAt = System.nanoTime()
        fixAlong = p?.alongMeters ?: 0.0
        fixCoord = loc.coord
        fixSpeed = if (loc.speed > 0.5) loc.speed else 0.0
        fixCourse = if (loc.courseKnown && loc.speed >= 1.3 && loc.accuracy <= 50.0) loc.course else -1.0
        fixBearing = if (fixCourse >= 0) fixCourse else (p?.routeBearing ?: shownBearing)
        targetAcross = across
        targetPitch = pitch
        if (shownCoord == null) {
            shownAlong = if (onRoute) fixAlong else null
            shownCoord = if (onRoute) coord(fixAlong) else fixCoord
            shownBearing = if (onRoute) roadBearing(fixAlong) else fixBearing
            markerBearing = markerTarget(shownBearing)
            shownAcross = across
            shownPitch = pitch
            northBlend = if (look == MapLook.NORTH) 1.0 else 0.0
        }
        // Keep the first view even if the renderer is still being laid out.
        if (starting || lastCamera == null && n.following) step(0.0)
        if (map != null || cameraOutput != null) start()
    }

    private fun pauseFrames() {
        if (running) Choreographer.getInstance().removeFrameCallback(this)
        running = false
        lastFrame = 0
    }

    fun stop() {
        pauseFrames()
        nav = null
        shownAlong = null
        shownCoord = null
        cameraEntry = null
        lastCamera = null
        carOnScreen = false
        clearPuck()
        puckOnMap = false
        puckPushed = null
    }

    private fun clearPuck() {
        onMapPuck?.invoke(null)
        (map?.style?.getSource(PUCK) as? GeoJsonSource)?.setGeoJson(org.maplibre.geojson.FeatureCollection.fromFeatures(emptyList()))
    }

    private fun start() {
        if (running) return
        running = true
        lastFrame = 0
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (!running) return
        val dt = if (lastFrame == 0L) 0.0 else min(0.1, (frameTimeNanos - lastFrame) / 1e9)
        lastFrame = frameTimeNanos
        step(dt)
        if (running) {
            val stationary = fixSpeed <= 0.5 && cameraEntry == null && abs(shownPitch - targetPitch) < 0.15 &&
                abs(northBlend - if (look == MapLook.NORTH) 1.0 else 0.0) < 0.005 && abs(shownAcross - targetAcross) < 1
            val choreographer = Choreographer.getInstance()
            if (mapTouched || stationary || nav?.following == false) choreographer.postFrameCallbackDelayed(this, 48L)
            else choreographer.postFrameCallback(this)
        }
    }

    private fun step(dt: Double) {
        val n = nav ?: run { pauseFrames(); return }
        val ahead = fixSpeed * min(2.0, max(0.0, (System.nanoTime() - fixAt) / 1e9))
        val k = if (dt == 0.0) 1.0 else 1 - exp(-dt / 0.35)

        val coordNow: LatLng
        var bearingTarget = fixBearing
        if (onRoute && line.isNotEmpty()) {
            val want = min(fixAlong + ahead, cum.last())
            var along = shownAlong ?: want
            if (abs(want - along) > 150) along = want
            val next = along + (want - along) * k
            along = if (next < along && along - want < 15) along else next
            shownAlong = along
            coordNow = coord(along)
            bearingTarget = roadBearing(along)
        } else {
            shownAlong = null
            var want = fixCoord
            if (fixCourse >= 0) want = moved(fixCoord, ahead, fixCourse)
            val from = shownCoord ?: want
            coordNow = if (from.distanceTo(want) > 200) want
            else LatLng(from.lat + (want.lat - from.lat) * k, from.lng + (want.lng - from.lng) * k)
        }
        shownCoord = coordNow
        val markerTarget = markerTarget(shownAlong?.let { roadBearing(it, behind = 1.0, ahead = 5.0) } ?: bearingTarget)
        markerBearing = (markerBearing + shortestTurn(markerBearing, markerTarget) *
            (if (dt == 0.0) 1.0 else 1 - exp(-dt / 0.16)) + 360) % 360
        shownBearing = (shownBearing + shortestTurn(shownBearing, bearingTarget) *
            (if (dt == 0.0) 1.0 else 1 - exp(-dt / 0.45)) + 360) % 360
        // Zooming in for a turn takes about a second; easing back out afterwards is gentler.
        val zoomTime = if (targetAcross < shownAcross) 0.48 else 1.6
        shownAcross += (targetAcross - shownAcross) * (if (dt == 0.0) 1.0 else 1 - exp(-dt / zoomTime))
        shownPitch += (targetPitch - shownPitch) * (if (dt == 0.0) 1.0 else 1 - exp(-dt / 0.28))

        val entering = cameraEntry != null
        if (n.following && !entering) {
            if (!carOnScreen) carOnScreen = true
            if (puckOnMap) { clearPuck(); puckOnMap = false }
        } else {
            if (!n.following) { cameraEntry = null; lastCamera = null }
            if (carOnScreen) carOnScreen = false
            // On the map, moved only now and then: each new spot makes the map fade the arrow in again.
            val now = System.nanoTime()
            val last = puckPushed
            val turned = abs(shortestTurn(puckPushedBearing, markerBearing))
            val markerStyle = if (n.route.mode == TravelMode.DRIVE) AppSettings.driveMarker else DriveMarker.ARROW
            if (last == null || now - puckPushedAt > 1_000_000_000L ||
                last.distanceTo(coordNow) > 25 || turned > 20 || puckPushedMarker != markerStyle) {
                val marker = Feature.fromGeometry(Point.fromLngLat(coordNow.lng, coordNow.lat))
                    .apply {
                        addNumberProperty("bearing", markerBearing)
                        addStringProperty("icon", markerStyle.sprite)
                    }
                (map?.style?.getSource(PUCK) as? GeoJsonSource)?.setGeoJson(marker)
                onMapPuck?.invoke(marker)
                puckPushedMarker = markerStyle
                puckPushed = coordNow; puckPushedAt = now; puckPushedBearing = markerBearing; puckOnMap = true
            }
        }
        val northTarget = if (look == MapLook.NORTH) 1.0 else 0.0
        northBlend += (northTarget - northBlend) * (if (dt == 0.0) 1.0 else 1 - exp(-dt / 0.3))
        if (abs(northTarget - northBlend) < 0.001) northBlend = northTarget
        if (n.following && !mapTouched) {
            val d = KiteApp.app.resources.displayMetrics.density.toDouble()
            // North up: the map turns to face north and the car moves up to the middle, as the road
            // ahead can be any way round. Otherwise it faces the way you go with the car low down.
            val forward = deviceHeading?.takeIf { fixSpeed < 1.4 || n.route.mode == TravelMode.WALK } ?: shownBearing
            val heading = (forward + shortestTurn(forward, 0.0) * northBlend + 360) % 360
            carNorth = northBlend.toFloat()
            carSquash = (1 - 0.36 * (shownPitch / 50.0).coerceIn(0.0, 1.0)).toFloat()
            // A pitched camera sees farther than the same zoom flat: zoom in a little to match the iPhone's distance.
            val zoom = MapCam.zoomFor(shownAcross, coordNow.lat, widthDp) + 0.35
            val camera = CameraPosition.Builder().target(coordNow.ml()).zoom(zoom).tilt(shownPitch).bearing(heading)
                .padding(0.0, topInset(heightDp, compactViewport) * (if (compactViewport) 1.0 else 1 - northBlend) * d,
                    0.0, bottomInset(heightDp, compactViewport) * d).build()
            val visible = enter(camera)
            carTurn = shortestTurn(visible.bearing, markerBearing).toFloat()
            val last = lastCamera
            val entryComplete = entering && cameraEntry == null
            if (last == null || entryComplete || !nearCamera(last, visible)) {
                lastCamera = visible
                outputCamera(visible, synchronize = last == null || entryComplete)
            }
        }
    }

    private fun outputCamera(camera: CameraPosition, synchronize: Boolean) {
        val output = cameraOutput
        if (output != null) output(camera, synchronize)
        else map?.moveCamera(CameraUpdateFactory.newCameraPosition(camera))
    }

    private fun markerTarget(roadHeading: Double): Double =
        if (nav?.route?.mode == TravelMode.DRIVE && fixCourse >= 0) fixCourse else roadHeading

    private fun enter(target: CameraPosition): CameraPosition {
        val from = cameraEntry ?: return target
        val a = from.target ?: return target.also { cameraEntry = null }
        val b = target.target ?: return target.also { cameraEntry = null }
        val t = ((System.nanoTime() - cameraEntryAt) / 390_000_000.0).coerceIn(0.0, 1.0)
        if (t >= 1.0) {
            cameraEntry = null
            return target
        }
        val f = t * t * (3 - 2 * t)
        fun mix(x: Double, y: Double) = x + (y - x) * f
        fun angle(x: Double, y: Double) = x + ((y - x + 540) % 360 - 180) * f
        val startPadding = from.padding ?: DoubleArray(4)
        val endPadding = target.padding ?: DoubleArray(4)
        return CameraPosition.Builder().target(
            org.maplibre.android.geometry.LatLng(mix(a.latitude, b.latitude),
                ((angle(a.longitude, b.longitude) + 540) % 360) - 180))
            .zoom(mix(from.zoom, target.zoom)).tilt(mix(from.tilt, target.tilt))
            .bearing((angle(from.bearing, target.bearing) + 360) % 360)
            .padding(DoubleArray(4) { mix(startPadding[it], endPadding[it]) }).build()
    }

    private fun nearCamera(a: CameraPosition, b: CameraPosition): Boolean {
        val center = a.target ?: return false
        val next = b.target ?: return false
        val pad = a.padding ?: return false
        val other = b.padding ?: return false
        return abs(a.zoom - b.zoom) < 0.001 && abs(a.tilt - b.tilt) < 0.05 &&
            abs((a.bearing - b.bearing + 540) % 360 - 180) < 0.07 &&
            center.kite().distanceTo(next.kite()) < 0.16 &&
            pad.indices.all { abs(pad[it] - other[it]) < 0.4 }
    }

    private fun coord(along: Double): LatLng = Geo.point(line, along, cum)

    private fun roadBearing(along: Double, behind: Double = 5.0, ahead: Double = 15.0): Double {
        val a = Geo.point(line, max(0.0, along - behind), cum)
        val b = Geo.point(line, along + ahead, cum)
        return if (a == b) shownBearing else Geo.bearing(a, b)
    }

    private fun moved(c: LatLng, meters: Double, bearing: Double): LatLng {
        val r = bearing * PI / 180
        val dLat = meters * cos(r) / 111_320
        val dLng = meters * sin(r) / (111_320 * max(0.2, cos(c.lat * PI / 180)))
        return LatLng(c.lat + dLat, c.lng + dLng)
    }
}
