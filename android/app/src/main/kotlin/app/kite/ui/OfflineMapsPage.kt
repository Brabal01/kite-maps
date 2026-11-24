package app.kite.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.kite.*
import app.kite.core.LatLng

@Composable
internal fun OfflineMapsPage(model: AppModel) {
    LaunchedEffect(Unit) { OfflineMaps.load() }
    var removing by remember { mutableStateOf<OfflineMaps.Area?>(null) }
    var selected by remember { mutableStateOf<OfflineRegions.Region?>(null) }
    var parentId by rememberSaveable { mutableStateOf<String?>(null) }
    var query by rememberSaveable { mutableStateOf("") }
    val areas = OfflineMaps.areas.values.sortedWith(compareByDescending<OfflineMaps.Area> { it.active }.thenByDescending { it.id })
    var downloads by rememberSaveable { mutableStateOf(areas.isNotEmpty()) }
    val catalogue = remember { OfflineRegions.catalogue }
    val grouped = remember(catalogue) { catalogue.groupBy { it.parent } }
    val parent = catalogue.firstOrNull { it.id == parentId }
    val parts = remember(parentId, query) {
        if (query.isBlank()) grouped[parentId].orEmpty()
        else catalogue.filter { it.parent != null && it.name.contains(query.trim(), ignoreCase = true) }.take(40)
    }

    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        SegmentedButton(downloads, { downloads = true }, SegmentedButtonDefaults.itemShape(0, 2)) {
            Text("Downloads${if (areas.isNotEmpty()) " · ${areas.size}" else ""}")
        }
        SegmentedButton(!downloads, { downloads = false }, SegmentedButtonDefaults.itemShape(1, 2)) { Text("Browse regions") }
    }
    OfflineMaps.message?.let { Text(it, color = Vela.closed, modifier = Modifier.padding(vertical = 6.dp)) }
    if (downloads) {
        OfflineMaps.pendingName?.let { name ->
            OfflineCard(name, "Preparing download", Icons.Filled.Download) {
                LinearProgressIndicator(Modifier.fillMaxWidth())
            }
        }
        if (areas.isEmpty() && !OfflineMaps.creating) {
            OfflineCard("No downloaded maps", "Pick a country or region to use its map offline.", Icons.Filled.OfflinePin) {
                Button({ downloads = false }) { Text("Browse regions") }
            }
        }
        for (area in areas) {
            val size = android.text.format.Formatter.formatShortFileSize(KiteApp.app, area.bytes)
            val progress = area.progress?.let { "${(it * 100).toInt()}%" }
            val status = when {
                area.complete -> "Available offline · $size"
                area.active && !Connectivity.online -> "Waiting for connection · $size"
                area.active && area.error != null -> "Retrying download · $size"
                area.active -> listOfNotNull("Downloading", progress, size).joinToString(" · ")
                else -> "Paused · $size"
            }
            OfflineCard(area.name, status, if (area.complete) Icons.Filled.OfflinePin else Icons.Filled.Download) {
                if (area.active) {
                    if (area.progress != null) LinearProgressIndicator(progress = { area.progress }, modifier = Modifier.fillMaxWidth())
                    else LinearProgressIndicator(Modifier.fillMaxWidth())
                    if (area.resources > 0) Text("${area.resources} map resources saved", color = secondaryText, fontSize = KType.caption)
                    area.error?.let { Text(it, color = secondaryText, fontSize = KType.caption) }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (area.complete) FilledTonalButton({
                        val c = area.bounds.center
                        model.offlineFocus = LatLng(c.latitude, c.longitude) to minOf(13.0, area.maxZoom - 1.0)
                        model.offlineMapShown = true
                        model.tab = AppTab.MAP
                    }) { Text("Open map") }
                    else if (area.active) TextButton({ OfflineMaps.stop(area.id) }) { Text("Pause") }
                    else TextButton({ OfflineMaps.resume(area.id) }, enabled = Connectivity.online && !OfflineMaps.creating &&
                        areas.none { it.active }) { Text("Resume") }
                    TextButton({ removing = area }) { Text("Remove") }
                }
            }
        }
        if (model.offlineMapShown) TextButton({ model.offlineMapShown = false; model.tab = AppTab.MAP }) { Text("Return to the online map") }
    } else {
        OutlinedTextField(query, { query = it }, leadingIcon = { Icon(Icons.Filled.Search, null) },
            label = { Text("Find a country or region") }, singleLine = true,
            modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(15.dp))
        SettingsGroup(header = if (query.isNotBlank()) "Search results" else parent?.name ?: "Continents",
            footer = "Regions from Geofabrik and Eurostat GISCO. Smaller areas include more street detail.") {
            if (parent != null && query.isBlank()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    TextButton({ parentId = parent.parent }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Back")
                    }
                    Spacer(Modifier.weight(1f))
                    if (parent.parent != null || parts.isEmpty()) TextButton({ selected = parent }) { Text("Whole area") }
                }
            }
            for (region in parts) {
                val children = grouped[region.id].orEmpty()
                val saved = areas.firstOrNull { it.name == region.name }
                Row(Modifier.fillMaxWidth().heightIn(min = 58.dp)
                    .tap {
                        if (children.isNotEmpty()) { parentId = region.id; query = "" }
                        else if (saved != null) downloads = true
                        else selected = region
                    }.padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(11.dp)) {
                    Box(Modifier.size(33.dp).clip(CircleShape).background(interfaceAccent.copy(alpha = 0.12f)),
                        contentAlignment = Alignment.Center) {
                        Icon(if (children.isEmpty()) Icons.Filled.Map else Icons.Filled.Public, null,
                            Modifier.size(17.dp), tint = interfaceAccentText)
                    }
                    Column(Modifier.weight(1f)) {
                        Text(region.name, color = primaryText, fontWeight = FontWeight.SemiBold)
                        val info = when {
                            saved?.complete == true -> "Available offline"
                            saved?.active == true -> "Downloading"
                            children.isNotEmpty() -> "${children.size} areas"
                            else -> null
                        }
                        if (info != null) Text(info, color = secondaryText, fontSize = KType.caption)
                    }
                    Icon(if (children.isNotEmpty()) Icons.AutoMirrored.Filled.KeyboardArrowRight
                        else if (saved?.complete == true) Icons.Filled.Check else Icons.Filled.Download,
                        if (children.isNotEmpty()) "Open regions" else "Download", tint = interfaceAccentText)
                }
                HorizontalDivider(Modifier.padding(start = 57.dp))
            }
            if (parts.isEmpty()) Text("No regions found", Modifier.padding(14.dp), color = secondaryText)
        }
    }
    selected?.let { region ->
        AlertDialog(onDismissRequest = { selected = null },
            title = { Text("Download ${region.name}") },
            text = { Text("Stores the basemap for this area. For more street detail, download a smaller region.") },
            confirmButton = {
                TextButton({ OfflineMaps.download(region); selected = null; downloads = true }, enabled = Connectivity.online &&
                    !OfflineMaps.creating && areas.none { it.active || it.name == region.name }) { Text("Download") }
            },
            dismissButton = { TextButton({ selected = null }) { Text("Cancel") } })
    }
    removing?.let { area ->
        AlertDialog(onDismissRequest = { removing = null }, title = { Text("Remove ${area.name}?") },
            text = { Text("This area will no longer be kept for offline use.") },
            confirmButton = { TextButton({ OfflineMaps.delete(area.id); removing = null }) { Text("Remove") } },
            dismissButton = { TextButton({ removing = null }) { Text("Cancel") } })
    }
}

@Composable
private fun OfflineCard(title: String, subtitle: String, icon: androidx.compose.ui.graphics.vector.ImageVector,
                        content: @Composable ColumnScope.() -> Unit) {
    Surface(Modifier.fillMaxWidth(), color = interfaceSurface, shape = RoundedCornerShape(22.dp)) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(11.dp)) {
                Icon(icon, null, tint = interfaceAccentText)
                Column(Modifier.weight(1f)) {
                    Text(title, color = primaryText, fontWeight = FontWeight.Bold)
                    Text(subtitle, color = secondaryText, fontSize = KType.caption)
                }
            }
            content()
        }
    }
}
