package app.kite.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import app.kite.core.Geo
import app.kite.core.Route
import app.kite.core.Valhalla
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

@Composable
fun RoutePathSections(route: Route, model: AppModel) {
    var expanded by remember(route.id) { mutableStateOf(false) }
    var sections by remember(route.id) { mutableStateOf<List<Valhalla.PathSection>?>(null) }
    var selected by remember(route.id) { mutableStateOf<Valhalla.PathSection?>(null) }
    LaunchedEffect(route.id, expanded) {
        if (expanded && sections == null) sections = Valhalla.pathSections(route)
    }
    IconRow(Icons.Filled.Terrain, "Surface & path type", trailing = if (expanded) "Hide" else "Show") {
        expanded = !expanded
    }
    if (!expanded) return
    val known = sections
    if (known == null) {
        CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
        return
    }
    if (known.isEmpty()) {
        Text("Surface and path data unavailable.", color = secondaryText)
        return
    }
    val total = remember(route.id) { Geo.length(route.polyline) }
    val unknown = secondaryText.copy(alpha = 0.20f)
    val natural = Vela.open
    val paved = interfaceAccentText
    val rough = androidx.compose.ui.graphics.Color(0xFFB36A30)
    fun tint(surface: String?) = when (surface) {
        "paved_smooth", "paved", "paved_rough" -> paved
        "gravel", "compacted", "dirt" -> rough
        "path", "grass" -> natural
        else -> unknown
    }
    Canvas(Modifier.fillMaxWidth().height(9.dp)) {
        drawRect(unknown)
        for (section in known) {
            val start = (section.from / total).toFloat() * size.width
            val width = ((section.to - section.from) / total).toFloat() * size.width
            drawRect(tint(section.surface),
                topLeft = androidx.compose.ui.geometry.Offset(start, 0f),
                size = androidx.compose.ui.geometry.Size(width, size.height))
        }
    }
    Column(Modifier.heightIn(max = 240.dp).verticalScroll(rememberScrollState())) {
        for (section in known) {
            val surface = section.surface?.let {
                when (it) {
                    "paved_smooth" -> "Smooth pavement"
                    "paved_rough" -> "Rough pavement"
                    "path" -> "Natural surface"
                    else -> pathLabel(it)
                }
            } ?: "Surface unknown"
            val type = section.type?.let(::pathLabel) ?: "Path type unknown"
            Column(Modifier.fillMaxWidth().tap {
                selected = section
                model.framePathSection(route, section)
            }.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("$surface · $type", color = if (selected == section) paved else primaryText, fontSize = KType.subheadline)
                Text("${Fmt.distance(section.from)} – ${Fmt.distance(section.to)}", color = secondaryText, fontSize = KType.caption)
            }
        }
    }
    Text("Path data from OpenStreetMap via Valhalla", color = secondaryText, fontSize = KType.caption)
}

private fun pathLabel(value: String): String = value.replace('_', ' ').replaceFirstChar(Char::uppercaseChar)
