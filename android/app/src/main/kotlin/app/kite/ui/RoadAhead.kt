package app.kite.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material.icons.filled.Traffic
import androidx.compose.material.icons.filled.Train
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import app.kite.core.TravelMode
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
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
import app.kite.interfaceSurface
import app.kite.LocalDark
import app.kite.LocalMapChrome
import app.kite.primaryText
import app.kite.secondaryText
import app.kite.KType

private data class AheadMarker(val distance: Double, val name: String, val icon: ImageVector, val color: Color, val alert: WazeAlert? = null)

@Composable
fun RoadAheadStrip(nav: Navigator, modifier: Modifier = Modifier, showLabels: Boolean = true,
                   verticalHeight: androidx.compose.ui.unit.Dp? = null, onAlert: (WazeAlert) -> Unit = {}) {
    val progress = nav.progress
    if ((progress?.offsetMeters ?: 0.0) > 120 || (progress?.remainingMeters ?: nav.route.distanceMeters) <= 0) return
    val start = progress?.alongMeters ?: 0.0
    val walking = nav.route.mode == TravelMode.WALK
    val range = (progress?.remainingMeters ?: nav.route.distanceMeters).coerceIn(1.0, if (walking) 600.0 else 3_000.0)
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
            Overpass.ControlKind.CROSSING -> AheadMarker(distance, "Pedestrian crossing", Icons.AutoMirrored.Filled.DirectionsWalk,
                if (dark) Color(0xFF98D9F0) else Color(0xFF126782))
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

    if (walking && verticalHeight != null) {
        if (markers.isEmpty()) return
        val count = ((verticalHeight.value - 12) / 53).toInt().coerceIn(1, 3)
        Column(modifier.width(66.dp).glass(RoundedCornerShape(17.dp), solid = true).padding(vertical = 6.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            for (marker in markers.take(count)) {
                Column(Modifier.fillMaxWidth().height(53.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center) {
                    Icon(marker.icon, marker.name, Modifier.size(23.dp), tint = marker.color)
                    Text(Fmt.distance(marker.distance), fontSize = KType.caption2, fontWeight = FontWeight.SemiBold, color = primaryText)
                }
            }
        }
        return
    }

    val vertical = verticalHeight != null
    val railColor = if (dark) Color(0xFF667994) else Color(0xFF90A6BC)
    val railEdge = if (dark) Color(0xFF1E2B41) else Color(0xFFDCE6EF)
    val origin = LocalMapChrome.current?.accent ?: if (dark) Color(0xFF82E6D8) else Color(0xFF0B8074)
    val shape = RoundedCornerShape(if (vertical) 27.dp else 19.dp)
    val stripSize = if (vertical) Modifier.width(51.dp).height(requireNotNull(verticalHeight))
        else Modifier.fillMaxWidth()
    Column(modifier.then(stripSize).glass(shape, solid = true).padding(if (vertical) 5.dp else 8.dp)) {
        if (showLabels && !vertical) Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp),
            horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Road ahead", color = primaryText, fontSize = KType.caption, fontWeight = FontWeight.SemiBold)
            val incident = traffic.minByOrNull { it.startMeters }
            val label = when (incident?.level) {
                1 -> "Slow traffic"
                2 -> "Heavy traffic"
                3 -> "Standstill traffic"
                else -> null
            }
            Text(label?.let { if (incident != null && incident.startMeters > start)
                "$it · ${Fmt.distance(incident.startMeters - start)}" else it } ?: Fmt.distance(range),
                color = secondaryText, fontSize = KType.caption)
        }
        val badge = 32.dp
        BoxWithConstraints(if (vertical) Modifier.fillMaxSize()
            else Modifier.fillMaxWidth().height(if (markers.isEmpty()) 14.dp else 38.dp)) {
            val length = (if (vertical) maxHeight else maxWidth) - badge
            Canvas(Modifier.fillMaxSize()) {
                val inset = (badge / 2).toPx()
                fun point(distance: Double): Offset {
                    val f = (distance / range).coerceIn(0.0, 1.0).toFloat()
                    return if (vertical) Offset(size.width / 2, size.height - inset - f * (size.height - 2 * inset))
                    else Offset(inset + f * (size.width - 2 * inset), size.height / 2)
                }
                drawLine(railEdge, point(0.0), point(range), strokeWidth = 12.dp.toPx(), cap = StrokeCap.Round)
                drawLine(railColor, point(0.0), point(range), strokeWidth = 6.dp.toPx(), cap = StrokeCap.Round)
                for (span in traffic) {
                    val color = when (span.level) {
                        1 -> Color(0xFFF59E0B)
                        2 -> Color(0xFFF05240)
                        else -> Color(0xFFC01E40)
                    }
                    drawLine(color, point(span.startMeters - start), point(span.startMeters + span.lengthMeters - start),
                        strokeWidth = 6.dp.toPx(), cap = StrokeCap.Round)
                }
                drawCircle(origin, radius = 5.dp.toPx(), center = point(0.0))
            }
            val spacing = range * ((badge + 3.dp) / length.coerceAtLeast(1.dp))
            var last = -spacing
            for (marker in markers) {
                if (marker.distance - last < spacing) continue
                last = marker.distance
                val offset = length * (marker.distance / range).toFloat()
                val action = marker.alert?.let { alert -> Modifier.clickable { onAlert(alert) } } ?: Modifier
                val position = if (vertical) Modifier.align(Alignment.TopCenter).offset(y = length - offset)
                    else Modifier.align(Alignment.CenterStart).offset(x = offset)
                Box(position.size(badge).background(interfaceSurface, CircleShape)
                    .border(1.5.dp, marker.color.copy(alpha = 0.72f), CircleShape)
                    .then(action), contentAlignment = Alignment.Center) {
                    Icon(marker.icon, "${marker.name}, ${Fmt.distance(marker.distance)} ahead",
                        tint = if (marker.color.luminance() < 0.20f && dark) Color.White else marker.color,
                        modifier = Modifier.size(23.dp))
                }
            }
        }
    }
}
