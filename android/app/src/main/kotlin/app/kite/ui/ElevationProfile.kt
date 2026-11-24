package app.kite.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.kite.*
import app.kite.core.Geo
import app.kite.core.Route
import app.kite.core.Valhalla
import kotlin.math.roundToInt

@Composable
fun RouteProfileOverlay(model: AppModel, route: Route) {
    BackHandler(onBack = model::closeProfile)
    LaunchedEffect(route.id) { model.routeProfiles.load(route) }
    val entry = model.routeProfiles[route]
    val cumulative = remember(route.id) { Geo.cumulative(route.polyline) }
    val distance = cumulative.lastOrNull() ?: 0.0
    var surfaceTab by remember(route.id) { mutableStateOf(false) }
    BoxWithConstraints(Modifier.fillMaxSize().systemBarsPadding()) {
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(maxHeight * 0.49f)
            .clip(RoundedCornerShape(topStart = 26.dp, topEnd = 26.dp)).background(interfaceSheet)
            .padding(horizontal = 16.dp, vertical = 10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Route profile", Modifier.weight(1f), color = primaryText, fontSize = KType.headline, fontWeight = FontWeight.Bold)
                TextButton(model::closeProfile) { Text("Done") }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(!surfaceTab, { surfaceTab = false }, label = { Text("Elevation") })
                FilterChip(surfaceTab, { surfaceTab = true }, label = { Text("Surface") })
            }
            Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (surfaceTab) {
                    val sections = entry?.surfaces
                    when {
                        sections == null -> CircularProgressIndicator(Modifier.size(24.dp))
                        sections.isEmpty() -> Text("Surface data unavailable.", color = secondaryText)
                        else -> SurfaceChart(sections, route, model, distance)
                    }
                    if (entry != null && !entry.fullSurface && distance > PREFETCH_SURFACE_METERS) {
                        TextButton({ model.routeProfiles.load(route, entireSurface = true) }, enabled = !entry.loadingSurface) {
                            Text(if (entry.loadingSurface) "Loading surface…" else "Load surface for the whole route")
                        }
                    }
                    Text("OpenStreetMap via Valhalla", color = secondaryText, fontSize = KType.caption)
                } else {
                    val elevation = entry?.elevation
                    when {
                        elevation != null && distance > 0 -> ElevationChart(elevation, distance) { fraction ->
                            model.scrubProfile(Geo.point(route.polyline, distance * fraction, cumulative))
                        }
                        entry?.elevationDone == true -> Text("Elevation data unavailable.", color = secondaryText)
                        else -> CircularProgressIndicator(Modifier.size(24.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun ElevationChart(data: ElevationProfile.Result, distance: Double, scrub: (Float) -> Unit) {
    val ink = interfaceAccentText
    val grid = secondaryText.copy(alpha = 0.20f)
    val ground = interfaceSurface
    val callback by rememberUpdatedState(scrub)
    var selected by remember(data) { mutableStateOf<Float?>(null) }
    val low = data.heights.min()
    val span = (data.heights.max() - low).coerceAtLeast(15.0)
    val current = selected
    val sample = current?.let { fraction -> data.heights[(fraction * data.heights.lastIndex).roundToInt()] }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text("↑ ${data.ascent.roundToInt()} m    ↓ ${data.descent.roundToInt()} m", color = primaryText, fontSize = KType.subheadline)
        if (sample != null) Text("${sample.roundToInt()} m · ${Fmt.distance(distance * current)}", color = ink, fontSize = KType.caption)
    }
    Canvas(Modifier.fillMaxWidth().height(116.dp).clip(RoundedCornerShape(14.dp)).background(ground)
        .pointerInput(data) {
            detectTapGestures {
                val fraction = (it.x / size.width.coerceAtLeast(1)).coerceIn(0f, 1f)
                selected = fraction
                callback(fraction)
            }
        }.pointerInput(data) {
            var lastUpdate = 0L
            detectHorizontalDragGestures(onDragEnd = { selected?.let(callback) }) { change, _ ->
                val fraction = (change.position.x / size.width.coerceAtLeast(1)).coerceIn(0f, 1f)
                selected = fraction
                if (change.uptimeMillis - lastUpdate >= 50) {
                    lastUpdate = change.uptimeMillis
                    callback(fraction)
                }
            }
        }.padding(vertical = 8.dp)) {
        fun y(height: Double) = size.height * (1f - ((height - low) / span).toFloat())
        for (i in 0..3) {
            val at = size.height * i / 3
            drawLine(grid, Offset(0f, at), Offset(size.width, at))
        }
        val line = Path().apply {
            data.heights.forEachIndexed { index, height ->
                val x = size.width * index / data.heights.lastIndex
                if (index == 0) moveTo(x, y(height)) else lineTo(x, y(height))
            }
        }
        val area = Path().apply {
            addPath(line)
            lineTo(size.width, size.height)
            lineTo(0f, size.height)
            close()
        }
        drawPath(area, Brush.verticalGradient(listOf(ink.copy(alpha = 0.40f), ink.copy(alpha = 0.03f))))
        drawPath(line, ink, style = Stroke(width = 2.dp.toPx()))
        if (current != null && sample != null) {
            val x = size.width * current
            drawLine(ink, Offset(x, 0f), Offset(x, size.height), 1.dp.toPx())
            drawCircle(Color.White, 5.dp.toPx(), Offset(x, y(sample)))
            drawCircle(ink, 3.dp.toPx(), Offset(x, y(sample)))
        }
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text("0 m", color = secondaryText, fontSize = KType.caption)
        Text(Fmt.distance(distance), color = secondaryText, fontSize = KType.caption)
    }
    Text("Elevation from Mapzen · AWS Open Data", color = secondaryText, fontSize = KType.caption)
}

@Composable
private fun SurfaceChart(sections: List<Valhalla.PathSection>, route: Route, model: AppModel, total: Double) {
    if (total <= 0.0) return
    val accent = interfaceAccentText
    val unknown = secondaryText.copy(alpha = 0.22f)
    val selected = model.pathSectionHighlight?.takeIf { it.first == route.id }?.second
    fun tint(surface: String?) = when (surface) {
        "Smooth pavement" -> accent
        "Pavement" -> Color(0xFF388DA3)
        "Rough pavement" -> Color(0xFF7360B0)
        "Gravel and compacted" -> Color(0xFFC17A33)
        "Natural surface" -> Vela.open
        else -> unknown
    }
    Canvas(Modifier.fillMaxWidth().height(22.dp).clip(RoundedCornerShape(8.dp))
        .pointerInput(sections, total) {
            detectTapGestures { point ->
                val at = point.x / size.width.coerceAtLeast(1) * total
                sections.firstOrNull { at >= it.from && at <= it.to }?.let { model.framePathSection(route, it) }
            }
        }) {
        drawRect(unknown)
        for (section in sections) {
            val start = (section.from / total).toFloat() * size.width
            val width = ((section.to - section.from) / total).toFloat() * size.width
            drawRect(if (section == selected) Color(0xFFE56C16) else tint(section.surface),
                topLeft = Offset(start, 0f), size = Size(width, size.height))
        }
    }
    for (section in sections) {
        Row(Modifier.fillMaxWidth().tap { model.framePathSection(route, section) }.padding(vertical = 5.dp),
            horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(10.dp).clip(RoundedCornerShape(4.dp)).background(tint(section.surface)))
            Text(section.surface.orEmpty(), Modifier.weight(1f), color = primaryText, fontSize = KType.subheadline)
            Text("${Fmt.distance(section.from)} – ${Fmt.distance(section.to)}", color = secondaryText, fontSize = KType.caption)
        }
    }
}
