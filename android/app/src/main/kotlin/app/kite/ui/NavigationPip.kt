package app.kite.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DirectionsTransit
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalDensity
import app.kite.*
import app.kite.core.TravelMode

@Composable
internal fun NavigationPictureInPicture(model: AppModel, showMapbox: Boolean) {
    val nav = model.mapNavigator
    val transit = model.transitGuidance
    val maneuver = nav?.nextManeuver
    val progress = nav?.progress
    val distance = progress?.distanceToNext?.let(Fmt::distance)
    val instruction = when {
        nav?.arrived == true || transit?.phase == TransitGuidance.Phase.COMPLETE -> "Arrived"
        maneuver != null -> maneuver.instruction
        transit != null -> transit.nextStop?.name ?: transit.leg?.toName ?: transit.destination.name
        else -> "Kite"
    }
    val eta = progress?.remainingSeconds?.let(Fmt::arrival)
    val accent = Color(0xFF8BF2D6)
    val panel = Color(0xFF123437)
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val compact = maxHeight < 105.dp
        if (nav != null && model.glide.carOnScreen) {
            val marker = if (nav.route.mode == TravelMode.DRIVE) AppSettings.driveMarker else DriveMarker.ARROW
            val tilted = marker != DriveMarker.ARROW && AppSettings.driveLook == app.kite.core.MapLook.TILTED
            val dark = LocalDark.current
            val puck = remember(marker, dark, tilted) { MapIcons.drivePuck(marker, dark, tilted).asImageBitmap() }
            val density = LocalDensity.current
            val height = maxHeight.value
            Image(puck, null, Modifier.align(Alignment.TopCenter).offset {
                IntOffset(0, with(density) { (NavGlide.carY(height, model.glide.carNorth, compact = true).dp - 19.dp).roundToPx() })
            }.size(38.dp).graphicsLayer {
                rotationZ = model.glide.carTurn
                if (!tilted) scaleY = model.glide.carSquash
            })
        }
        Row(Modifier.align(Alignment.TopCenter).fillMaxWidth().padding(5.dp)
            .background(panel, RoundedCornerShape(12.dp)).padding(horizontal = 8.dp, vertical = if (compact) 4.dp else 6.dp),
            horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(maneuver?.type?.let(::maneuverIcon) ?: if (transit != null) Icons.Filled.DirectionsTransit else Icons.Filled.Navigation,
                null, tint = accent, modifier = Modifier.size(20.dp))
            Column(Modifier.weight(1f)) {
                if (distance != null) Text(distance, color = accent, fontSize = 14.sp, lineHeight = 16.sp, fontWeight = FontWeight.ExtraBold)
                Text(instruction, color = Color.White, fontSize = 12.sp, lineHeight = 14.sp, fontWeight = FontWeight.SemiBold,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (eta != null) Text(eta, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold,
            modifier = Modifier.align(Alignment.BottomEnd).padding(5.dp).background(panel, RoundedCornerShape(9.dp))
                .padding(horizontal = 7.dp, vertical = 3.dp))
        if (showMapbox) MapboxAttribution(Modifier.align(Alignment.BottomStart).padding(4.dp))
    }
}
