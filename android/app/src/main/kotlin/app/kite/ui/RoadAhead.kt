package app.kite.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material.icons.filled.Traffic
import androidx.compose.material.icons.filled.Train
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.kite.AppSettings
import app.kite.Navigator
import app.kite.MapIcons
import app.kite.core.WazeAlert
import androidx.compose.foundation.clickable
import app.kite.Fmt
import app.kite.core.Overpass
import app.kite.glass
import app.kite.LocalDark
import app.kite.primaryText
import app.kite.secondaryText
import app.kite.KType

private data class AheadMarker(val distance: Double, val name: String, val icon: ImageVector, val color: Color, val alert: WazeAlert? = null)

@Composable
fun RoadAheadStrip(nav: Navigator, modifier: Modifier = Modifier, showLabels: Boolean = true, onAlert: (WazeAlert) -> Unit = {}) {
    val progress = nav.progress ?: return
    if (progress.offRoute || progress.remainingMeters <= 0) return
    val start = progress.alongMeters
    val range = progress.remainingMeters.coerceIn(1.0, 3_000.0)
    val end = start + range
    val dark = LocalDark.current
    val traffic = nav.roadTraffic.filter { it.startMeters < end && it.startMeters + it.lengthMeters > start }
    val controls = nav.roadControls.asSequence().filter { it.along in start..end && AppSettings.showsControl(it.kind) }.map {
        val distance = it.along - start
        when (it.kind) {
            Overpass.ControlKind.SIGNAL -> AheadMarker(distance, "Traffic lights", Icons.Filled.Traffic,
                if (dark) Color(0xFFA8CBFF) else Color(0xFF29558C))
            Overpass.ControlKind.STOP -> AheadMarker(distance, "Stop sign", Icons.Filled.StopCircle,
                if (dark) Color(0xFFFF8D88) else Color(0xFFB11F32))
            Overpass.ControlKind.RAIL -> AheadMarker(distance, "Railroad crossing", Icons.Filled.Train,
                if (dark) Color(0xFFFFCD80) else Color(0xFF835021))
        }
    }
    val cameras = nav.routeCameras.asSequence().filter { AppSettings.aheadCameras && it.along in start..end && !it.camera.quiet }
        .map { AheadMarker(it.along - start, "Camera", Icons.Filled.PhotoCamera, if (dark) Color(0xFFDBC5FF) else Color(0xFF643894)) }
    val reports = nav.routeWaze.asSequence().filter {
        it.along in start..end && AppSettings.showsOnRoad(it.alert)
    }.map { AheadMarker(it.along - start, it.alert.title, MapIcons.wazeIcon(it.alert.kind),
        Color(0xFF000000 or MapIcons.wazeColor(it.alert.kind)), it.alert) }
    val markers = (reports + controls + cameras).sortedBy { it.distance }.toList()

    Column(modifier.fillMaxWidth().glass(RoundedCornerShape(18.dp)).padding(horizontal = 12.dp, vertical = 6.dp)) {
        if (showLabels) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("Road ahead", color = primaryText, fontSize = KType.caption, fontWeight = FontWeight.SemiBold)
                val congestion = traffic.minByOrNull { it.startMeters }
                val status = congestion?.let {
                    val label = when (it.level) {
                        1 -> "Slow traffic"
                        2 -> "Heavy traffic"
                        else -> "Standstill traffic"
                    }
                    if (it.startMeters <= start) label else "$label · ${Fmt.distance(it.startMeters - start)}"
                }
                Text(status ?: Fmt.distance(range), color = secondaryText, fontSize = KType.caption)
            }
        }
        val base = if (dark) Color(0xFF698298) else Color(0xFF9BABB6)
        val startColor = if (dark) Color(0xFF87E8DA) else Color(0xFF007B70)
        val dualRows = showLabels && markers.any { it.alert != null } && markers.any { it.alert == null }
        val height = if (markers.isEmpty()) 12.dp else if (dualRows) 52.dp else 32.dp
        BoxWithConstraints(Modifier.fillMaxWidth().height(height)) {
            val width = (maxWidth - 24.dp).coerceAtLeast(1.dp)
            Canvas(Modifier.fillMaxWidth().align(Alignment.BottomCenter).height(10.dp)) {
                val left = 12.dp.toPx()
                val right = size.width - left
                val y = size.height / 2
                fun x(along: Double) = left + ((along - start) / range).coerceIn(0.0, 1.0).toFloat() * (right - left)
                drawLine(base, Offset(left, y), Offset(right, y), strokeWidth = 4.dp.toPx(), cap = StrokeCap.Round)
                for (span in traffic) {
                    val color = when (span.level) {
                        1 -> Color(0xFFF59E0B)
                        2 -> Color(0xFFF05240)
                        else -> Color(0xFFB91C3C)
                    }
                    drawLine(color, Offset(x(span.startMeters), y), Offset(x(span.startMeters + span.lengthMeters), y),
                        strokeWidth = 4.dp.toPx(), cap = StrokeCap.Round)
                }
                drawCircle(startColor, radius = 3.7.dp.toPx(), center = Offset(left, y))
            }
            val spacing = range * (23.dp / width)
            val rows = if (dualRows) markers.partition { it.alert != null }.let { listOf(it.first, it.second) }
                else listOf(markers)
            for ((row, candidates) in rows.withIndex()) {
                var last = -spacing
                for (marker in candidates) {
                    if (marker.distance - last < spacing) continue
                    last = marker.distance
                    val offset = width * (marker.distance / range).toFloat()
                    val action = marker.alert?.let { alert -> Modifier.clickable { onAlert(alert) } } ?: Modifier
                    Box(Modifier.offset(x = offset + 1.dp, y = (row * 20).dp).size(22.dp)
                        .background(marker.color.copy(alpha = 0.13f), CircleShape).then(action), contentAlignment = Alignment.Center) {
                        Icon(marker.icon, "${marker.name}, ${Fmt.distance(marker.distance)} ahead", tint = marker.color,
                            modifier = Modifier.size(16.dp))
                    }
                }
            }
        }
    }
}
