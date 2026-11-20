@file:OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package app.kite.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.kite.*
import app.kite.core.Place
import kotlinx.coroutines.delay
import java.util.Date

@Composable
fun TransitNavigationOverlay(model: AppModel, journey: TransitGuidance, showMapbox: Boolean) {
    val leg = journey.leg
    val phase = journey.phase
    var showTrip by remember { mutableStateOf(false) }
    var showDepartures by remember(journey.legIndex) { mutableStateOf(false) }
    var confirmEnd by remember { mutableStateOf(false) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(journey) {
        while (true) { delay(5000); now = System.currentTimeMillis() }
    }
    BackHandler { confirmEnd = true }
    Box(Modifier.fillMaxSize().systemBarsPadding()) {
        if (showMapbox) MapboxAttribution(Modifier.align(Alignment.BottomCenter).padding(bottom = 104.dp))
        val walking = model.nav.takeIf { phase == TransitGuidance.Phase.WALK }
        if (walking != null) Box(Modifier.align(Alignment.TopCenter).padding(top = 4.dp, start = 12.dp, end = 12.dp)) {
            InstructionBanner(walking)
        }
        if (walking?.following == true && model.glide.carOnScreen) {
            val y = NavGlide.carY(model.mapHeightDp, model.glide.carNorth).dp
            Icon(Icons.Filled.Navigation, null, tint = Vela.accentText(LocalDark.current),
                modifier = Modifier.align(Alignment.TopCenter).offset(y = y - 45.dp).size(36.dp))
        }
        Column(Modifier.align(Alignment.BottomCenter).padding(12.dp).fillMaxWidth().glass(RoundedCornerShape(25.dp))
            .padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            val label = when (phase) {
                TransitGuidance.Phase.WALK -> leg?.toName?.takeUnless { it.isBlank() || it == "END" }?.let { "Walk to $it" }
                    ?: "Walk to ${journey.destination.name}"
                TransitGuidance.Phase.BOARD -> "Board at ${leg?.fromName.orEmpty()}"
                TransitGuidance.Phase.RIDE -> if (journey.nearExit) "Get off at ${leg?.toName.orEmpty()}" else "On board"
                TransitGuidance.Phase.COMPLETE -> "You reached ${journey.destination.name}"
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (leg != null && !leg.isWalk) LineChip(leg)
                Text(label, color = primaryText, fontSize = KType.headline, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                if (phase != TransitGuidance.Phase.COMPLETE && (!journey.following || walking?.following == false))
                    IconButton(model::followTransit) { Icon(Icons.Filled.MyLocation, "Re-centre") }
            }
            when (phase) {
                TransitGuidance.Phase.WALK -> {
                    walking?.progress?.let {
                        Text("${Fmt.distance(it.remainingMeters)} · ${Fmt.duration(it.remainingSeconds)}", color = secondaryText)
                    }
                    if (walking == null && !journey.walkingError) Text("Preparing walking guidance…", color = secondaryText)
                    if (journey.walkingError) {
                        Text("Walking directions unavailable. The transfer path is still on the map.", color = secondaryText)
                        TextButton(model::retryTransitWalk) { Text("Retry walking directions") }
                    }
                    TextButton(model::advanceTransitLeg) { Text(if (journey.legIndex == journey.trip.legs.lastIndex) "I'm at the destination" else "I'm at the stop") }
                }
                TransitGuidance.Phase.BOARD -> {
                    val live = journey.liveDeparture
                    val time = live?.time ?: leg?.depart
                    val call = leg?.calls?.firstOrNull()
                    val details = listOfNotNull(
                        leg?.headsign?.let { "Toward $it" },
                        (live?.platform ?: call?.platform)?.takeIf(String::isNotBlank)?.let { "Platform $it" },
                        time?.let { "${if (live?.delayMinutes == null && leg?.delayMinutes == null) "Scheduled" else "Live"} ${Fmt.time(Date(it))}" })
                    if (details.isNotEmpty()) Text(details.joinToString(" · "), color = secondaryText)
                    if (time != null && now > time + 180_000) Text("This departure may have passed.", color = Vela.closed)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton({ showDepartures = true }) { Text("Departures") }
                        Button(model::boardTransit, enabled = !journey.boarding) {
                            Text(if (journey.boarding) "Preparing ride…" else "I'm on board")
                        }
                    }
                }
                TransitGuidance.Phase.RIDE -> {
                    val positionAt = journey.lastAlongAt
                    val gps = positionAt != null && now - positionAt <= 20_000
                    val next = if (gps) journey.nextStop else journey.scheduledNext(now)
                    next?.let { Text("${if (gps) "Next stop" else "Scheduled next stop"} · ${it.name}", color = primaryText) }
                    val exit = listOfNotNull(leg?.toName, leg?.arrive?.let { Fmt.time(Date(it)) })
                    if (exit.isNotEmpty()) Text("Get off · ${exit.joinToString(" · ")}", color = secondaryText)
                    if (!gps) Text("Waiting for a position along the route", color = secondaryText, fontSize = KType.caption)
                    TextButton(model::advanceTransitLeg) { Text("I'm off the vehicle") }
                }
                TransitGuidance.Phase.COMPLETE -> {}
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                if (phase != TransitGuidance.Phase.COMPLETE) {
                    TextButton({ showTrip = true }) { Text("Trip") }
                    TextButton(model::replanTransit) { Text("Replan") }
                    TextButton({ confirmEnd = true }) { Text("End") }
                } else Button(model::endNavigation) { Text("Done") }
            }
        }
    }
    if (showTrip) TripSheet("Your transit trip", "Done", { showTrip = false }) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 18.dp)) {
            TransitSteps(journey.trip)
        }
    }
    if (showDepartures) TripSheet("Departures", "Done", { showDepartures = false }) {
        val call = leg?.calls?.firstOrNull()
        val at = call?.at ?: leg?.path?.firstOrNull()
        if (at != null) Column(Modifier.verticalScroll(rememberScrollState()).padding(18.dp)) {
            val id = call?.stopId?.let { "transit:$it" } ?: "stop:${at.lat},${at.lng}"
            DepartureBoard(Place(id, leg?.fromName.orEmpty(), at, "transitous", category = "Transit stop"))
        }
    }
    if (confirmEnd) AlertDialog(onDismissRequest = { confirmEnd = false },
        title = { Text("End this trip?") },
        confirmButton = { TextButton(model::endNavigation) { Text("End trip") } },
        dismissButton = { TextButton({ confirmEnd = false }) { Text("Keep going") } })
}
