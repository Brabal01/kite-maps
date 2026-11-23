@file:OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package app.kite.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kite.*
import app.kite.core.GoogleClient
import app.kite.core.Place
import kotlinx.coroutines.CancellationException

@Composable
internal fun StopResultsPage(search: StopSearch, list: LazyListState, close: () -> Unit, showOnMap: (StopCandidate) -> Unit) {
    var expandedId by rememberSaveable { mutableStateOf<String?>(null) }
    val galleries = remember { mutableStateMapOf<String, List<String>>() }
    val allowsGoogle = !AppSettings.noGoogle
    val expandedPlace = search.results.firstOrNull { it.place.id == expandedId }?.place
    val photoId = expandedPlace?.featureId?.takeIf { allowsGoogle && expandedPlace.photoUrls.size < 4 }
    LaunchedEffect(photoId) {
        if (photoId == null || galleries.containsKey(photoId)) return@LaunchedEffect
        galleries[photoId] = try {
            GoogleClient.shared.photos(photoId).take(4)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            emptyList()
        }
    }

    FullScreenDialog(close) {
        Column(Modifier.fillMaxSize().background(interfaceSheet).systemBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(if (search.parking) "Parking near destination" else search.query.replaceFirstChar { it.titlecase() },
                        fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = primaryText,
                        maxLines = 2, overflow = TextOverflow.Ellipsis)
                    val count = search.results.size
                    Text(if (count == 1) "1 result" else "$count results", fontSize = KType.subheadline, color = secondaryText)
                }
                FilledTonalButton(onClick = close, contentPadding = PaddingValues(horizontal = 12.dp)) {
                    Icon(Icons.Outlined.Map, null, Modifier.size(19.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Map")
                }
            }
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                state = list,
                contentPadding = PaddingValues(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                itemsIndexed(search.results, key = { _, candidate -> candidate.place.id }) { index, candidate ->
                    val place = candidate.place
                    val selected = place.id == search.selected?.place?.id
                    val expanded = place.id == expandedId
                    val distance = if (search.parking) "${Fmt.distance(candidate.offset)} from destination"
                        else candidate.ahead?.let { "${Fmt.distance(it)} ahead" }
                    val detour = search.detours[place.id]?.let(::detourShort)
                    Surface(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(18.dp),
                        color = interfaceGround,
                        border = if (selected) BorderStroke(1.dp, interfaceAccentText.copy(alpha = 0.6f)) else null,
                    ) {
                        Column {
                            PlaceResultSummary(
                                place, onOpen = { showOnMap(candidate) }, mapNumber = index + 1,
                                mapSelected = selected, openLabel = "Show on map",
                                supporting = {
                                    if (distance != null || detour != null) {
                                        FlowRow(Modifier.padding(top = 3.dp), horizontalArrangement = Arrangement.spacedBy(5.dp),
                                            verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                            distance?.let { StopMetric(Icons.Filled.Place, it) }
                                            detour?.let { StopMetric(Icons.Outlined.Schedule, it) }
                                        }
                                    }
                                },
                            ) {
                                FilledTonalIconButton(
                                    { expandedId = if (expanded) null else place.id },
                                    modifier = Modifier.size(48.dp),
                                    colors = IconButtonDefaults.filledTonalIconButtonColors(
                                        containerColor = if (expanded) interfaceAccent else interfaceSurface,
                                        contentColor = if (expanded) interfaceOnAccent else interfaceAccentText,
                                    ),
                                ) {
                                    Icon(if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                                        if (expanded) "Collapse details for ${place.name}" else "Expand details for ${place.name}")
                                }
                            }
                            if (expanded) StopResultDetails(
                                place, morePhotos = photoId?.let { galleries[it] }.orEmpty(),
                                loadingPhotos = photoId != null && !galleries.containsKey(photoId),
                                showOnMap = { showOnMap(candidate) },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StopMetric(icon: ImageVector, label: String) {
    Row(Modifier.background(interfaceSurface, CircleShape).padding(horizontal = 7.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(13.dp), tint = interfaceAccentText)
        Text(label, fontSize = KType.caption2, fontWeight = FontWeight.SemiBold, color = primaryText)
    }
}

@Composable
private fun StopResultDetails(place: Place, morePhotos: List<String>, loadingPhotos: Boolean, showOnMap: () -> Unit) {
    var hoursOpen by rememberSaveable(place.id) { mutableStateOf(false) }
    val photos = (place.photoUrls + morePhotos).filterNot { AppSettings.noGoogle && isGooglePhoto(it) }
        .distinctBy { it.substringBeforeLast("=w") }.take(4)
    val summary = place.editorialSummary?.takeIf(String::isNotBlank)
    val website = place.website?.takeIf(String::isNotBlank)?.removePrefix("https://")?.removePrefix("http://")
    Column(Modifier.padding(start = 12.dp, end = 12.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        HorizontalDivider(color = secondaryText.copy(alpha = 0.15f))
        if (photos.isNotEmpty()) {
            PhotoStrip(photos, height = 100.dp)
            if (photos.any(::isGooglePhoto)) Text("Photos from Google Maps", fontSize = KType.caption2, color = secondaryText)
        } else if (loadingPhotos) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                Text("Loading photos…", fontSize = KType.caption, color = secondaryText)
            }
        }
        summary?.let { Text(it, fontSize = KType.footnote, color = primaryText, maxLines = 4, overflow = TextOverflow.Ellipsis) }
        place.address?.let { InfoRow(Icons.Outlined.Place, it) }
        if (place.hours.isNotEmpty()) OpeningHoursCard(place, hoursOpen) { hoursOpen = !hoursOpen }
        place.phone?.let { InfoRow(Icons.Outlined.Phone, it) }
        website?.let { InfoRow(Icons.Filled.Language, it) }
        if (summary == null && photos.isEmpty() && place.address.isNullOrBlank() && place.hours.isEmpty() &&
            place.phone.isNullOrBlank() && website == null && !loadingPhotos) {
            Text("No additional details available", fontSize = KType.caption, color = secondaryText)
        }
        OutlinedButton(onClick = showOnMap, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Outlined.Map, null, Modifier.size(18.dp))
            Spacer(Modifier.width(7.dp))
            Text("Show on map")
        }
    }
}
