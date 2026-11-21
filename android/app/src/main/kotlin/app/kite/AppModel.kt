package app.kite

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import app.kite.core.*
import kotlinx.coroutines.*
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.MapLibreMap
import kotlin.math.*

/** The dock's pages. */
enum class AppTab { MAP, SAVED, SETTINGS }

/** Which of your places the "pick a place" sheet is choosing. */
enum class PickKind { HOME, WORK }

enum class SheetDetent { PEEK, HALF, FULL }

enum class SortMode(val label: String) { RELEVANCE("Relevance"), DISTANCE("Distance"), RATING("Rating") }

/** What a home-screen shortcut asked the app to do once it's open. */
enum class LaunchKind { HOME, WORK, CAR }

data class Category(val label: String, val icon: ImageVector, val query: String) {
    companion object {
        /** British words where units are British: petrol, supermarkets, chemists, cash machines. */
        val all: List<Category> get() = if (Fmt.yards) british else american

        val british = listOf(
            Category("Restaurants", Icons.Filled.Restaurant, "restaurants"),
            Category("Coffee", Icons.Filled.LocalCafe, "coffee"),
            Category("Drinking water", Icons.Filled.WaterDrop, "drinking water"),
            Category("Petrol", Icons.Filled.LocalGasStation, "petrol station"),
            Category("Supermarkets", Icons.Filled.ShoppingCart, "supermarket"),
            Category("Pubs", Icons.Filled.SportsBar, "pub"),
            Category("Hotels", Icons.Filled.Hotel, "hotels"),
            Category("Parking", Icons.Filled.LocalParking, "car park"),
            Category("EV charging", Icons.Filled.EvStation, "ev charging station"),
            Category("Chemists", Icons.Filled.LocalPharmacy, "pharmacy"),
            Category("Cash machines", Icons.Filled.LocalAtm, "atm"),
        )
        val american = listOf(
            Category("Restaurants", Icons.Filled.Restaurant, "restaurants"),
            Category("Coffee", Icons.Filled.LocalCafe, "coffee"),
            Category("Drinking water", Icons.Filled.WaterDrop, "drinking water"),
            Category("Gas", Icons.Filled.LocalGasStation, "gas stations"),
            Category("Groceries", Icons.Filled.ShoppingCart, "grocery stores"),
            Category("Hotels", Icons.Filled.Hotel, "hotels"),
            Category("Parking", Icons.Filled.LocalParking, "parking"),
            Category("Pharmacies", Icons.Filled.LocalPharmacy, "pharmacy"),
            Category("ATMs", Icons.Filled.LocalAtm, "atm"),
        )
    }
}

/** Directions to one place: routes for every mode, the one picked, and where from. */
data class DirectionsState(
    val destination: Place,
    /** True when the trip goes from the place back to you. */
    val reversed: Boolean = false,
    val mode: TravelMode,
    val routes: Map<TravelMode, List<Route>> = emptyMap(),
    val loading: Set<TravelMode> = emptySet(),
    val errors: Map<TravelMode, String> = emptyMap(),
    val selected: Int = 0,
    /** Places to stop at on the way, in order. */
    val stops: List<Place> = emptyList(),
    /** The Transit tab is showing (its trips come from Transitous, not the road routers). */
    val transit: Boolean = false,
    val trips: List<TransitTrip>? = null,
    val tripsError: String? = null,
    /** Null for "leave now". */
    val transitTime: Long? = null,
    val arriveBy: Boolean = false,
    val trip: Int = 0,
    val start: Place? = null,
) {
    fun orderedPlaces(): List<Place?> =
        if (reversed) listOf(destination) + stops.asReversed() + listOf(null)
        else listOf(start) + stops + destination

    fun endpoints(current: LatLng?): Pair<LatLng?, LatLng?> =
        if (reversed) destination.location to current else (start?.location ?: current) to destination.location

    val current: List<Route> get() = if (transit) emptyList() else routes[mode] ?: emptyList()
    val route: Route? get() = current.getOrNull(selected) ?: current.firstOrNull()
    val pickedTrip: TransitTrip? get() = if (transit) trips?.let { it.getOrNull(trip) ?: it.firstOrNull() } else null
}

/** The whole app's state; the map and every sheet read it. */
class AppModel {
    val settings = AppSettings
    val location = LocationService
    val scope = MainScope()

    var query by mutableStateOf("")
    /** Autocomplete while typing: Google's, or OpenStreetMap's without Google. */
    var suggestions by mutableStateOf(SuggestParser.Result())
    private var suggestTask: Job? = null
    var results by mutableStateOf<List<Place>>(emptyList())
    var resultsTitle by mutableStateOf("")
    var selected by mutableStateOf<Place?>(null)
    var searching by mutableStateOf(false)
    var notice by mutableStateOf<String?>(null)
    var detent by mutableStateOf(SheetDetent.HALF)
    var openNowOnly by mutableStateOf(false)
    var rating4Only by mutableStateOf(false)
    var sort by mutableStateOf(SortMode.RELEVANCE)
    var directions by mutableStateOf<DirectionsState?>(null)
    var nav by mutableStateOf<Navigator?>(null)
    var transitGuidance by mutableStateOf<TransitGuidance?>(null)
        private set
    private var transitWalkJob: Job? = null
    private var transitOverviewJob: Job? = null
    private var transitBoardJob: Job? = null
    private var transitClockJob: Job? = null
    private var transitDeparturesJob: Job? = null
    private var transitCameraAt = 0L
    var showLayers by mutableStateOf(false)
    var tab by mutableStateOf(AppTab.MAP)
    /** Live Waze reports in view, for the "Live from Waze" chip; null until Waze answers. */
    var wazeLiveCount by mutableStateOf<Int?>(null)
    /** The police risk around you (0 to 100), for the chip on the map. */
    var areaRisk by mutableStateOf<Int?>(null)
    /** A Waze report tapped on the map, shown in a small card. */
    var wazeInfo by mutableStateOf<WazeAlert?>(null)
    var surveillanceInfo by mutableStateOf<SurveillanceCamera?>(null)
    /** The live camera whose photo is open (tapped on the map or in a route's camera row). */
    var liveCam by mutableStateOf<LiveCam?>(null)
    /** The route's cameras in order, when the open one was picked from the route's row (for next/previous). */
    var liveCamRoute by mutableStateOf<List<LiveCam>>(emptyList())
    /** The "Add stop" search sheet. */
    var addingStop by mutableStateOf(false)
    var placingStop by mutableStateOf(false)
        private set
    var measurement by mutableStateOf<Pair<LatLng, LatLng>?>(null)
    fun beginStopPin() {
        addingStop = false
        stopPinWasFollowing = stopSearch?.wasFollowing ?: (nav?.following == true)
        closeStopSearch(restore = false)
        nav?.following = false
        browseFollowing = false
        placingStop = true
    }

    private var stopPinWasFollowing = false
    fun finishStopPin(at: LatLng? = null) {
        placingStop = false
        if (at != null) acceptStop(StopCandidate(Place("pin:${at.lat},${at.lng}", "Dropped pin", at, "pin"), null, 0.0))
        if (stopPinWasFollowing && nav != null) recenterNav()
        else if (at == null && nav == null) frameRoute()
        stopPinWasFollowing = false
    }
    var stopSearch by mutableStateOf<StopSearch?>(null)
        private set
    private var stopSearchJob: Job? = null
    var picking by mutableStateOf<PickKind?>(null)
    var showSteps by mutableStateOf(false)
    /** "Start" on a place: begin the drive as soon as its route arrives. */
    var autoStart by mutableStateOf(false)
    /** A drive that was under way when the app last closed, offered again on the home map. */
    var resumeOffer by mutableStateOf<SavedTrip?>(null)
    private var tripSavedAt = 0L
    /** Bumped when the map should redraw overlays that don't come from a state value. */
    var mapTick by mutableIntStateOf(0)
    /** Which way the map faces, for the compass button. */
    var mapHeading by mutableStateOf(0.0)
    /**
     * The browse map's 3D, 2D or north-up button. North up is the map as it always was; 3D and 2D
     * follow you round like the driving map, without a route. Starts north up each time Kite opens.
     */
    var browseLook by mutableStateOf(MapLook.NORTH)
    /** Whether the browse map is following you in 3D or 2D; dragging the map stops it. */
    var browseFollowing by mutableStateOf(false)
    /** Street View opened from a place. */
    var streetView by mutableStateOf<StreetViewRequest?>(null)

    var map: MapLibreMap? = null
        set(v) { field = v; glide.map = v }
    /** The map view's size in dp, for framing. */
    var mapWidthDp = 400f
    var mapHeightDp = 800f
    /** Moves the nav arrow and camera every frame between GPS fixes. */
    val glide = NavGlide()
    private var routesRequest = 0
    private var transitRequest = 0
    private var transitLoadedAt = 0L
    private var searchTask: Job? = null

    init {
        location.onUpdate = { locationChanged(it) }
        // A drive cut short (the app closed, the phone restarted): offer it again, for two hours.
        settings.trip?.let { t ->
            if (!DemoScript.active && System.currentTimeMillis() - t.atMillis < 2 * 3600_000L) resumeOffer = t else settings.trip = null
        }
    }

    /** "Carry on": the same place, stops and way of travelling, started as soon as the route arrives. */
    fun resumeTrip() {
        val t = resumeOffer ?: return
        resumeOffer = null
        settings.trip = null
        selected = null
        results = emptyList()
        directions = DirectionsState(destination = t.destination, mode = TravelMode.entries.firstOrNull { it.raw == t.mode } ?: TravelMode.DRIVE,
            stops = t.stops)
        detent = SheetDetent.HALF
        autoStart = true
        loadAllModes()
    }

    fun dismissResume() {
        resumeOffer = null
        settings.trip = null
    }

    private fun rememberTrip(n: Navigator) {
        tripSavedAt = System.currentTimeMillis()
        settings.trip = SavedTrip(n.destination, n.stops, n.route.mode.raw, tripSavedAt)
    }

    fun edit(f: (DirectionsState) -> DirectionsState) { directions?.let { directions = f(it) } }

    val userLatLng: LatLng? get() = location.last?.coord

    // Search

    val visibleResults: List<Place>
        get() {
            var r = results
            if (openNowOnly) r = r.filter { it.openNow == true }
            if (rating4Only) r = r.filter { (it.rating ?: 0.0) >= 4 }
            return when (sort) {
                SortMode.RELEVANCE -> r
                SortMode.DISTANCE -> r.sortedBy { it.distanceMeters ?: Double.MAX_VALUE }
                SortMode.RATING -> r.sortedByDescending { it.rating ?: 0.0 }
            }
        }

    val viewport: Pair<LatLng, Double?>
        get() {
            val m = map ?: return Pair(userLatLng ?: LatLng(51.5074, -0.1278), null)
            val c = m.cameraPosition.target ?: return Pair(userLatLng ?: LatLng(51.5074, -0.1278), null)
            val b = m.projection.visibleRegion.latLngBounds
            val span = LatLng(b.latitudeSouth, b.longitudeWest).distanceTo(LatLng(b.latitudeNorth, b.longitudeEast)) / 1.4
            val center = LatLng(c.latitude, c.longitude)
            // A world view provides little local context for addresses or nearby businesses.
            val here = userLatLng
            if (here != null && (span > 120_000 || center == LatLng(51.5074, -0.1278))) return Pair(here, 20_000.0)
            return Pair(center, span.takeIf { it.isFinite() && it > 0 }?.coerceIn(1_500.0, 120_000.0))
        }

    fun search(text: String? = null, title: String? = null) {
        val q = (text ?: query).trim()
        if (q.isEmpty()) return
        if (title == null && MapLinks.looksLikeLink(q)) { openLink(q); return }
        query = title ?: q
        settings.addRecent(title ?: q)
        searchTask?.cancel()
        selected = null
        directions = null
        searching = true
        notice = null
        openNowOnly = false
        rating4Only = false
        sort = SortMode.RELEVANCE
        val vp = viewport
        val useGoogle = !settings.noGoogle
        val user = userLatLng
        searchTask = scope.launch {
            val r = PlaceSearch.search(q, vp.first, vp.second, useGoogle)
            // Cleared or replaced while it was loading: leave the screen to the newer one.
            ensureActive()
            val radius = ((vp.second ?: 20_000.0) * 0.6).coerceIn(5_000.0, 30_000.0)
            var places = r.places.filter { it.location.distanceTo(vp.first) <= radius }
            if (places.isEmpty() && OutdoorData.kind(q) == null)
                places = PlaceSearch.namedNearby(q, vp.first, radius * 2, useGoogle)
                    .filter { it.location.distanceTo(vp.first) <= radius }
            if (places.isEmpty()) {
                // A named town or an exact address is a destination, even outside the local business search.
                val name = Place.fold(q)
                places = r.places.filter {
                    val category = Place.fold(it.category.orEmpty())
                    it.source == "postcodes.io" ||
                        Place.fold(it.name) == name && (category in geographicSearchCategories || q.any(Char::isDigit) && category == "address")
                }.take(1)
            }
            ensureActive()
            places = places.sortedBy { it.location.distanceTo(vp.first) }
            if (user != null) places = places.map { it.copy(distanceMeters = user.distanceTo(it.location)) }
            searching = false
            resultsTitle = title ?: q
            results = places
            if (places.isEmpty()) {
                notice = Connectivity.explain("No results for \"$q\" here. Try another word, or move the map.")
            } else if (r.googleError != null && useGoogle) {
                notice = "Google didn't answer, so these results are from OpenStreetMap."
            }
            if (places.size == 1) select(places[0]) else {
                detent = SheetDetent.HALF
                frame(places.take(8).map { it.location })
            }
        }
    }

    fun typed(text: String) {
        suggestTask?.cancel()
        val q = text.trim()
        if (q.length < 2 || MapLinks.looksLikeLink(q)) { suggestions = SuggestParser.Result(); return }
        val vp = viewport
        val useGoogle = !settings.noGoogle
        val user = userLatLng
        suggestTask = scope.launch {
            delay(250)
            var places = emptyList<Place>()
            var queries = emptyList<String>()
            if (useGoogle) {
                runCatching { GoogleClient.shared.suggest(q, vp.first, vp.second ?: 20_000.0) }.getOrNull()?.let {
                    places = it.places; queries = it.queries
                }
            }
            places = PlaceSearch.nearFirst(places, vp.first)
            if (places.isEmpty()) Postcodes.lookup(q)?.let { places = listOf(it) }
            if (PlaceSearch.needsNearbyFallback(places, vp.first)) {
                val open = runCatching { Photon.search(q, vp.first, 8) }.getOrDefault(emptyList())
                places = PlaceSearch.withNearbyFallback(places, open, vp.first)
            }
            ensureActive()
            if (user != null) places = places.map { it.copy(distanceMeters = user.distanceTo(it.location)) }
            val was = suggestions
            suggestions = SuggestParser.Result(
                SuggestParser.steady(places, was.places) { it.id },
                SuggestParser.steady(queries, was.queries) { it },
            )
        }
    }

    /** A pasted Google Maps, Waze or Apple Maps link (or coordinates): show the spot it points at. */
    fun openLink(text: String) {
        searchTask?.cancel()
        suggestTask?.cancel()
        suggestions = SuggestParser.Result()
        selected = null
        directions = null
        results = emptyList()
        notice = null
        searching = true
        query = "Opening link…"
        searchTask = scope.launch {
            val target = runCatching { MapLinks.resolve(text) }.getOrNull()
            searching = false
            when (target) {
                is MapLinks.Target.Spot -> if (target.name != null) {
                    query = target.name!!
                    resolve(Place(id = "link:${target.at.lat},${target.at.lng}", name = target.name!!, location = target.at, source = "osm"))
                } else {
                    // Keep where it is in the box, not an empty "Where to?" as if nothing was found.
                    query = String.format(java.util.Locale.US, "%.5f, %.5f", target.at.lat, target.at.lng)
                    dropPin(target.at, "Shared location")
                }
                is MapLinks.Target.Search -> {
                    target.near?.let { n -> map?.moveCamera(CameraUpdateFactory.newLatLngZoom(org.maplibre.android.geometry.LatLng(n.lat, n.lng), 14.0)) }
                    search(target.text)
                }
                null -> {
                    query = ""
                    notice = Connectivity.explain("Couldn't find a location in that link.")
                }
            }
        }
    }

    /** A place picked from the suggestions: show it now, then fill in its details from Google. */
    fun openSuggestion(place: Place) {
        suggestTask?.cancel()
        searchTask?.cancel()
        searching = false
        notice = null
        settings.addRecent(place.name)
        query = place.name
        results = emptyList()
        directions = null
        resolve(place)
    }

    fun clearSearch() {
        searchTask?.cancel()
        query = ""
        results = emptyList()
        resultsTitle = ""
        selected = null
        searching = false
        notice = null
    }

    fun select(place: Place, focus: Boolean = true) {
        var p = place
        settings.addRecentPlace(place)
        if (p.distanceMeters == null) userLatLng?.let { p = p.copy(distanceMeters = it.distanceTo(p.location)) }
        selected = p
        detent = SheetDetent.HALF
        if (!focus) return
        val m = map ?: return
        browseFollowing = false
        browseLook = MapLook.NORTH
        val zoom = max(MapCam.zoomFor(900.0, p.location.lat, mapWidthDp), min(m.cameraPosition.zoom, 18.0).let { if (it > 16) it else 0.0 })
        MapCam.animate(m, CameraPosition.Builder().target(p.location.ml()).zoom(zoom).tilt(0.0).bearing(0.0).build(),
            padding = intArrayOf(0, 120, 0, (mapHeightDp * 0.45f).toInt()), ms = 600)
    }

    fun closePlace() {
        selected = null
        if (results.isNotEmpty()) detent = SheetDetent.HALF
    }

    /** A tap on a place the basemap draws: look it up on Google by name at that spot. */
    fun resolveTapped(name: String, point: LatLng, category: String?, source: String) {
        resolve(Place(id = "tap:${point.lat},${point.lng}", name = name, location = point, source = source, category = category))
    }

    /** Show [placeholder] right away, then swap in Google's full place found at the same spot. */
    private fun resolve(placeholder0: Place) {
        val point = placeholder0.location
        val placeholder = placeholder0.copy(distanceMeters = userLatLng?.distanceTo(point))
        select(placeholder, focus = !placeholder.id.startsWith("tap:"))
        if (settings.noGoogle) return
        val q = listOfNotNull(placeholder.name, placeholder.address).joinToString(" ")
        val pid = placeholder.id
        scope.launch {
            val found = runCatching { GoogleClient.shared.search(q, point, 1_000.0, pages = 1) }.getOrDefault(emptyList())
            if (selected?.id != pid) return@launch
            // The same place by name too, not just the nearest: a café next door mustn't take its place.
            val best = found.filter { it.location.distanceTo(point) < 150 && similarNames(it.name, placeholder.name) }
                .minByOrNull { it.location.distanceTo(point) } ?: return@launch
            var b = best
            if (pid.startsWith("tap:")) b = b.copy(location = point)
            b = b.copy(distanceMeters = userLatLng?.distanceTo(b.location))
            selected = b
            settings.addRecentPlace(b)
        }
    }

    /**
     * A saved place: its "Open · Closes 10 pm" was true the day it was saved, not now. Show it
     * without that, then fill in today's from Google (left out with no internet).
     */
    fun openSaved(saved: Place) {
        val p = saved.copy(statusText = null, openNow = null)
        select(p)
        if (settings.noGoogle) return
        val q = listOfNotNull(p.name, p.address).joinToString(" ")
        scope.launch {
            val found = runCatching { GoogleClient.shared.search(q, p.location, 1_000.0, pages = 1) }.getOrDefault(emptyList())
            val fresh = found.firstOrNull { it.location.distanceTo(p.location) < 150 && similarNames(it.name, p.name) } ?: return@launch
            if (selected?.id == p.id) selected = selected?.copy(statusText = fresh.statusText, openNow = fresh.openNow,
                hours = fresh.hours, permanentlyClosed = fresh.permanentlyClosed)
        }
    }

    /** "Costa" and "Costa Coffee", "St Mary's Church" and "St. Mary's": every word of one name is in the other. */
    private fun similarNames(a: String, b: String): Boolean {
        fun words(s: String) = java.text.Normalizer.normalize(s.lowercase(), java.text.Normalizer.Form.NFD)
            .replace(Regex("\\p{M}"), "").split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
        val x = words(a); val y = words(b)
        if (x.isEmpty() || y.isEmpty()) return false
        // Whole words, so "Costa" isn't "Costas" and "Royal Hotel" isn't "Royal Cafe".
        return y.containsAll(x) || x.containsAll(y)
    }

    // My places

    /** A home-screen shortcut: directions home or to work, or back to the car. */
    fun perform(kind: LaunchKind) {
        scope.launch {
            repeat(20) { if (userLatLng == null) delay(250) }
            val target = when (kind) {
                LaunchKind.HOME -> settings.home
                LaunchKind.WORK -> settings.work
                LaunchKind.CAR -> settings.parking
            }
            if (target == null) {
                if (kind == LaunchKind.CAR) { nav?.say("No parking spot saved yet.") ?: run { notice = "No parking spot saved yet. Tap P on the map when you park." } }
                // Mid-drive, keep the trip going: a picker on top of it, cancelled, would lose it.
                else if (nav != null) nav?.say("No ${if (kind == LaunchKind.HOME) "home" else "work"} address saved yet. Set it in Saved after this drive.")
                else picking = if (kind == LaunchKind.HOME) PickKind.HOME else PickKind.WORK
                return@launch
            }
            // Only now that there's somewhere to go does the current drive end.
            if (nav != null) endNavigation()
            openDirections(target)
            if (kind == LaunchKind.CAR) edit { it.copy(mode = TravelMode.WALK) }
        }
    }

    /** Home, work, the parked car or a saved place, by id, for a tap on its map icon. */
    fun myPlace(id: String): Place? =
        listOfNotNull(settings.home, settings.work, settings.parking).firstOrNull { it.id == id } ?: settings.saved.firstOrNull { it.id == id }

    fun setHome(p: Place?) {
        settings.home = p?.copy(distanceMeters = null)
        if (p != null) notice = "Saved as your home."
    }

    fun setWork(p: Place?) {
        settings.work = p?.copy(distanceMeters = null)
        if (p != null) notice = "Saved as your work."
    }

    /** Remember where the car is: here, now, with the street name when one is found. */
    fun saveParking() {
        val me = userLatLng ?: run {
            notice = if (location.denied) "Location is off for Kite. Turn it on in Settings to save where you parked."
            else "Still finding your location. Try again in a moment."
            return
        }
        val p = Place(id = "parking:${System.currentTimeMillis() / 1000}", name = "Parked car", location = me, source = "osm",
            category = "Parked at ${Fmt.time(java.util.Date())}")
        settings.parking = p
        notice = "Parking spot saved. Tap the P button to find your car."
        scope.launch {
            val found = Photon.reverse(me) ?: return@launch
            if (settings.parking?.id != p.id) return@launch
            settings.parking = settings.parking?.copy(address = listOfNotNull(found.name, found.address).joinToString(", "))
        }
    }

    fun clearParking() {
        if (selected?.id == settings.parking?.id) selected = null
        settings.parking = null
    }

    /** Long press: a dropped pin with the address there. */
    fun dropPin(point: LatLng, name: String = "Dropped pin") {
        val pin = Place(id = "pin:${point.lat},${point.lng}", name = name, location = point, source = "osm",
            category = String.format(java.util.Locale.US, "%.5f, %.5f", point.lat, point.lng))
        select(pin)
        scope.launch {
            val found = Photon.reverse(point) ?: return@launch
            if (selected?.id != pin.id) return@launch
            selected = pin.copy(address = listOfNotNull(found.name, found.address).joinToString(", "))
        }
    }

    // Directions

    fun openDirections(place: Place, mode: TravelMode = settings.defaultMode) {
        closeStopSearch(restore = false)
        addingStop = false
        if (resumeOffer != null) dismissResume()
        autoStart = false
        directions = DirectionsState(destination = place, mode = mode)
        detent = SheetDetent.HALF
        loadAllModes()
    }

    fun closeDirections() {
        closeStopSearch(restore = false)
        autoStart = false
        directions = null
        showSteps = false
        selected?.let { select(it) }
    }

    fun reverseDirections() {
        directions?.let { reorderPlan(it.orderedPlaces().asReversed()) }
    }

    fun moveWaypoint(index: Int, step: Int) {
        val places = directions?.orderedPlaces()?.toMutableList() ?: return
        val target = index + step
        if (index !in places.indices || target !in places.indices) return
        val item = places.removeAt(index)
        places.add(target, item)
        reorderPlan(places)
    }

    private fun reorderPlan(places: List<Place?>) {
        val d = directions ?: return
        if (places.size < 2) return
        val middle = places.drop(1).dropLast(1)
        val snap = if (middle.any { it == null }) currentWaypoint() ?: return else null
        val orderedStops = middle.mapNotNull { it ?: snap }
        val from = places.first()
        val to = places.last()
        val updated = if (to == null && from != null) {
            d.copy(destination = from, reversed = true, start = null, stops = orderedStops.asReversed())
        } else if (to != null) {
            d.copy(destination = to, reversed = false, start = from, stops = orderedStops)
        } else return
        directions = updated
        reloadRoutes()
    }

    private fun currentWaypoint(): Place? = userLatLng?.let {
        Place("waypoint:${it.lat},${it.lng}", "Your location", it, "pin")
    }

    fun routePlan(name: String): SavedPlan? {
        val d = directions ?: return null
        val points = d.orderedPlaces().map { it ?: currentWaypoint() ?: return null }
        return SavedPlan(name.trim().ifEmpty { "${points.first().name} → ${points.last().name}" }, points, d.mode, transit = d.transit)
    }

    fun openSavedPlan(plan: SavedPlan) {
        tab = AppTab.MAP
        clearSearch()
        closeStopSearch(restore = false)
        addingStop = false
        autoStart = false
        val first = plan.points.first()
        directions = DirectionsState(plan.points.last(), mode = plan.mode,
            stops = plan.points.drop(1).dropLast(1), start = first, transit = plan.transit)
        detent = SheetDetent.HALF
        loadAllModes()
    }

    fun setMode(m: TravelMode) {
        edit { it.copy(transit = false, mode = m, selected = 0) }
        settings.defaultMode = m
        frameRoute()
    }

    fun searchStops(query: String, named: Boolean = false, parking: Boolean = false) {
        val q = query.trim()
        if (q.isEmpty()) return
        val driving = nav
        val d = directions
        val route = driving?.route ?: d?.route
        val endpoints = d?.endpoints(userLatLng)
        val origin = endpoints?.first ?: userLatLng ?: viewport.first
        val line = route?.polyline?.takeIf { it.size >= 2 } ?: listOf(origin, endpoints?.second ?: origin)
        val cum = Geo.cumulative(line)
        val start = (driving?.progress?.alongMeters ?: 0.0).coerceIn(0.0, cum.last())
        val end = if (driving == null) cum.last() else min(cum.last(), start + 42_000.0)
        val span = end - start
        val existing = driving?.stops ?: d?.stops.orEmpty()
        val destinationId = (driving?.destination ?: d?.orderedPlaces()?.lastOrNull())?.id
        val useGoogle = settings.welcomed && !settings.noGoogle
        val search = StopSearch(q, wasFollowing = stopSearch?.wasFollowing ?: (driving?.following == true), parking = parking)
        stopSearchJob?.cancel()
        stopSearch = search
        addingStop = false
        driving?.following = false
        map?.cancelTransitions()
        stopSearchJob = scope.launch {
            val results = withContext(Dispatchers.Default) {
                if (parking && driving != null) {
                    val target = driving.destination.location
                    val places = coroutineScope {
                        val osm = async { OutdoorData.find(OutdoorData.PARKING, target, 1400.0).orEmpty() }
                        val google = async { if (useGoogle) PlaceSearch.namedNearby("parking", target, 2800.0, true) else emptyList() }
                        OutdoorData.combine(google.await(), osm.await())
                    }
                    return@withContext places.map { StopCandidate(it, null, target.distanceTo(it.location)) }
                        .filter { it.offset <= 1500 && it.place.id != destinationId }.sortedBy { it.offset }.take(20)
                }
                val count = ceil(span / (if (driving == null) 27_000 else 14_000)).toInt()
                    .coerceIn(1, if (driving == null) 72 else 3)
                val window = Geo.slice(line, start, end, cum)
                val windowCum = Geo.cumulative(window)
                val found = (0 until count).chunked(4).flatMap { batch ->
                    coroutineScope {
                        batch.map { i ->
                            async {
                                val center = if (span > 0) Geo.point(line, start + span * (i + 0.5) / count, cum) else origin
                                val width = max(4_000.0, span / count * 1.65)
                                if (named) PlaceSearch.namedNearby(q, center, width, useGoogle)
                                else PlaceSearch.search(q, center, width, useGoogle).places
                            }
                        }.awaitAll().flatten()
                    }
                }
                val candidates = found.mapNotNull { p ->
                    if (p.id == destinationId || existing.any(p::matchesNearby)) return@mapNotNull null
                    if (span <= 1 || window.size < 2) {
                        val distance = origin.distanceTo(p.location)
                        return@mapNotNull if (distance < 3500) StopCandidate(p, null, distance) else null
                    }
                    val at = Geo.project(p.location, window, windowCum)
                    val corridor = if (named) 5_000.0 else 2_200.0
                    if (at.offset > corridor || (driving != null && at.along < 30 && !named)) return@mapNotNull null
                    StopCandidate(p, at.along, at.offset, start + at.along)
                }
                val ranked = if (driving != null || span <= 42_000) candidates.sortedBy { (it.ahead ?: 0.0) + it.offset * 3 }
                    else {
                        val bands = candidates.groupBy { ((it.ahead ?: 0.0) / (span / 30).coerceAtLeast(28_000.0)).toInt() }
                        bands.values.flatMap { group -> group.sortedBy { it.offset }.take(3) }.sortedBy { it.ahead }
                    }
                buildList<StopCandidate> {
                    for (p in ranked) {
                        if (none { it.place.matchesNearby(p.place) }) add(p)
                        if (size == 100) break
                    }
                }
            }
            if (stopSearch !== search) return@launch
            if (nav !== driving || directions?.destination?.id != d?.destination?.id) {
                closeStopSearch(restore = false)
                return@launch
            }
            if (driving != null && driving.route.id != route?.id) {
                searchStops(q, named, parking)
                return@launch
            }
            stopSearch = search.copy(loading = false, results = results)
            if (results.isNotEmpty()) {
                val first = if (parking) driving?.destination?.location ?: origin
                    else if (span > 0) Geo.point(line, start, cum) else origin
                val visible = if (driving == null && span > 42_000) results else results.take(7)
                frame(listOf(first) + visible.map { it.place.location }, bottomFraction = 0.27f, top = 125)
            }
        }
    }

    fun selectStopPin(id: String?) {
        val search = stopSearch ?: return
        val selected = search.results.firstOrNull { it.place.id == id }
        if (search.selected != selected) stopSearch = search.copy(selected = selected)
    }

    fun showStopPin(candidate: StopCandidate) {
        selectStopPin(candidate.place.id)
        frame(listOf(candidate.place.location), bottomFraction = 0.27f, top = 125)
    }

    fun closeStopSearch(restore: Boolean = true) {
        val search = stopSearch ?: return
        stopSearchJob?.cancel()
        stopSearch = null
        if (restore) {
            if (search.wasFollowing && nav != null) recenterNav()
            else if (nav == null) frameRoute()
        }
    }

    fun acceptStop(candidate: StopCandidate) {
        val driving = nav
        if (driving != null && stopSearch?.parking == true) {
            closeStopSearch()
            driving.parkAt(candidate.place)
            return
        }
        val route = driving?.route ?: directions?.route
        val existing = driving?.stops ?: directions?.orderedPlaces()?.drop(1)?.dropLast(1)?.filterNotNull().orEmpty()
        val along = candidate.routeMeters
        val cum = route?.let { Geo.cumulative(it.polyline) }
        val idx = if (along == null || route == null || cum == null) (if (driving != null) 0 else existing.size) else {
            existing.indexOfFirst { Geo.project(it.location, route.polyline, cum).along > along }
                .takeIf { it >= 0 } ?: existing.size
        }
        closeStopSearch(restore = driving != null)
        if (driving != null) driving.addStop(candidate.place, idx) else addStop(candidate.place, idx)
        addingStop = false
    }

    fun addStop(p: Place, index: Int = directions?.stops?.size ?: 0) {
        val d = directions ?: return
        if (d.stops.size >= 8) return
        val insertion = (if (d.reversed) d.stops.size - index else index).coerceIn(0, d.stops.size)
        edit { it.copy(stops = it.stops.toMutableList().apply { add(insertion, p) }) }
        reloadRoutes()
    }

    fun removeStop(i: Int) {
        val d = directions ?: return
        if (i !in d.stops.indices) return
        val index = if (d.reversed) d.stops.lastIndex - i else i
        edit { it.copy(stops = it.stops.filterIndexed { j, _ -> j != index }) }
        reloadRoutes()
    }

    /** 0 leave now, 1 depart at, 2 arrive by. */
    fun setTransitTime(kind: Int, atMillis: Long) {
        edit { it.copy(transitTime = if (kind == 0) null else atMillis, arriveBy = kind == 2) }
        loadTransit()
    }

    fun showTransit() {
        edit { it.copy(transit = true) }
        // "Leave now" times found a while ago may have left already: look again.
        if (directions?.transitTime == null && System.currentTimeMillis() - transitLoadedAt > 120_000) loadTransit()
        frameRoute()
    }

    fun selectTrip(i: Int) { edit { it.copy(trip = i) }; frameRoute() }

    fun selectRoute(i: Int) { edit { it.copy(selected = i) }; mapTick++ }

    fun reloadRoutes() {
        if (directions == null) return
        edit { it.copy(routes = emptyMap(), errors = emptyMap(), selected = 0) }
        loadAllModes()
    }

    private fun loadAllModes() {
        val d = directions ?: return
        val (from, to) = d.endpoints(userLatLng)
        if (from == null || to == null) {
            val why = if (location.denied) LOCATION_OFF_TEXT
                else if (location.systemOff) "Location is off on this phone. Turn it on in Settings to get directions from where you are."
                else "Waiting for your location…"
            edit { it.copy(errors = TravelMode.entries.associateWith { why }, tripsError = why, trips = emptyList()) }
            if (!location.denied) {
                location.start()
                scope.launch {
                    repeat(40) { if (userLatLng == null) delay(250) }
                    if (userLatLng != null && directions?.destination?.id == d.destination.id && directions?.routes?.isEmpty() == true) reloadRoutes()
                }
            }
            return
        }
        val via = (if (d.reversed) d.stops.reversed() else d.stops).map { it.location }
        routesRequest++
        val req = routesRequest
        val hw = settings.avoidHighways; val tolls = settings.avoidTolls; val google = !settings.noGoogle
        // Already driving (asked at a red light, say): no route that starts with a U-turn.
        val moving = location.last?.let { l -> if (l.speed >= 4 && l.courseKnown) l.course else null }
        val heading = if (d.reversed || d.start != null) null else moving
        val mapboxToken = settings.activeMapboxToken
        for (m in TravelMode.entries) {
            edit { it.copy(loading = it.loading + m) }
            scope.launch {
                val r = runCatching {
                    Directions.routes(from, to, m, hw, tolls, google, via, if (m == TravelMode.DRIVE) heading else null,
                        alternatives = true, mapboxToken = mapboxToken)
                }.getOrElse { Directions.Result(emptyList(), it.message) }
                if (directions?.destination?.id != d.destination.id || routesRequest != req) return@launch
                edit {
                    var e = it.errors
                    if (r.routes.isEmpty()) e = e + (m to Connectivity.explain(
                        if (r.error == "No route found.") "No route found." else "Couldn't get a route just now. Try again in a moment."))
                    // The fastest first, so it's the one picked (a bike route marked "Slower route" was picked
                    // while one 5 min faster sat below it).
                    it.copy(loading = it.loading - m, routes = it.routes + (m to r.routes.sortedBy { x -> x.durationSeconds }), errors = e)
                }
                if (m == directions?.mode) {
                    frameRoute()
                    if (autoStart && r.routes.isNotEmpty()) {
                        autoStart = false
                        startNavigation()
                    }
                }
            }
        }
        loadTransit()
    }

    /** Transit trips for the current trip, leaving now or at the picked time. */
    fun loadTransit() {
        val d = directions ?: return
        val (from, to) = d.endpoints(userLatLng)
        if (from == null || to == null) return
        transitLoadedAt = System.currentTimeMillis()
        // A new request either way, so one still loading can't put back trips without the stops.
        transitRequest++
        // The planner can't go via stops: rather say so than show trains for a different trip.
        if (d.stops.isNotEmpty()) {
            edit { it.copy(trips = emptyList(), tripsError = "Public transport can't go via stops. Remove the stops to see trains and buses.") }
            return
        }
        val destId = d.destination.id
        val req = transitRequest
        edit { it.copy(trips = null, tripsError = null, trip = 0) }
        scope.launch {
            try {
                val trips = Transitous.plan(from, to, d.transitTime, d.arriveBy)
                if (directions?.destination?.id != destId || transitRequest != req) return@launch
                edit { it.copy(trips = trips, tripsError = if (trips.isEmpty()) "No transit trips found here." else null) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (directions?.destination?.id != destId || transitRequest != req) return@launch
                edit { it.copy(trips = emptyList(), tripsError = Connectivity.explain("Couldn't reach the transit planner.")) }
            }
            if (directions?.transit == true) frameRoute()
        }
    }

    fun frameRoute() {
        directions?.pickedTrip?.let { t ->
            if (t.path.size >= 2) frame(t.path, bottomFraction = 0.42f)
            mapTick++
            return
        }
        val r = directions?.route ?: run { mapTick++; return }
        frame(r.polyline, bottomFraction = 0.42f, top = 170 + (directions?.stops?.size ?: 0) * 42)
    }

    /** Police risk within about a kilometre of you, from remembered and live Waze police reports. */
    fun updateAreaRisk(live: List<WazeAlert>) {
        val fix = location.last
        if (!settings.wazeOn || !settings.policeRisk || !settings.wazePolice || location.reducedAccuracy || fix == null ||
            fix.accuracy > 200 || fix.ageMs > 120_000) { areaRisk = null; return }
        val here = fix.coord
        val d = 0.0096 / max(cos(here.lat * PI / 180), 0.2) * 0.62
        val line = listOf(LatLng(here.lat, here.lng - d), LatLng(here.lat, here.lng + d))
        val near = live.count { it.kind == WazeAlert.Kind.POLICE && it.location.distanceTo(here) < 1_500 }
        areaRisk = PoliceRisk.score(line, WazeHistory.reports, near, radius = 900.0)
    }

    // Navigation

    private var navZoomSteps = 0

    fun startTransitNavigation() {
        val d = directions ?: return
        val trip = d.pickedTrip?.takeIf { it.legs.isNotEmpty() } ?: return
        if (d.reversed || nav != null || transitGuidance != null) return
        val session = TransitGuidance(trip, d.destination)
        transitGuidance = session
        location.last?.let { session.observe(it) }
        settings.trip = null
        resumeOffer = null
        location.setNavigating(true)
        DriveService.start(KiteApp.app, "Using transit with Kite")
        transitClockJob = scope.launch {
            while (transitGuidance === session && session.phase != TransitGuidance.Phase.COMPLETE) {
                delay(5_000)
                session.tick(System.currentTimeMillis())
            }
        }
        session.prepareLeg()
        setTransitLeg(session)
    }

    private fun setTransitLeg(session: TransitGuidance) {
        stopTransitOverview()
        transitWalkJob?.cancel()
        transitBoardJob?.cancel()
        transitDeparturesJob?.cancel()
        nav?.stop()
        nav = null
        glide.stop()
        transitCameraAt = 0
        val leg = session.leg
        if (leg == null) {
            location.setNavigating(false)
            DriveService.stop(KiteApp.app)
        } else when (session.phase) {
            TransitGuidance.Phase.WALK -> walkTransitLeg(session, location.last)
            TransitGuidance.Phase.BOARD -> {
                (leg.calls.firstOrNull()?.at ?: leg.path.firstOrNull())?.let {
                    frame(listOf(it), bottomFraction = 0.23f, top = 135)
                }
                DriveService.show(KiteApp.app, "Board ${leg.line} at ${leg.fromName}", leg.headsign ?: leg.toName)
                val first = leg.calls.firstOrNull()
                if (first?.stopId != null && leg.tripId != null) {
                    transitDeparturesJob = scope.launch {
                        while (transitGuidance === session && session.phase == TransitGuidance.Phase.BOARD) {
                            val board = withContext(Dispatchers.Default) {
                                Transitous.departures(first.at, stopId = first.stopId, stopName = first.name)
                            }
                            if (transitGuidance === session && session.leg === leg)
                                session.liveDeparture = board?.departures?.firstOrNull { it.tripId == leg.tripId }
                            delay(40_000)
                        }
                    }
                }
            }
            else -> {}
        }
        mapTick++
    }

    private fun walkTransitLeg(session: TransitGuidance, fix: Fix?) {
        val leg = session.leg ?: return
        if (!leg.isWalk || transitWalkJob?.isActive == true) return
        val destination = session.trip.legs.getOrNull(session.legIndex + 1)?.takeUnless { it.isWalk }?.let {
            it.calls.firstOrNull()?.at ?: it.path.firstOrNull()
        } ?: leg.path.lastOrNull()
        val freshFix = fix?.takeIf { it.ageMs in 0..15_000 && it.accuracy in 0.0..65.0 }
        val origin = freshFix?.coord ?: leg.path.firstOrNull()
        if (destination == null || origin == null) {
            session.walkingError = true
            return
        }
        val name = leg.toName.takeUnless { it.isBlank() || it == "END" } ?: session.destination.name
        if (freshFix != null && freshFix.accuracy <= 35 && origin.distanceTo(destination) < 23 && leg.distanceMeters < 80) {
            advanceTransitLeg()
            return
        }
        val end = Place("transit-walk:${session.legIndex}", name, destination, "transitous")
        val index = session.legIndex
        session.walkingError = false
        transitWalkJob = scope.launch {
            val route = if (leg.walkSteps.isNotEmpty() && leg.path.size >= 2 && origin.distanceTo(leg.path.first()) < 50) {
                Route(TravelMode.WALK, leg.path, leg.distanceMeters, leg.durationSeconds, null, null,
                    leg.walkSteps.map { it.copy() }.toMutableList(), source = "transitous")
            } else Directions.routes(origin, destination, TravelMode.WALK, useGoogle = false).routes.firstOrNull()
            if (transitGuidance !== session || session.legIndex != index) return@launch
            if (route == null) {
                session.walkingError = true
                frame(leg.path, bottomFraction = 0.24f, top = 135)
                return@launch
            }
            val walking = Navigator(route, end, emptyList(), scope, transitWalk = true)
            nav = walking
            location.last?.let { now ->
                walking.handle(now)
                if (walking.arrived) { advanceTransitLeg(); return@launch }
                followCamera(walking, now)
            }
            mapTick++
        }
    }

    fun retryTransitWalk() {
        val session = transitGuidance ?: return
        walkTransitLeg(session, location.last)
    }

    fun boardTransit() {
        val session = transitGuidance ?: return
        val leg = session.leg ?: return
        if (session.phase != TransitGuidance.Phase.BOARD || session.boarding) return
        session.boarding = true
        transitBoardJob = scope.launch {
            val tracker = withContext(Dispatchers.Default) { TransitRide(leg) }
            if (transitGuidance !== session || session.leg !== leg) return@launch
            transitDeparturesJob?.cancel()
            stopTransitOverview()
            session.board(tracker)
            location.last?.let { session.observe(it) }
            frame(leg.path, bottomFraction = 0.24f, top = 148)
            DriveService.show(KiteApp.app, "Riding ${leg.line}", "Get off at ${leg.toName}")
            mapTick++
        }
    }

    fun advanceTransitLeg() {
        val session = transitGuidance ?: return
        nav?.stop()
        nav = null
        session.advance()
        setTransitLeg(session)
    }

    fun replanTransit() {
        val destination = transitGuidance?.destination ?: return
        endNavigation()
        openDirections(destination)
        showTransit()
    }

    fun stopTransitOverview() {
        if (transitOverviewJob?.isActive == true) map?.cancelTransitions()
        transitOverviewJob?.cancel()
        transitOverviewJob = null
        transitGuidance?.overviewing = false
    }

    fun previewTransitJourney() {
        val journey = transitGuidance ?: return
        val path = journey.trip.path
        if (path.isEmpty()) return
        stopTransitOverview()
        journey.overviewing = true
        journey.following = false
        nav?.following = false
        val waypoints = journey.trip.legs.flatMap { leg ->
            listOfNotNull(leg.path.firstOrNull() ?: leg.calls.firstOrNull()?.at,
                leg.path.lastOrNull() ?: leg.calls.lastOrNull()?.at)
        }.distinct()
        val stride = (waypoints.size / 12).coerceAtLeast(1)
        transitOverviewJob = scope.launch {
            frame(path, bottomFraction = 0.19f, top = 135)
            delay(700)
            for ((index, point) in waypoints.withIndex()) {
                if (index % stride != 0 && index != waypoints.lastIndex) continue
                val m = map ?: break
                MapCam.animate(m, CameraPosition.Builder().target(point.ml()).zoom(15.0)
                    .tilt(0.0).bearing(0.0).padding(0.0, 0.0, 0.0, 0.0).build(), ms = 440)
                delay(700)
            }
            frame(path, bottomFraction = 0.19f, top = 135)
        }
    }

    fun followTransit() {
        val session = transitGuidance ?: return
        stopTransitOverview()
        session.following = true
        nav?.let { recenterNav(); return }
        if (session.phase == TransitGuidance.Phase.BOARD) {
            val leg = session.leg
            (leg?.calls?.firstOrNull()?.at ?: leg?.path?.firstOrNull())?.let {
                frame(listOf(it), bottomFraction = 0.22f, top = 135)
            }
        } else location.last?.let {
            transitCameraAt = 0
            focusTransitRide(session, it)
        }
    }

    private fun focusTransitRide(session: TransitGuidance, f: Fix) {
        val m = map ?: return
        if (!session.following || glide.mapTouched || session.phase != TransitGuidance.Phase.RIDE || f.accuracy > 75) return
        val time = android.os.SystemClock.elapsedRealtime()
        if (time - transitCameraAt < 1200 || m.cameraPosition.target?.kite()?.distanceTo(f.coord)?.let { it < 24 } == true) return
        transitCameraAt = time
        MapCam.animate(m, CameraPosition.Builder().target(f.coord.ml()).zoom(15.4).tilt(0.0).bearing(0.0).build(), ms = 500)
    }

    fun startNavigation() {
        val d = directions ?: return
        val route = d.route ?: return
        val me = userLatLng ?: return
        val explicitStart = d.orderedPlaces().firstOrNull()
        if (d.reversed || explicitStart?.location?.distanceTo(me)?.let { it > 70 } == true) {
            val plan = routePlan("") ?: return
            val stops = plan.points.dropLast(1).filterIndexed { i, p -> i != 0 || p.location.distanceTo(me) > 70 }
            directions = DirectionsState(plan.points.last(), mode = d.mode, stops = stops)
            autoStart = true
            loadAllModes()
            return
        }
        val n = Navigator(route, d.destination, d.stops, scope)
        navZoomSteps = 0
        nav = n
        n.onFinished = { if (nav === n) endNavigation() }
        // In a tunnel the Navigator carries on along the route by itself: move the arrow with it.
        n.onEstimate = { f ->
            if (nav === n) {
                n.handle(f, estimated = true)
                followCamera(n, f)
                driveNote(n)
                mapTick++
            }
        }
        resumeOffer = null
        rememberTrip(n)
        location.setNavigating(true)
        DriveService.start(KiteApp.app)
        location.last?.let { n.handle(it); followCamera(n, it) }
    }

    fun endNavigation() {
        stopTransitOverview()
        transitWalkJob?.cancel()
        transitWalkJob = null
        transitBoardJob?.cancel()
        transitClockJob?.cancel()
        transitDeparturesJob?.cancel()
        transitGuidance = null
        placingStop = false
        stopPinWasFollowing = false
        closeStopSearch(restore = false)
        addingStop = false
        nav?.stop()
        glide.stop()
        nav = null
        settings.trip = null
        location.setNavigating(false)
        DriveService.stop(KiteApp.app)
        directions = null
        showSteps = false
        browseLook = MapLook.NORTH
        browseFollowing = false
        resetCamera()
        mapTick++
    }

    fun recenterNav() {
        val n = nav ?: return
        if (!n.following) glide.easeFromCurrentCamera()
        n.following = true
        location.last?.let { followCamera(n, it) }
    }

    fun zoomNavigation(step: Int) {
        val n = nav ?: return
        val m = map ?: return
        if (n.following) {
            navZoomSteps = (navZoomSteps + step).coerceIn(-3, 4)
            location.last?.let { followCamera(n, it) }
        } else {
            val camera = m.cameraPosition
            m.animateCamera(CameraUpdateFactory.newCameraPosition(CameraPosition.Builder(camera)
                .zoom((camera.zoom + step * 0.55).coerceIn(2.0, 20.0)).build()), 220)
        }
    }

    fun previewNavTurn(turn: Maneuver) {
        val n = nav ?: return
        val m = map ?: return
        n.following = false
        MapCam.animate(m, CameraPosition.Builder().target(turn.location.ml()).zoom(16.8).tilt(24.0)
            .padding(0.0, 0.0, 0.0, 0.0).build(), ms = 380)
    }

    /** Show the whole remaining trip; the camera stops following until re-centered. */
    fun overviewNav() {
        val n = nav ?: return
        n.following = false
        val line = n.progress?.let { Geo.slice(n.route.polyline, it.alongMeters, Geo.length(n.route.polyline)) } ?: n.route.polyline
        frame(line, bottomFraction = 0.25f, top = 200)
    }

    private fun locationChanged(f: Fix) {
        if (location.reducedAccuracy || f.accuracy > 200) areaRisk = null
        val transit = transitGuidance
        if (transit != null) {
            val walking = nav
            if (transit.phase == TransitGuidance.Phase.WALK && walking == null && transit.walkingError &&
                f.ageMs in 0..15_000 && f.accuracy in 0.0..35.0 &&
                transit.leg?.path?.lastOrNull()?.distanceTo(f.coord)?.let { it <= 20 } == true) {
                advanceTransitLeg()
            } else if (transit.phase == TransitGuidance.Phase.WALK && walking != null) {
                transit.observe(f)
                walking.handle(f)
                if (walking.arrived) advanceTransitLeg()
                else { followCamera(walking, f); driveNote(walking); mapTick++ }
            } else if (transit.observe(f)) advanceTransitLeg()
            else if (transit.shouldAutoBoard(f)) boardTransit()
            else focusTransitRide(transit, f)
            return
        }
        val n = nav ?: run { followBrowse(f, entering = false); return }
        n.handle(f)
        followCamera(n, f)
        tripCheck(n)
        driveNote(n)
        mapTick++
    }

    /** The next turn and arrival time on the drive's notification (Android only: the iPhone has no such thing to fill). */
    private fun driveNote(n: Navigator) {
        val p = n.progress ?: return
        if (n.arrived) {
            DriveService.show(KiteApp.app, "You have arrived", n.destination.name)
            return
        }
        val m = n.nextManeuver
        val turn = if (m == null) "To ${n.destination.name}" else "${Fmt.distance(p.distanceToNext)} · ${SpokenText.forScreen(m.instruction)}"
        DriveService.show(KiteApp.app, turn, "Arrive ${Fmt.arrival(p.remainingSeconds)} · ${Fmt.distance(p.remainingMeters)} to go")
    }

    private fun tripCheck(n: Navigator) {
        if (n.arrived) {
            if (settings.trip != null) settings.trip = null
        } else if (System.currentTimeMillis() - tripSavedAt > 60_000 || settings.trip?.stops?.size != n.stops.size ||
            settings.trip?.destination?.id != n.destination.id) {
            rememberTrip(n)
        }
    }

    private fun followCamera(n: Navigator, f: Fix) {
        val p = n.progress
        // Further out on long stretches, closer in and flatter just before a turn (see NavZoom).
        // Then the zoom setting (Closer, Normal, Wider) and the 3D, 2D or north-up button.
        val view = NavZoom.view(f.speed, p?.distanceToNext, n.nextManeuver?.type, n.route.mode == TravelMode.DRIVE)
            .applying(settings.mapZoom, settings.driveLook)
        glide.look = settings.driveLook
        glide.fix(n, f, view.across / 1.36.pow(navZoomSteps), view.pitch)
    }

    /** The map button while driving: 3D, then 2D, then north up. Kept for the next drive. */
    fun cycleDriveLook() {
        settings.driveLook = settings.driveLook.next
        val n = nav ?: return
        n.following = true
        location.last?.let { followCamera(n, it) }
    }

    /**
     * The map button off a route. North up with the map turned by hand: face north first, like the
     * compass it replaces. Otherwise on to the next of 3D, 2D and north up.
     */
    fun cycleBrowseLook(ctx: android.content.Context) {
        if (browseLook == MapLook.NORTH && mapHeading != 0.0) {
            map?.let { m -> MapCam.animate(m, CameraPosition.Builder(m.cameraPosition).bearing(0.0).build(), ms = 300) }
            return
        }
        browseLook = browseLook.next
        if (browseLook == MapLook.NORTH) {
            browseFollowing = false
            resetCamera()
            return
        }
        val loc = location.last
        if (loc == null) {
            if (location.denied) LocationService.openSettings(ctx) else location.start()
            return
        }
        browseFollowing = true
        followBrowse(loc, entering = true)
    }

    /**
     * In 3D or 2D off a route, keeps you in the middle with the map facing the way you're going, as you
     * move. Pinching to zoom is kept; dragging the map, or opening a place, stops it until Centre on me.
     */
    private fun followBrowse(f: Fix, entering: Boolean) {
        val m = map ?: return
        if (!browseFollowing || browseLook == MapLook.NORTH || nav != null) return
        if (!entering && (selected != null || results.isNotEmpty() || directions != null)) return
        val course = if (f.courseKnown && f.speed > 2) f.course else m.cameraPosition.bearing
        val tilted = browseLook == MapLook.TILTED
        val zoom = if (entering) MapCam.zoomFor(if (tilted) 700.0 else 900.0, f.lat, mapWidthDp) else m.cameraPosition.zoom
        val tilt = if (tilted) (if (entering) 50.0 else max(m.cameraPosition.tilt, 30.0)) else 0.0
        val pos = CameraPosition.Builder().target(f.coord.ml()).zoom(zoom).tilt(tilt).bearing(course).build()
        MapCam.animate(m, pos, ms = if (entering) 600 else 900)
    }

    // Map

    fun centerOnUser(ctx: android.content.Context) {
        val m = map
        val loc = location.last
        if (m == null || loc == null) {
            if (location.denied) LocationService.openSettings(ctx) else location.start()
            return
        }
        // In 3D or 2D, Centre on me picks up following again.
        if (browseLook != MapLook.NORTH && nav == null) {
            browseFollowing = true
            followBrowse(loc, entering = true)
            return
        }
        MapCam.animate(m, CameraPosition.Builder().target(loc.coord.ml()).zoom(MapCam.zoomFor(1200.0, loc.lat, mapWidthDp))
            .tilt(0.0).bearing(0.0).build(), ms = 500)
    }

    private fun resetCamera() {
        val m = map ?: return
        m.setPadding(0, 0, 0, 0)
        val c = m.cameraPosition
        MapCam.animate(m, CameraPosition.Builder(c).tilt(0.0).bearing(0.0).padding(0.0, 0.0, 0.0, 0.0).build(), ms = 500)
    }

    fun frame(points: List<LatLng>, bottomFraction: Float = 0.45f, top: Int = 130) {
        val m = map ?: return
        val unique = points.distinct()
        if (unique.isEmpty()) return
        // Showing a place or a route: stop following, or the next fix would pull the map away.
        browseFollowing = false
        if (nav == null) browseLook = MapLook.NORTH
        if (unique.size == 1) {
            MapCam.animate(m, CameraPosition.Builder().target(unique[0].ml()).zoom(MapCam.zoomFor(1200.0, unique[0].lat, mapWidthDp))
                .tilt(0.0).bearing(0.0).build(), ms = 300)
            return
        }
        val b = LatLngBounds.Builder().apply { unique.forEach { include(it.ml()) } }.build()
        val topInset = top.coerceAtMost((mapHeightDp * 0.35f).toInt())
        val bottomInset = (mapHeightDp * bottomFraction + 20).toInt().coerceAtMost((mapHeightDp * 0.55f).toInt())
        MapCam.fit(m, b, intArrayOf(40, topInset, 40, bottomInset), ms = 600)
    }

    companion object {
        private val geographicSearchCategories = setOf("city", "town", "village", "municipality", "hamlet", "suburb", "country", "state", "postcode")
        const val LOCATION_OFF_TEXT = "Location is off for Kite. Turn it on in Settings to get directions from where you are."
    }
}

data class StopCandidate(val place: Place, val ahead: Double?, val offset: Double, val routeMeters: Double? = null)
data class StopSearch(
    val query: String,
    val wasFollowing: Boolean,
    val loading: Boolean = true,
    val parking: Boolean = false,
    val results: List<StopCandidate> = emptyList(),
    val selected: StopCandidate? = null,
) {
    companion object { const val PINS = "kite-stop-candidates" }
}

/** Street View asked for from a place: where, and what to call it. */
data class StreetViewRequest(val name: String, val pano: StreetView.Panorama, val heading: Double)
