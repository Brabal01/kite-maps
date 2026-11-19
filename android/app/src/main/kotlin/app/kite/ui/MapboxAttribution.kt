package app.kite.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import app.kite.R

@Composable
internal fun MapboxAttribution(modifier: Modifier = Modifier) {
    var open by remember { mutableStateOf(false) }
    val context = LocalContext.current
    Row(modifier.clip(RoundedCornerShape(6.dp)).background(Color.White.copy(alpha = 0.92f))
        .clickable(onClickLabel = "Map attribution") { open = true }.padding(horizontal = 5.dp)) {
        Image(painterResource(R.drawable.mapbox_attribution), "Mapbox", Modifier.height(23.dp))
    }
    if (open) AlertDialog(
        onDismissRequest = { open = false },
        title = { Text("Map attribution") },
        text = {
            Column {
                TextButton({ context.open("https://www.mapbox.com/about/maps/") }) { Text("© Mapbox") }
                TextButton({ context.open("https://www.openstreetmap.org/copyright") }) { Text("© OpenStreetMap") }
                TextButton({ context.open("https://apps.mapbox.com/feedback/") }) { Text("Improve this map") }
            }
        },
        confirmButton = { TextButton({ open = false }) { Text("Done") } },
    )
}
