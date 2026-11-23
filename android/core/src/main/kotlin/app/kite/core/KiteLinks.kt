package app.kite.core

object KiteLinks {
    sealed interface Target {
        data object Map : Target
        data class Search(val query: String?) : Target
        data class Place(val at: LatLng, val name: String?, val directions: Boolean) : Target
        data class Shortcut(val id: String) : Target
        enum class Saved : Target { HOME, WORK, CAR }
    }

    fun parse(text: String): Target? {
        val link = Link(text.trim())
        if (!link.scheme.equals("kite", ignoreCase = true) || link.path !in listOf("", "/")) return null
        val params = link.queryItems
        return when (link.host?.lowercase()) {
            "map" -> Target.Map
            "search" -> Target.Search(params["q"]?.trim()?.take(300)?.takeIf(String::isNotBlank))
            "home" -> Target.Saved.HOME
            "work" -> Target.Saved.WORK
            "car" -> Target.Saved.CAR
            "shortcut" -> params["id"]?.takeIf { it.isNotBlank() && it.length <= 100 }?.let { Target.Shortcut(it) }
            "place", "directions" -> {
                val lat = params["lat"]?.toDoubleOrNull()?.takeIf { it in -90.0..90.0 } ?: return null
                val lng = params["lng"]?.toDoubleOrNull()?.takeIf { it in -180.0..180.0 } ?: return null
                Target.Place(LatLng(lat, lng), params["name"]?.trim()?.take(100)?.takeIf(String::isNotBlank),
                    link.host.equals("directions", ignoreCase = true))
            }
            else -> null
        }
    }
}
