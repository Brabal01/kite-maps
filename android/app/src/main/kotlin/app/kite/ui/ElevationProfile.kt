package app.kite.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Terrain
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import app.kite.*
import app.kite.core.Route
import kotlin.math.roundToInt

@Composable
fun RouteElevation(route: Route) {
    var expanded by remember(route.id) { mutableStateOf(false) }
    var loaded by remember(route.id) { mutableStateOf(false) }
    var profile by remember(route.id) { mutableStateOf<ElevationProfile.Result?>(null) }
    LaunchedEffect(route.id, expanded) {
        if (expanded && !loaded) {
            profile = ElevationProfile.sample(route)
            loaded = true
        }
    }
    IconRow(Icons.Filled.Terrain, "Elevation profile", trailing = if (expanded) "Hide" else "Show") { expanded = !expanded }
    if (!expanded) return
    val data = profile
    if (data == null) {
        if (loaded) Text("Elevation data unavailable.", color = secondaryText)
        else CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
        return
    }
    val color = Vela.accentText(LocalDark.current)
    val low = data.heights.min()
    val high = data.heights.max()
    Text("↑ ${data.ascent.roundToInt()} m   ↓ ${data.descent.roundToInt()} m", color = primaryText)
    Canvas(Modifier.fillMaxWidth().height(100.dp).padding(vertical = 4.dp)) {
        val line = Path()
        val span = (high - low).coerceAtLeast(15.0)
        for ((index, elevation) in data.heights.withIndex()) {
            val x = index.toFloat() / data.heights.lastIndex * size.width
            val y = (size.height - (elevation - low) / span * size.height).toFloat()
            if (index == 0) line.moveTo(x, y) else line.lineTo(x, y)
        }
        val area = Path().apply {
            addPath(line)
            lineTo(size.width, size.height)
            lineTo(0f, size.height)
            close()
        }
        drawPath(area, color.copy(alpha = 0.17f))
        drawPath(line, color, style = Stroke(width = 2.dp.toPx()))
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text("${low.roundToInt()}–${high.roundToInt()} m", color = secondaryText, fontSize = KType.caption)
        Text(Fmt.distance(route.distanceMeters), color = secondaryText, fontSize = KType.caption)
    }
    Text("Terrain data from Mapzen · AWS Open Data", color = secondaryText, fontSize = KType.caption)
}
