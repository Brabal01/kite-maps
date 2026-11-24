package app.kite.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.ExitToApp
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Place
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.kite.*
import app.kite.core.IndoorMaps
import app.kite.core.LatLng
import app.kite.core.Place

@Composable
fun IndoorPlaceActions(model: AppModel, place: Place, station: Boolean) {
    var access by remember(place.id) { mutableStateOf(false) }
    val context = LocalContext.current
    val isSantovka = place.name.contains("Šantovka", ignoreCase = true) &&
        place.location.distanceTo(LatLng(49.5861, 17.2587)) < 1000
    Column {
        IconRow(Icons.Filled.Apartment, "Indoor floors", trailing = if (model.loadingIndoor) "Loading…" else "View map") {
            model.openIndoor(place)
        }
        if (station) IconRow(Icons.Filled.ExitToApp, "Station entrances and exits", trailing = "View") { access = true }
        if (isSantovka) IconRow(Icons.Filled.Map, "Official Galerie Šantovka floor map", trailing = "Open") {
            context.open("https://www.galeriesantovka.cz/obchody/mapa-centra/")
        }
    }
    if (access) StationAccessDialog(place.location, { access = false }) {
        access = false
        model.showStationEntrance(it)
    }
}

@Composable
fun IndoorFloorOverlay(model: AppModel, view: AppModel.IndoorView) {
    BackHandler(onBack = model::closeIndoor)
    Box(Modifier.fillMaxSize().systemBarsPadding().padding(12.dp)) {
        Row(Modifier.align(Alignment.TopCenter).fillMaxWidth().clip(RoundedCornerShape(18.dp))
            .background(interfaceSheet).padding(start = 16.dp, end = 6.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).padding(vertical = 9.dp)) {
                Text(view.place.name, color = primaryText, fontSize = KType.headline, fontWeight = FontWeight.Bold, maxLines = 1)
                Text("Indoor floors · OpenStreetMap", color = secondaryText, fontSize = KType.caption)
            }
            TextButton(model::closeIndoor) { Text("Done") }
        }
        LazyColumn(Modifier.align(Alignment.CenterEnd).heightIn(max = 330.dp)
            .clip(RoundedCornerShape(18.dp)).background(interfaceSheet),
            contentPadding = PaddingValues(6.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            items(view.plan.floors, key = { it }) { floor ->
                val selected = floor == view.floor
                FilterChip(selected, { model.setIndoorFloor(floor) }, label = { Text(floor) })
            }
        }
    }
}

@Composable
fun StationAccessDialog(at: LatLng, onClose: () -> Unit, onMap: (LatLng) -> Unit) {
    var entrances by remember(at) { mutableStateOf<List<IndoorMaps.Entrance>?>(null) }
    var finished by remember(at) { mutableStateOf(false) }
    LaunchedEffect(at) {
        entrances = IndoorMaps.entrances(at)
        finished = true
    }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text("Entrances and exits nearby") },
        text = {
            val pins = entrances
            when {
                !finished -> CircularProgressIndicator(Modifier.size(24.dp))
                pins.isNullOrEmpty() -> Text("No station access points found in OpenStreetMap.")
                else -> LazyColumn(Modifier.heightIn(max = 370.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    items(pins, key = { "${it.at.lat},${it.at.lng}" }) { pin ->
                        val accessibility = when (pin.wheelchair) {
                            true -> " · Wheelchair accessible"
                            false -> " · Not wheelchair accessible"
                            null -> ""
                        }
                        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(interfaceSurface)
                            .tap { onMap(pin.at) }.padding(9.dp), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                            Icon(Icons.Filled.Place, null, tint = interfaceAccentText)
                            Column(Modifier.weight(1f)) {
                                Text(pin.name, fontWeight = FontWeight.SemiBold)
                                Text(Fmt.distance(pin.at.distanceTo(at)) + accessibility,
                                    color = secondaryText, fontSize = KType.caption)
                            }
                            Icon(Icons.Filled.Map, "Show on map", tint = interfaceAccentText)
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClose) { Text("Done") } }
    )
}
