package app.kite.core

import kotlin.math.cos

/** A bounded OpenStreetMap view for outdoor facilities and signed route relations. */
object OutdoorData {
    const val WATER = "drinking_water"
    const val PARKING = "parking"
    private val common = listOf(WATER, PARKING, "bicycle_parking", "toilets", "shelter", "cafe", "restaurant",
        "fast_food", "pharmacy", "fuel", "bench", "bicycle_rental")
    private val names = mapOf(WATER to "Drinking water", PARKING to "Parking", "bicycle_parking" to "Bicycle parking",
        "toilets" to "Public toilets", "shelter" to "Shelter", "bench" to "Bench")

    fun kind(query: String): String? = when (Place.fold(query.trim())) {
        "drinking water", "water fountain", "water fountains", "pitko", "pitka", "pitna voda" -> WATER
        "parking", "car park", "parking lot", "parking lots", "parkoviste" -> PARKING
        "bicycle parking", "bike parking", "parkovani kol" -> "bicycle_parking"
        "toilets", "public toilets", "restrooms", "public restroom", "wc", "verejne toalety" -> "toilets"
        else -> null
    }

    fun bounds(at: LatLng, radius: Double): Box {
        val y = radius / 111_320
        val x = y / cos(Math.toRadians(at.lat)).coerceAtLeast(0.1)
        return Box((at.lat - y).coerceAtLeast(-90.0), (at.lng - x).coerceAtLeast(-180.0),
            (at.lat + y).coerceAtMost(90.0), (at.lng + x).coerceAtMost(180.0))
    }

    suspend fun find(kind: String?, at: LatLng, radius: Double): List<Place>? {
        val box = bounds(at, radius)
        val b = "${box.s},${box.w},${box.n},${box.e}"
        val amenities = kind?.takeIf(common::contains)?.let(::listOf) ?: common
        val facilities = """nwr["amenity"~"^(${amenities.joinToString("|")})$"]["access"!~"^(private|no)$"]($b);"""
        val extra = if (kind == null) """
            nwr["shop"~"^(supermarket|convenience|bakery|bicycle)$"]($b);
            nwr["tourism"~"^(viewpoint|information|picnic_site)$"]($b);
        """ else ""
        val data = Overpass.query("[out:json][timeout:12];($facilities$extra);out center 1400;") ?: return null
        return parsePlaces(data).sortedBy { it.location.distanceTo(at) }.take(if (kind == null) 300 else 35)
    }

    fun parsePlaces(data: ByteArray): List<Place> = Json.obj(data)?.get("elements").asMaps().orEmpty().mapNotNull { row ->
        val tags = row["tags"].asMap() ?: return@mapNotNull null
        val type = (tags["amenity"] ?: tags["shop"] ?: tags["tourism"]) as? String ?: return@mapNotNull null
        val location = point(row["center"].asMap() ?: row) ?: return@mapNotNull null
        val id = row["id"].long() ?: return@mapNotNull null
        val label = names[type] ?: type.replace('_', ' ').capitalizedFirst()
        val name = (tags["name"] as? String)?.takeIf(String::isNotBlank) ?: label
        val address = listOfNotNull(tags["addr:street"] as? String, tags["addr:housenumber"] as? String)
            .joinToString(" ").takeIf(String::isNotBlank)
        Place("osm:${(row["type"] as? String)?.firstOrNull()?.uppercaseChar() ?: 'N'}$id", name, location, "osm",
            category = label, address = address, website = tags["website"] as? String)
    }

    fun combine(google: List<Place>, open: List<Place>): List<Place> {
        fun same(a: Place, b: Place): Boolean {
            if (a.matchesNearby(b)) return true
            val kind = a.category?.let(::kind)
            return kind != null && kind == b.category?.let(::kind) && a.location.distanceTo(b.location) < 32
        }
        val reviewed = google.filter { it.rating != null || (it.reviewCount ?: 0) > 0 }
        val rest = google.filterNot { it in reviewed }.filterNot { g -> open.any { same(it, g) } }
        return (reviewed + open.filterNot { p -> reviewed.any { same(it, p) } } + rest).distinctBy { it.id }
    }

    private fun point(row: Map<String, Any?>): LatLng? {
        val lat = row["lat"].num() ?: return null
        val lon = row["lon"].num() ?: return null
        return LatLng(lat, lon)
    }
}
