package app.kite

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import app.kite.ui.*

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        Connectivity.start(applicationContext)
        LocationService.refreshPermission()
        Voice.warmUp()
        WazeWeb.install(this)
        handle(intent)
        setContent { KiteTheme { KiteScreen(model, this) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    override fun onResume() {
        super.onResume()
        LocationService.visible = true
        LocationService.refreshPermission()
    }

    /** Out of sight and not driving: GPS off to save the battery (back on at onResume). */
    override fun onStop() {
        super.onStop()
        LocationService.visible = false
        LocationService.stop()
    }

    override fun onDestroy() {
        WazeWeb.uninstall(this)
        super.onDestroy()
    }

    /** Links shared from other apps, map links opened in Kite, and the Home, Work and Car shortcuts. */
    private fun handle(i: Intent?) {
        i ?: return
        when (i.action) {
            Intent.ACTION_SEND -> i.getStringExtra(Intent.EXTRA_TEXT)?.let { model.openLink(it) }
            Intent.ACTION_VIEW -> i.dataString?.let { model.openLink(it) }
            "app.kite.HOME" -> model.perform(LaunchKind.HOME)
            "app.kite.WORK" -> model.perform(LaunchKind.WORK)
            "app.kite.CAR" -> model.perform(LaunchKind.CAR)
        }
        // The screenshot scripts, for the build's emulator only: on a real phone another app could
        // otherwise start Kite in a demo that mutes the voice.
        if (onEmulator) i.getStringExtra("demo")?.let { DemoScript.start(model, it) }
    }

    private val onEmulator: Boolean
        get() = android.os.Build.HARDWARE in setOf("ranchu", "goldfish") || android.os.Build.PRODUCT.startsWith("sdk_")

    /** The screen stays on while driving, like every sat nav. */
    fun keepScreenOn(on: Boolean) {
        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    companion object {
        /** One model for the app's life, so turning the phone or switching apps keeps everything as it was. */
        val model by lazy { AppModel() }
    }
}

@Composable
fun KiteScreen(model: AppModel, activity: MainActivity) {
    val ctx = activity
    val s = AppSettings
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val kiteMap = remember { KiteMap(model, ctx.applicationContext).also { DemoScript.kite = it } }
    val dark = LocalDark.current
    val scenery = remember(kiteMap) { MapboxScenery(model, kiteMap).also { kiteMap.scenery = it } }

    // The map's own location dot follows the same fixes the drive uses.
    DisposableEffect(Unit) {
        val modelUpdate = LocationService.onUpdate
        LocationService.onUpdate = { f -> modelUpdate?.invoke(f); kiteMap.pushFix(f) }
        model.glide.onMapPuck = { feature ->
            scenery.updateOverlay(NavGlide.PUCK) {
                feature?.toJson() ?: """{"type":"FeatureCollection","features":[]}"""
            }
        }
        onDispose {
            LocationService.onUpdate = modelUpdate
            model.glide.onMapPuck = null
            model.glide.cameraOutput = null
        }
    }
    val driving = model.nav?.route?.mode == app.kite.core.TravelMode.DRIVE
    val mapboxToken = s.activeMapboxToken
    val satellite = s.satellite
    val standardToken = mapboxToken.takeIf { s.standardMap && s.welcomed }
    LaunchedEffect(standardToken) { scenery.allowRetry() }
    val usableStandardToken = standardToken.takeUnless { scenery.failed }
    val standardReady = usableStandardToken != null && scenery.ready
    val showingMapbox = standardReady || kiteMap.showingMapbox
    val look = MapboxScenery.Look(dark, satellite, s.terrain3D, s.terrain, s.buildingShadows, s.streetLamps, s.traffic && !driving,
        if (dark) s.nightMapPalette else s.dayMapPalette)
    LaunchedEffect(look) { scenery.setLook(look) }
    LaunchedEffect(dark, driving, satellite, mapboxToken, standardReady) {
        kiteMap.applyBasemap(dark, driving, satellite && !standardReady, mapboxToken.takeUnless { standardReady })
    }
    LaunchedEffect(s.googleMapPlaces, s.openMapPlaces, s.hikingTrails, s.bikeTrails, s.transitLines, s.noGoogle, model.tab, model.nav, model.directions, model.selected, model.results) {
        kiteMap.refreshGooglePlaces()
        scenery.showTransit(s.transitLines && model.nav == null)
        LocationService.last?.let(scenery::updatePosition)
    }

    // Redraw the map's layers whenever anything they show changes.
    LaunchedEffect(Unit) {
        snapshotFlow {
            listOf(model.mapTick, model.results, model.selected?.id, model.directions, model.nav, model.stopSearch, model.measurement, model.nav?.routeWaze, model.nav?.roadControls, model.nav?.roadTraffic, model.openNowOnly, model.rating4Only,
                s.traffic, s.satellite, s.terrain, s.transitLines, s.speedCameras, s.plateCameras, s.wazeOnMap, s.wazeHeatmap,
                s.home, s.work, s.parking, s.saved, LocationService.authorized, model.tab,
                s.welcomed, s.noGoogle, s.surveillanceCameras, s.wazeOn, s.wazeKinds, s.wazeMaxAge,
                s.liveCams, s.liveRoadCams, s.liveWebcams, LiveCamStore.version,
                s.aheadSignals, s.aheadStops, s.aheadRail, s.aheadWaze, s.aheadCameras, s.aheadTraffic, s.roadWazeKinds)
        }.collect { kiteMap.render() }
    }
    // Kept on while driving; once arrived the phone goes in a pocket, so the screen may sleep (like the iPhone).
    val screenOn = model.nav?.let { !it.arrived } ?: false
    LaunchedEffect(screenOn) { activity.keepScreenOn(screenOn) }
    LaunchedEffect(s.wazeOn, s.wazeOnMap, s.wazeHeatmap) {
        if (!s.wazeOn) WazeWeb.shutDown()
        kiteMap.refreshWaze()
    }

    val ready = s.welcomed && !s.needsWazeChoice
    val perms = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { r ->
        LocationService.refreshPermission()
        if (r[Manifest.permission.ACCESS_FINE_LOCATION] == false && r[Manifest.permission.ACCESS_COARSE_LOCATION] == false) LocationService.denied = true
    }
    LaunchedEffect(ready) {
        if (!ready) return@LaunchedEffect
        LocationService.refreshPermission()
        if (!LocationService.authorized) {
            val list = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
            if (Build.VERSION.SDK_INT >= 33) list += Manifest.permission.POST_NOTIFICATIONS
            perms.launch(list.toTypedArray())
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        model.mapWidthDp = maxWidth.value
        model.mapHeightDp = maxHeight.value
        model.glide.heightDp = maxHeight.value
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { c -> KiteMapSurface(c, lifecycle, kiteMap, scenery, model) },
            onReset = null,
            onRelease = { it.dispose() },
            update = { it.show(usableStandardToken, standardReady, look) },
        )

        val nav = model.nav
        CompositionLocalProvider(LocalMapboxAttribution provides if (standardReady) scenery::openAttribution else null) {
            when {
                model.placingStop -> StopPinOverlay(model, showingMapbox) { scenery.centerPoint() ?: kiteMap.centerPoint() }
                model.stopSearch != null -> StopMapOverlay(model, showingMapbox)
                nav != null -> NavigationOverlay(model, nav, showingMapbox)
                model.directions != null -> DirectionsOverlay(model, showingMapbox)
                else -> when (model.tab) {
                    AppTab.MAP -> BrowseOverlay(model, showingMapbox)
                    AppTab.SAVED -> SavedPage(model)
                    AppTab.SETTINGS -> SettingsPage(model)
                }
            }
        }
        if (model.measurement != null && !model.placingStop && model.stopSearch == null && model.tab == AppTab.MAP) {
            DistanceMeasure(model, Modifier.align(androidx.compose.ui.Alignment.CenterStart))
        }
        val info = model.wazeInfo
        if (info != null && model.tab == AppTab.MAP && model.stopSearch == null && !model.placingStop) {
            val placement = if (nav == null) Modifier else Modifier.align(androidx.compose.ui.Alignment.Center)
            WazeInfoToast(model, info, placement)
        }
        val cam = model.liveCam
        if (cam != null && nav == null && model.tab == AppTab.MAP) {
            LiveCamCard(model, cam)
        }
    }

    model.surveillanceInfo?.let { cam ->
        val details = listOfNotNull(cam.operatorName?.let { "Operator: $it" }, cam.manufacturer?.let { "Manufacturer: $it" },
            cam.surveillance?.let { "Watches: $it" }, cam.mount?.let { "Mount: $it" }, cam.direction?.let { "Direction: $it" }).joinToString("\n")
        AlertDialog(onDismissRequest = { model.surveillanceInfo = null },
            confirmButton = { TextButton({ model.surveillanceInfo = null }) { Text("OK") } },
            title = { Text(if (cam.isALPR) "Plate reader" else "Surveillance camera") },
            text = { Text(details.ifEmpty { "Details not mapped in OpenStreetMap." }) })
    }
    if (model.showLayers) LayersSheet(model.wazeLiveCount) { model.showLayers = false }
    if (model.addingStop) StopPicker(model)
    model.picking?.let { PlacePicker(model, it) }
    model.streetView?.let { sv -> StreetViewScreen(sv) { model.streetView = null } }
    if (!s.welcomed || s.needsWazeChoice) {
        if (s.welcomed) WazeIntroScreen() else WelcomeScreen()
    }
    if (DemoScript.step == "icons") DemoIcons()
}
