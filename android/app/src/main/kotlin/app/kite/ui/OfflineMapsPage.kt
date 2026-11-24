package app.kite.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.kite.*
import app.kite.core.LatLng

@Composable
internal fun OfflineMapsPage(model: AppModel) {
    LaunchedEffect(Unit) { OfflineMaps.load() }
    var name by remember { mutableStateOf("") }
    var radius by remember { mutableFloatStateOf(6f) }
    var removing by remember { mutableStateOf<OfflineMaps.Area?>(null) }
    val areas = OfflineMaps.areas.values.sortedBy { it.id }
    SettingsGroup(header = "Download around the current map center",
        footer = "Stores the OpenStreetMap basemap. Route calculation, live departures and traffic need a connection.") {
        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(name, { name = it }, label = { Text("Area name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Text("Download radius · ${radius.toInt()} km", color = primaryText)
            Slider(radius, { radius = it }, valueRange = 2f..15f, steps = 12)
            Button({ OfflineMaps.download(name, model.visibleCamera?.invoke()?.target?.kite() ?: model.viewport.first, radius) },
                enabled = Connectivity.online && !OfflineMaps.creating && areas.none { it.active }) {
                Icon(Icons.Filled.Download, null)
                Spacer(Modifier.width(6.dp))
                Text("Download area")
            }
        }
    }
    if (model.offlineMapShown) TextButton({ model.offlineMapShown = false; model.tab = AppTab.MAP }) { Text("Return to the online map") }
    OfflineMaps.message?.let { Text(it, color = secondaryText) }
    for (area in areas) Surface(color = interfaceSurface, shape = RoundedCornerShape(18.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(area.name, color = primaryText, fontWeight = FontWeight.Bold)
            val size = android.text.format.Formatter.formatShortFileSize(KiteApp.app, area.bytes)
            Text((if (area.complete) "Available offline" else if (area.active) "Downloading" else "Paused") + " · $size", color = secondaryText)
            if (area.active) {
                val progress = area.progress
                if (progress != null) LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth())
                else LinearProgressIndicator(Modifier.fillMaxWidth())
            }
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (area.complete) TextButton({
                    val c = area.bounds.center
                    model.offlineFocus = LatLng(c.latitude, c.longitude)
                    model.offlineMapShown = true
                    model.tab = AppTab.MAP
                }) { Text("Open map") }
                else if (area.active) TextButton({ OfflineMaps.stop(area.id) }) { Text("Pause") }
                else TextButton({ OfflineMaps.resume(area.id) }, enabled = Connectivity.online && areas.none { it.active }) { Text("Resume") }
                TextButton({ removing = area }) { Text("Remove") }
            }
        }
    }
    removing?.let { area ->
        AlertDialog(onDismissRequest = { removing = null }, title = { Text("Remove ${area.name}?") },
            text = { Text("This area will no longer be kept for offline use.") },
            confirmButton = { TextButton({ OfflineMaps.delete(area.id); removing = null }) { Text("Remove") } },
            dismissButton = { TextButton({ removing = null }) { Text("Cancel") } })
    }
}
