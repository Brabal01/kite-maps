package app.kite

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.service.quicksettings.TileService
import app.kite.core.Place

internal object QuickLaunch {
    private const val PREFIX = "shortcut:"

    fun intent(context: Context, target: Uri = Uri.parse("kite://map")) =
        Intent(Intent.ACTION_VIEW, target, context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)

    private fun shortcut(context: Context, place: Place): ShortcutInfo {
        val link = Uri.Builder().scheme("kite").authority("shortcut").appendQueryParameter("id", place.id).build()
        return ShortcutInfo.Builder(context, place.id).setShortLabel(place.name.take(35)).setLongLabel(place.name.take(100))
            .setIcon(Icon.createWithResource(context, R.drawable.ic_shortcut_home))
            .setIntent(intent(context, link)).build()
    }

    fun sync(context: Context, places: List<Place>) {
        val manager = context.getSystemService(ShortcutManager::class.java) ?: return
        val entries = places.filter { it.id.startsWith(PREFIX) }.asReversed()
        val ids = entries.mapTo(mutableSetOf()) { it.id }
        val slots = (manager.maxShortcutCountPerActivity - manager.manifestShortcuts.size).coerceAtLeast(0)
        val dynamic = entries.take(slots).map { shortcut(context, it) }
        val obsolete = manager.pinnedShortcuts.filter { it.id.startsWith(PREFIX) && it.id !in ids }.map { it.id }
        if (obsolete.isNotEmpty()) manager.disableShortcuts(obsolete, "This place was removed from Kite.")
        val pinned = manager.pinnedShortcuts.associateBy { it.id }
        val renamed = entries.filter { place -> pinned[place.id]?.let { it.shortLabel != place.name.take(35) || it.longLabel != place.name.take(100) } == true }
        if (renamed.isNotEmpty()) manager.updateShortcuts(renamed.map { shortcut(context, it) })
        val current = manager.dynamicShortcuts
        if (dynamic.map { it.id to it.shortLabel } != current.map { it.id to it.shortLabel }) {
            manager.dynamicShortcuts = dynamic
        }
    }

    fun shareLink(place: Place): String = Uri.Builder().scheme("kite").authority("place")
        .appendQueryParameter("lat", place.location.lat.toString())
        .appendQueryParameter("lng", place.location.lng.toString())
        .appendQueryParameter("name", place.name).build().toString()

    fun pin(context: Context, place: Place): Boolean {
        val manager = context.getSystemService(ShortcutManager::class.java) ?: return false
        return manager.isRequestPinShortcutSupported && manager.requestPinShortcut(shortcut(context, place), null)
    }
}

class QuickMapTile : TileService() {
    @Suppress("DEPRECATION")
    override fun onClick() {
        super.onClick()
        val intent = QuickLaunch.intent(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        } else startActivityAndCollapse(intent)
    }
}
