@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class, androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package app.kite.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.kite.*
import app.kite.core.*
import coil.compose.AsyncImage
import coil.request.ImageRequest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import java.util.Locale

@Composable
fun PlaceHeader(model: AppModel, place: Place) {
    val dark = LocalDark.current
    val ctx = LocalContext.current
    var share by remember(place.id) { mutableStateOf(false) }
    Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.weight(1f)) {
                Copyable(place.name) {
                    Text(place.name, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, color = primaryText, maxLines = 2,
                        overflow = TextOverflow.Ellipsis, lineHeight = 30.sp)
                }
            }
            CircleIconButton(if (AppSettings.isSaved(place)) Icons.Filled.Bookmark else Icons.Outlined.BookmarkBorder) { AppSettings.toggleSaved(place) }
            Box {
                CircleIconButton(Icons.Filled.Share) { share = true }
                DropdownMenu(share, { share = false }) {
                    listOf("Open in Google Maps" to { ctx.open(place.shareUrl) },
                        "Share Google Maps link" to { ctx.share(place.shareUrl) },
                        "Share place name" to { ctx.share(place.name) },
                        "Share coordinates" to { ctx.share("${place.location.lat.plain()}, ${place.location.lng.plain()}") },
                    ).forEach { (label, action) ->
                        DropdownMenuItem(text = { Text(label) }, onClick = { share = false; action() })
                    }
                }
            }
            CircleIconButton(Icons.Filled.Close) { model.closePlace() }
        }
        PlaceMetaLine(place, here = model.userLatLng)
        StatusText(place)
        Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.weight(1f).heightIn(min = 56.dp).clip(CircleShape).background(Vela.accent(dark))
                .clickable { model.openDirections(place) }, horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Directions, null, tint = Vela.onAccent(dark), modifier = Modifier.size(24.dp))
                Text("Directions", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = Vela.onAccent(dark))
            }
            Row(Modifier.heightIn(min = 56.dp).clip(CircleShape).background(Vela.tonal(dark))
                .clickable { model.openDirections(place); model.autoStart = true }.padding(horizontal = 24.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Navigation, null, tint = Vela.onTonal(dark), modifier = Modifier.size(22.dp))
                Text("Go", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = Vela.onTonal(dark))
            }
        }
    }
}

@Composable
fun PlaceBody(model: AppModel, place: Place) {
    if (place.id.startsWith("transit:")) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 72.dp)) {
            DepartureBoard(place)
        }
        return
    }
    var tab by remember(place.id) { mutableIntStateOf(0) }
    val mediaId = place.featureId.takeUnless { AppSettings.noGoogle }
    val canReview = mediaId != null && (place.reviewCount ?: 1) > 0
    var reviews by remember(mediaId) { mutableStateOf<List<PlaceReview>?>(null) }
    var reviewsFailed by remember(mediaId) { mutableStateOf(false) }
    var attempt by remember(mediaId) { mutableIntStateOf(0) }
    var gallery by remember(mediaId) { mutableStateOf<List<String>?>(null) }
    var driveSeconds by remember(place.id) { mutableStateOf<Double?>(null) }
    LaunchedEffect(mediaId, canReview, attempt) {
        if (mediaId == null || !canReview) return@LaunchedEffect
        reviewsFailed = false
        try {
            reviews = GoogleClient.shared.reviews(mediaId)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            reviewsFailed = true
        }
    }
    LaunchedEffect(mediaId) {
        gallery = if (mediaId == null) emptyList() else try {
            GoogleClient.shared.photos(mediaId)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            emptyList()
        }
    }
    val previews = if (AppSettings.noGoogle) place.photoUrls.filterNot(::isGooglePhoto) else place.photoUrls
    val photos = (gallery.orEmpty() + previews).distinctBy { it.substringBeforeLast("=w") }
    LaunchedEffect(place.id) {
        val from = model.userLatLng ?: return@LaunchedEffect
        val d = from.distanceTo(place.location)
        if (d <= 300 || d >= 300_000) return@LaunchedEffect
        val s = model.settings
        var r: List<Route>? = null
        if (!s.noGoogle) r = runCatching { GoogleClient.shared.directions(from, place.location, TravelMode.DRIVE, s.avoidHighways, s.avoidTolls) }.getOrNull()
        if (r.isNullOrEmpty()) r = runCatching { OSRM.route(from, place.location, TravelMode.DRIVE) }.getOrNull()
        driveSeconds = r?.minOfOrNull { it.durationSeconds }
    }
    val scroll = rememberScrollState()
    LaunchedEffect(tab) { scroll.scrollTo(0) }
    Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(horizontal = 16.dp).padding(bottom = 80.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        PlaceActions(model, place, driveSeconds)
        val mediaTabs = buildList {
            add("Overview")
            if (canReview) add("Reviews")
            if (mediaId != null || photos.isNotEmpty()) add("Photos")
            if (place.about.isNotEmpty()) add("About")
        }
        val selectedTab = mediaTabs.getOrNull(tab) ?: "Overview"
        if (mediaTabs.size > 1) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                mediaTabs.forEachIndexed { i, label ->
                    SegmentedButton(selectedTab == label, { tab = i }, SegmentedButtonDefaults.itemShape(i, mediaTabs.size)) {
                        Text(label, maxLines = 1, style = MaterialTheme.typography.labelMedium)
                    }
                }
            }
        }
        when (selectedTab) {
            "Reviews" -> PlaceReviews(place, reviews, reviewsFailed) { attempt++ }
            "Photos" -> PlacePhotos(place, photos, loading = mediaId != null && gallery == null)
            "About" -> PlaceAbout(place)
            else -> {
                PhotoStrip(photos.take(5), 140.dp, opensViewer = true, streetView = place, model = model)
                if (photos.isNotEmpty()) TextButton({ tab = mediaTabs.indexOf("Photos") }) { Text("See more photos") }
                PlaceOverview(place)
                if (reviews.orEmpty().isNotEmpty() || canReview && !place.featuredReview.isNullOrBlank()) {
                    Text("Reviews", fontWeight = FontWeight.Bold, color = primaryText, fontSize = KType.headline)
                    if (reviews.orEmpty().isEmpty()) place.featuredReview?.let { Text(it, color = secondaryText) }
                    reviews.orEmpty().take(3).forEach { ReviewRow(it) }
                    TextButton({ tab = mediaTabs.indexOf("Reviews") }) { Text("See more reviews") }
                }
            }
        }
        val attribution = when (place.source) {
            "google" -> "Place details from Google Maps"
            "mapbox" -> "Map data © Mapbox and OpenStreetMap contributors"
            else -> "Map data © OpenStreetMap contributors"
        }
        Text(attribution, fontSize = KType.caption, color = secondaryText)
    }
}

@Composable
private fun PlaceReviews(place: Place, reviews: List<PlaceReview>?, failed: Boolean, retry: () -> Unit) {
    val ctx = LocalContext.current
    var openWeb by remember(place.id) { mutableStateOf(false) }
    if (failed) {
        Text("Reviews are temporarily unavailable.", color = secondaryText)
        TextButton(retry) { Text("Try again") }
    } else if (reviews == null) {
        CircularProgressIndicator(Modifier.size(26.dp))
    } else if (reviews.orEmpty().isEmpty()) {
        Text(place.featuredReview ?: "No reviews returned for this place.", color = secondaryText)
    }
    reviews.orEmpty().forEach { ReviewRow(it) }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        TextButton({ openWeb = true }) { Text("Read all reviews") }
        TextButton({ ctx.open(place.shareUrl) }) { Text("Open Google Maps") }
    }
    if (openWeb && !AppSettings.noGoogle) GoogleReviewsPage(place) { openWeb = false }
}

@Composable
private fun ReviewRow(review: PlaceReview) {
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(review.author, fontWeight = FontWeight.Bold, color = primaryText)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            review.stars?.let { rating ->
                val stars = rating.coerceIn(0, 5)
                Row(Modifier.semantics { contentDescription = "$stars out of 5 stars" }) {
                    repeat(5) { index ->
                        val filled = index < stars
                        Icon(if (filled) Icons.Filled.Star else Icons.Outlined.StarBorder, null,
                            tint = if (filled) Color(if (LocalDark.current) 0xFFFFC55E else 0xFF985300) else secondaryText,
                            modifier = Modifier.size(17.dp))
                    }
                }
            }
            review.relativeTime?.let { Text(it, fontSize = KType.caption, color = secondaryText) }
        }
        review.text?.let { Text(it, color = primaryText) }
        if (review.photos.isNotEmpty()) PhotoStrip(review.photos, 82.dp, opensViewer = true)
    }
    HorizontalDivider()
}

@Composable
private fun PlacePhotos(place: Place, photos: List<String>, loading: Boolean) {
    val ctx = LocalContext.current
    var viewing by remember(place.id) { mutableStateOf<Int?>(null) }
    if (loading) CircularProgressIndicator(Modifier.size(26.dp))
    photos.chunked(3).forEachIndexed { row, urls ->
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            urls.forEachIndexed { col, url ->
                AsyncImage(url, "Photo ${row * 3 + col + 1}", contentScale = ContentScale.Crop,
                    modifier = Modifier.weight(1f).aspectRatio(1f).clip(RoundedCornerShape(10.dp))
                        .background(secondaryText.copy(alpha = 0.15f)).clickable { viewing = row * 3 + col })
            }
            repeat(3 - urls.size) { Spacer(Modifier.weight(1f)) }
        }
    }
    if (photos.isEmpty() && !loading) Text("No photos returned for this place.", color = secondaryText)
    if (place.featureId != null && !AppSettings.noGoogle) TextButton({ ctx.open(place.shareUrl) }) { Text("More photos on Google Maps") }
    viewing?.takeIf { it in photos.indices }?.let { PhotoViewer(photos, it) { viewing = null } }
}

@Composable
private fun PlaceActions(model: AppModel, place: Place, driveSeconds: Double?) {
    val ctx = LocalContext.current
    val dark = LocalDark.current
    var more by remember { mutableStateOf(false) }
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        driveSeconds?.let {
            Row(Modifier.height(52.dp).border(1.dp, secondaryText.copy(alpha = 0.35f), CircleShape).padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.DirectionsCar, null, tint = primaryText, modifier = Modifier.size(20.dp))
                Text("${Fmt.duration(it)} drive", fontWeight = FontWeight.Bold, color = primaryText)
            }
        }
        telUrl(place.phone)?.let { PillButton("Call", Icons.Filled.Phone) { ctx.open(it) } }
        webUrl(place.website)?.let { PillButton("Website", Icons.Filled.Language) { ctx.open(it) } }
        if (place.id == model.settings.parking?.id) PillButton("Clear spot", Icons.Outlined.Cancel) { model.clearParking() }
        Box {
            Row(Modifier.height(40.dp).clip(CircleShape).background(Vela.tonal(dark)).clickable { more = true }.padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.MoreHoriz, null, tint = Vela.onTonal(dark), modifier = Modifier.size(18.dp))
                Text("More", fontSize = KType.subheadline, fontWeight = FontWeight.SemiBold, color = Vela.onTonal(dark))
            }
            DropdownMenu(more, { more = false }) {
                fun item(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, f: () -> Unit) = @Composable {
                    DropdownMenuItem(text = { Text(label) }, leadingIcon = { Icon(icon, null) }, onClick = { more = false; f() })
                }
                if (model.settings.home?.id == place.id) item("Remove home", Icons.Filled.Home) { model.setHome(null) }()
                else item("Set as home", Icons.Outlined.Home) { model.setHome(place) }()
                if (model.settings.work?.id == place.id) item("Remove work", Icons.Filled.Work) { model.setWork(null) }()
                else item("Set as work", Icons.Outlined.WorkOutline) { model.setWork(place) }()
                item("Copy coordinates", Icons.Filled.ContentCopy) {
                    ctx.copy(String.format(Locale.US, "%.6f, %.6f", place.location.lat, place.location.lng))
                }()
                place.address?.let { a -> item("Copy address", Icons.Filled.ContentPaste) { ctx.copy("${place.name}, $a") }() }
                HorizontalDivider()
                Text("Open in", fontSize = KType.caption, color = secondaryText, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
                for (app in OtherApp.entries) item(app.label, Icons.Filled.Map) { ctx.open(app.url(place)) }()
            }
        }
    }
}

/** A bus stop or a station, which gets a live departure board. */
private fun isStop(p: Place): Boolean {
    if (p.id.startsWith("transit:")) return true
    val text = ((p.category ?: "") + " " + p.name).lowercase()
    if (text.contains("gas station") || text.contains("charging station") || text.contains("petrol station")) return false
    return listOf("station", "bus stop", "stop ", "transit", "subway", "metro", "tram", "light rail", "terminal", "depot").any { text.contains(it) }
}

@Composable
private fun PlaceOverview(place: Place) {
    val ctx = LocalContext.current
    var hoursOpen by remember(place.id) { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        place.editorialSummary?.let { s -> Copyable(s) { Text(s, color = primaryText) } }
        place.address?.let { a -> Copyable(a) { InfoRow(Icons.Outlined.Place, a) } }
        if (isStop(place)) DepartureBoard(place)
        if (place.hours.isNotEmpty()) Copyable(place.hours.joinToString("\n"), onClick = { hoursOpen = !hoursOpen }) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
                    Icon(Icons.Outlined.Schedule, null, tint = secondaryText, modifier = Modifier.size(22.dp))
                    Column(Modifier.weight(1f)) {
                        StatusText(place)
                        if (!hoursOpen) place.hours.firstOrNull()?.let { Text(it, fontSize = KType.subheadline, color = secondaryText) }
                    }
                    Icon(if (hoursOpen) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown, null, tint = secondaryText)
                }
                if (hoursOpen) for (h in place.hours) {
                    val parts = h.split(":", limit = 2)
                    Row(Modifier.padding(start = 36.dp)) {
                        Text(parts.first(), fontSize = KType.subheadline, color = primaryText, modifier = Modifier.width(110.dp))
                        Text(if (parts.size > 1) parts[1].trim() else "", fontSize = KType.subheadline, color = primaryText)
                    }
                }
            }
        }
        place.phone?.let { phone -> Copyable(phone, onClick = { telUrl(phone)?.let { ctx.open(it) } }) { InfoRow(Icons.Outlined.Phone, phone) } }
        place.website?.let { site ->
            Copyable(site, onClick = { webUrl(site)?.let { ctx.open(it) } }) {
                InfoRow(Icons.Filled.Language, site.removePrefix("https://").removePrefix("http://"))
            }
        }
        val coords = String.format(Locale.US, "%.6f, %.6f", place.location.lat, place.location.lng)
        Copyable(coords) { InfoRow(Icons.Filled.GpsFixed, coords) }
        place.featuredReview?.let { r ->
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Review", fontSize = KType.headline, fontWeight = FontWeight.SemiBold, color = primaryText)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(Icons.Filled.AccountCircle, null, tint = secondaryText, modifier = Modifier.size(28.dp))
                    Text("“$r”", fontSize = KType.subheadline, color = primaryText)
                }
            }
        }
    }
}

@Composable
private fun PlaceAbout(place: Place) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        for (section in place.about) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(section.title, fontSize = KType.headline, fontWeight = FontWeight.SemiBold, color = primaryText)
                for (item in section.items) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Check, null, tint = secondaryText, modifier = Modifier.size(14.dp))
                    Text(item, fontSize = KType.subheadline, color = primaryText)
                }
            }
        }
    }
}

@Composable
fun InfoRow(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
        Icon(icon, null, tint = secondaryText, modifier = Modifier.size(22.dp))
        Text(text, fontSize = KType.subheadline, color = primaryText, modifier = Modifier.weight(1f))
    }
}

/** Next departures at a stop from Transitous, refreshed every 30 seconds while it's open. */
@Composable
fun DepartureBoard(place: Place) {
    var board by remember(place.id) { mutableStateOf<Transitous.Board?>(null) }
    var loaded by remember(place.id) { mutableStateOf(false) }
    LaunchedEffect(place.id) {
        while (true) {
            val b = runCatching { Transitous.departures(place.location,
                stopId = place.id.removePrefix("transit:").takeIf { place.id.startsWith("transit:") },
                stopName = place.name) }.getOrNull()
            if (b != null || !loaded) board = b
            loaded = true
            delay(30_000)
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Departures", fontSize = KType.headline, fontWeight = FontWeight.SemiBold, color = primaryText)
        val b = board
        when {
            b != null -> {
                for (d in b.departures.take(8)) Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    LineChip(TransitLeg(isWalk = false, mode = d.mode, line = d.line, color = d.color, textColor = d.textColor))
                    Text(d.headsign, fontSize = KType.subheadline, color = primaryText, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    Column(horizontalAlignment = Alignment.End) {
                        Text(countdown(d.time), fontSize = KType.subheadline, fontWeight = FontWeight.SemiBold,
                            color = if (d.delayMinutes != null) Vela.open else primaryText)
                        d.delayMinutes?.takeIf { it != 0 }?.let { late ->
                            Text(if (late > 0) "$late min late" else "${-late} min early", fontSize = KType.caption2,
                                color = if (late > 0) Vela.closed else Vela.open)
                        }
                    }
                }
                Text("Live times in green · from Transitous", fontSize = KType.caption, color = secondaryText)
            }
            loaded -> Text("No departures found here.", fontSize = KType.subheadline, color = secondaryText)
            else -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                Text("Loading departures…", color = secondaryText)
            }
        }
    }
}

private fun countdown(t: Long): String {
    val mins = Math.round((t - System.currentTimeMillis()) / 60_000.0).toInt()
    if (mins <= 0) return "Now"
    if (mins < 60) return "$mins min"
    return Fmt.time(java.util.Date(t))
}

@Composable
fun PhotoStrip(all: List<String>, height: Dp = 130.dp, opensViewer: Boolean = false, streetView: Place? = null, model: AppModel? = null) {
    // "Use Kite without Google": a place saved earlier still has Google's photo links; don't load them.
    val urls = if (AppSettings.noGoogle) all.filterNot(::isGooglePhoto) else all
    var viewing by remember { mutableStateOf<Int?>(null) }
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        if (streetView != null && model != null) StreetViewTile(model, streetView, height)
        urls.forEachIndexed { i, u ->
            AsyncImage(u, null, contentScale = ContentScale.Crop,
                modifier = Modifier.size(height * 1.4f, height).clip(RoundedCornerShape(10.dp)).background(secondaryText.copy(alpha = 0.15f))
                    .then(if (opensViewer) Modifier.clickable { viewing = i } else Modifier))
        }
    }
    viewing?.let { start -> PhotoViewer(urls, start) { viewing = null } }
}

fun isGooglePhoto(u: String): Boolean {
    val host = runCatching { java.net.URI(u).host?.lowercase() }.getOrNull() ?: return false
    return "google" in host || "gstatic" in host || "ggpht" in host
}

/** Google photo links carry their size ("=w408-h306-k-no"): ask for a bigger one. */
fun largePhoto(u: String): String = u.replace(Regex("=w\\d+-h\\d+"), "=w1600-h1200")

/** Photos full screen, swiped through. */
@Composable
fun PhotoViewer(urls: List<String>, start: Int, close: () -> Unit) {
    FullScreenDialog(close) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            val pager = rememberPagerState(start) { urls.size }
            HorizontalPager(pager, Modifier.fillMaxSize()) { i ->
                AsyncImage(largePhoto(urls[i]), null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
            }
            Box(Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(16.dp).size(40.dp).clip(CircleShape)
                .background(Color.White.copy(alpha = 0.2f)).clickable(onClick = close), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Close, "Close", tint = Color.White)
            }
        }
    }
}

/** The first tile of a place's photos: Google Street View looking at the place. */
@Composable
fun StreetViewTile(model: AppModel, place: Place, height: Dp) {
    val ctx = LocalContext.current
    if (AppSettings.noGoogle) return
    var pano by remember(place.id, place.streetViewHint) { mutableStateOf<StreetView.Panorama?>(null) }
    var loaded by remember(place.id, place.streetViewHint) { mutableStateOf(false) }
    fun heading(p: StreetView.Panorama): Double = place.streetViewHint?.takeIf { it.id == p.id }?.yaw
        ?: if (p.location.distanceTo(place.location) > 2) Geo.bearing(p.location, place.location) else p.heading
    LaunchedEffect(place.id, place.location, place.streetViewHint) {
        val hint = place.streetViewHint
        val resolved = hint?.let { StreetView.byId(it.id) } ?: StreetView.find(place.location)
            ?: hint?.let { StreetView.Panorama(it.id, place.location, heading = it.yaw ?: 0.0) }
        pano = resolved
        loaded = true
        if (resolved != null && DemoScript.step == "streetview") {
            model.streetView = StreetViewRequest(place.name, resolved, heading(resolved))
        }
    }
    val p = pano
    if (p != null) {
        val heading = heading(p)
        Box(Modifier.size(height * 1.4f, height).clip(RoundedCornerShape(10.dp))
            .clickable { model.streetView = StreetViewRequest(place.name, p, heading) }) {
            val thumbnail = ImageRequest.Builder(ctx).data(StreetView.thumbnailUrl(p, heading)).apply {
                StreetView.imageHeaders.forEach { (name, value) -> addHeader(name, value) }
            }.build()
            AsyncImage(thumbnail, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().background(secondaryText.copy(alpha = 0.15f)))
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.5f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.55f))))
            Row(Modifier.align(Alignment.BottomStart).padding(8.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Streetview, null, tint = Color.White, modifier = Modifier.size(16.dp))
                Text("Street View", fontSize = KType.caption, fontWeight = FontWeight.SemiBold, color = Color.White)
            }
        }
    } else {
        Box(Modifier.size(height * 1.4f, height).clip(RoundedCornerShape(10.dp)).background(Vela.tonal(LocalDark.current))
            .clickable {
                val at = "${place.location.lat.plain()},${place.location.lng.plain()}"
                ctx.open("https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=$at")
            }, contentAlignment = Alignment.Center) {
            Text(if (loaded) "Open Street View" else "Loading Street View…", color = primaryText, fontWeight = FontWeight.SemiBold)
        }
    }
}

/** A transit line's badge in its own colors. */
@Composable
fun LineChip(leg: TransitLeg) {
    val bg = leg.color?.let { Color(0xFF000000 or it) } ?: Vela.routeBlue
    val fg = leg.textColor?.let { Color(0xFF000000 or it) } ?: Color.White
    Row(Modifier.height(22.dp).clip(RoundedCornerShape(5.dp)).background(bg).padding(horizontal = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        Icon(vehicleIcon(leg.vehicle), null, tint = fg, modifier = Modifier.size(12.dp))
        Text(leg.line.ifEmpty { leg.mode.lowercase().replaceFirstChar { it.uppercase() } }, fontSize = KType.caption, fontWeight = FontWeight.Bold, color = fg, maxLines = 1)
    }
}

fun vehicleIcon(v: TransitLeg.Vehicle) = when (v) {
    TransitLeg.Vehicle.WALK -> Icons.AutoMirrored.Filled.DirectionsWalk
    TransitLeg.Vehicle.BUS -> Icons.Filled.DirectionsBus
    TransitLeg.Vehicle.METRO -> Icons.Filled.Subway
    TransitLeg.Vehicle.TRAM -> Icons.Filled.Tram
    TransitLeg.Vehicle.TRAIN -> Icons.Filled.Train
    TransitLeg.Vehicle.FERRY -> Icons.Filled.DirectionsBoat
    TransitLeg.Vehicle.OTHER -> Icons.Filled.DirectionsTransit
}
