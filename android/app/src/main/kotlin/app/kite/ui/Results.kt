@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class, androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package app.kite.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kite.*
import app.kite.core.*
import coil.compose.AsyncImage

@Composable
fun ResultsHeader(model: AppModel) {
    Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(model.resultsTitle.replaceFirstChar { it.uppercase() }, fontSize = 24.sp, fontWeight = FontWeight.ExtraBold,
                    color = primaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("${model.visibleResults.size} results", fontSize = KType.subheadline, color = secondaryText)
            }
            val expanded = model.detent == SheetDetent.FULL
            CircleIconButton(if (expanded) Icons.Filled.KeyboardArrowDown else Icons.Filled.KeyboardArrowUp,
                description = if (expanded) "Show more map" else "Expand results") {
                model.detent = if (expanded) SheetDetent.HALF else SheetDetent.FULL
            }
            CircleIconButton(Icons.Filled.Close, description = "Close results") { model.clearSearch() }
        }
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChipLabel("Open now", model.openNowOnly, menu = false) { model.openNowOnly = !model.openNowOnly; model.mapTick++ }
            var open by remember { mutableStateOf(false) }
            Box {
                FilterChipLabel(if (model.sort == SortMode.RELEVANCE) "Sort" else model.sort.label, model.sort != SortMode.RELEVANCE, menu = true) { open = true }
                DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                    SortMode.entries.forEach { m ->
                        DropdownMenuItem(text = { Text(m.label) }, onClick = { model.sort = m; model.mapTick++; open = false },
                            trailingIcon = { if (model.sort == m) Icon(Icons.Filled.Check, null) })
                    }
                }
            }
            FilterChipLabel("Rating 4.0+", model.rating4Only, menu = false) { model.rating4Only = !model.rating4Only; model.mapTick++ }
        }
    }
}

@Composable
fun FilterChipLabel(title: String, on: Boolean, menu: Boolean, onClick: () -> Unit) {
    Row(Modifier.height(44.dp).clip(CircleShape)
        .background(if (on) interfaceAccent else interfaceGround)
        .border(BorderStroke(1.dp, if (on) Color.Transparent else secondaryText.copy(alpha = 0.28f)), CircleShape)
        .tap(onClick).padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        val fg = if (on) interfaceOnAccent else primaryText
        if (on && !menu) Icon(Icons.Filled.Check, null, Modifier.size(14.dp), tint = fg)
        Text(title, fontSize = KType.body, fontWeight = FontWeight.SemiBold, color = fg)
        if (menu) Icon(Icons.Filled.KeyboardArrowDown, null, Modifier.size(16.dp), tint = fg)
    }
}

@Composable
fun ResultsList(model: AppModel, modifier: Modifier = Modifier,
                list: androidx.compose.foundation.lazy.LazyListState = androidx.compose.foundation.lazy.rememberLazyListState()) {
    Box(modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), state = list,
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 60.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (model.visibleResults.isEmpty() && model.results.isNotEmpty()) {
                item {
                    Text("Nothing here matches these filters. Turn one off to see more.", fontSize = KType.body, color = secondaryText,
                        textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(vertical = 32.dp, horizontal = 20.dp))
                }
            }
            items(model.visibleResults, key = { it.id }) { p ->
                ResultRow(model, p)
            }
        }
        // Screenshot run only: the list scrolled with the sheet full height, and a label saying which.
        if (DemoScript.step == "listscroll") {
            LaunchedEffect(Unit) { kotlinx.coroutines.delay(6000); list.scrollToItem(4) }
            val atTop = list.firstVisibleItemIndex == 0 && list.firstVisibleItemScrollOffset == 0
            Text(if (atTop) "list at top" else "list scrolled", fontSize = KType.caption, fontWeight = FontWeight.Bold, color = Color.White,
                modifier = Modifier.align(Alignment.BottomEnd).padding(end = 16.dp, bottom = 80.dp).clip(CircleShape).background(Color.Red).padding(6.dp))
        }
    }
}

@Composable
fun ResultRow(model: AppModel, place: Place) {
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(interfaceGround)) {
        PlaceResultSummary(place, onOpen = { model.select(place) }, here = model.userLatLng) {
            FilledIconButton(
                onClick = { model.selected = place; model.openDirections(place) },
                colors = IconButtonDefaults.filledIconButtonColors(containerColor = interfaceAccent, contentColor = interfaceOnAccent),
                modifier = Modifier.size(48.dp),
            ) { Icon(Icons.Filled.Directions, "Directions to ${place.name}") }
        }
    }
}

@Composable
internal fun PlaceResultSummary(
    place: Place,
    onOpen: () -> Unit,
    here: LatLng? = null,
    mapNumber: Int? = null,
    mapSelected: Boolean = false,
    openLabel: String? = null,
    supporting: @Composable ColumnScope.() -> Unit = {},
    action: @Composable () -> Unit,
) {
    val photo = place.photoUrls.firstOrNull { !AppSettings.noGoogle || !isGooglePhoto(it) }
    Row(Modifier.fillMaxWidth().clickable(onClickLabel = openLabel, onClick = onOpen)
        .padding(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        if (photo != null || mapNumber != null) {
            Box(Modifier.size(56.dp).clip(RoundedCornerShape(12.dp)).background(interfaceSurface), contentAlignment = Alignment.Center) {
                if (photo != null) AsyncImage(photo, null, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
                if (mapNumber != null) {
                    val position = if (photo != null) Modifier.align(Alignment.BottomStart).padding(3.dp) else Modifier
                    Surface(
                        modifier = position,
                        shape = CircleShape,
                        color = if (mapSelected || photo != null) interfaceAccent else MaterialTheme.colorScheme.secondaryContainer,
                        contentColor = if (mapSelected || photo != null) interfaceOnAccent else MaterialTheme.colorScheme.onSecondaryContainer,
                    ) {
                        val diameter = if (photo == null) 32.dp else 25.dp
                        Box(Modifier.defaultMinSize(minWidth = diameter, minHeight = diameter).padding(horizontal = 4.dp),
                            contentAlignment = Alignment.Center) {
                            Text(mapNumber.toString(), fontSize = KType.caption, fontWeight = FontWeight.ExtraBold)
                        }
                    }
                }
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(place.name, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = primaryText,
                maxLines = 2, overflow = TextOverflow.Ellipsis)
            PlaceMetaLine(place, showStars = false, here = here, showDistance = mapNumber == null)
            place.address?.let {
                Text(it, fontSize = KType.footnote, color = secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            StatusText(place, fontSize = KType.footnote)
            supporting()
        }
        action()
    }
}
