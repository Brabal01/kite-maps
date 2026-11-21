package app.kite.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.math.cos

/** A bounded OpenStreetMap view for outdoor facilities and signed route relations. */
object OutdoorData {
    const val WATER = "drinking_water"
    const val PARKING = "parking"
    private val amenities = listOf(WATER, PARKING, "bicycle_parking", "toilets", "shelter", "cafe", "restaurant",
        "fast_food", "pharmacy", "fuel", "bench", "bicycle_rental", "bicycle_repair_station", "charging_station")
    private val names = mapOf(WATER to "Drinking water", PARKING to "Parking", "bicycle_parking" to "Bicycle parking",
        "toilets" to "Public toilets", "shelter" to "Shelter", "bench" to "Bench", "viewpoint" to "Viewpoint",
        "picnic_site" to "Picnic site", "bicycle_repair_station" to "Bicycle repair station",
        "charging_station" to "EV charging stations", "fuel" to "Fuel stations", "pharmacy" to "Pharmacies")
    private val aliases = mapOf(
        WATER to listOf("drinking water", "water fountain", "water fountains", "water refill", "pitko", "pitka", "pitnou vodu", "pitna voda", "fontanka na piti"),
        PARKING to listOf("parking", "car park", "parking lot", "parking lots", "parkoviste", "parkovani"),
        "bicycle_parking" to listOf("bicycle parking", "bike parking", "parkovani kol", "stojany na kola"),
        "toilets" to listOf("toilets", "public toilets", "restrooms", "public restroom", "wc", "verejne toalety", "zachody", "toalety"),
        "shelter" to listOf("shelter", "shelters", "pristresek", "pristresky"),
        "bench" to listOf("bench", "benches", "lavicka", "lavicky"),
        "viewpoint" to listOf("viewpoint", "viewpoints", "vyhlidka", "vyhlidky"),
        "picnic_site" to listOf("picnic site", "picnic sites", "piknik", "piknikova mista"),
        "bicycle_repair_station" to listOf("bicycle repair station", "bike repair", "servis kol"),
        "charging_station" to listOf("ev charging", "ev charging station", "ev charging stations", "dobijeci stanice"),
        "fuel" to listOf("fuel", "fuel stations", "petrol stations", "gas stations", "cerpaci stanice", "benzinky"),
        "pharmacy" to listOf("pharmacy", "pharmacies", "lekarna", "lekarny"),
    )
    private val categoryByName = aliases.flatMap { (category, names) -> names.map { it to category } }.toMap()

    fun kind(query: String): String? = categoryByName[normalize(query)]

    fun classicKind(query: String): String? =
        kind(query)?.takeIf { it == WATER || it == PARKING || it == "bicycle_parking" || it == "toilets" }

    fun categorySuggestions(query: String): List<String> {
        val term = normalize(query)
        if (term.length < 2) return emptyList()
        return aliases.filterValues { words -> words.any { it.startsWith(term) } }.keys.mapNotNull(names::get)
    }

    private fun normalize(text: String) = Place.fold(text).trim().replace(Regex("""\s+"""), " ")

    fun bounds(at: LatLng, radius: Double): Box {
        val y = radius / 111_320
        val x = y / cos(Math.toRadians(at.lat)).coerceAtLeast(0.1)
        return Box((at.lat - y).coerceAtLeast(-90.0), (at.lng - x).coerceAtLeast(-180.0),
            (at.lat + y).coerceAtMost(90.0), (at.lng + x).coerceAtMost(180.0))
    }

    suspend fun find(kind: String?, at: LatLng, radius: Double): List<Place>? = withContext(Dispatchers.Default) {
        val box = bounds(at, radius)
        val b = String.format(java.util.Locale.US, "%.5f,%.5f,%.5f,%.5f", box.s, box.w, box.n, box.e)
        val selector = when (kind) {
            null -> """nwr["amenity"~"^(${amenities.joinToString("|")})$"]($b);
                nwr["shop"~"^(supermarket|convenience|bakery|bicycle)$"]($b);
                nwr["tourism"~"^(viewpoint|information|picnic_site)$"]($b);"""
            "viewpoint", "picnic_site" -> """nwr["tourism"="$kind"]($b);"""
            in amenities -> """nwr["amenity"="$kind"]($b);"""
            else -> return@withContext emptyList()
        }
        val cap = if (kind == null) 1400 else 300
        val primary = if (kind == null) "($selector);" else selector
        val found = coroutineScope {
            val main = async { Overpass.queryLocal("[out:json][timeout:8];$primary out center $cap;")?.let(::parsePlaces) }
            val extra = if (kind == WATER) async {
                val query = """[out:json][timeout:5];(
                    nwr["drinking_water"="yes"]["man_made"~"^(water_tap|water_well)$"]($b);
                    nwr["drinking_water"="yes"]["amenity"="fountain"]($b);
                    nwr["drinking_water"="yes"]["natural"="spring"]($b);
                );out center 100;"""
                withTimeoutOrNull(4_000) { Overpass.queryLocal(query)?.let(::parsePlaces) }
            } else null
            val places = main.await()
            val more = extra?.await()
            if (places == null && more == null) null else places.orEmpty() + more.orEmpty()
        } ?: return@withContext null
        found.distinctBy { it.id }.filter { it.location.distanceTo(at) <= radius }
            .sortedBy { it.location.distanceTo(at) }.take(if (kind == null) 300 else 35)
    }

    fun parsePlaces(data: ByteArray): List<Place> = Json.obj(data)?.get("elements").asMaps().orEmpty().mapNotNull { row ->
        val tags = row["tags"].asMap() ?: return@mapNotNull null
        if (tags["access"] in setOf("private", "no")) return@mapNotNull null
        val type = if (tags["drinking_water"] == "yes" &&
            (tags["amenity"] == "fountain" || tags["man_made"] in listOf("water_tap", "water_well") || tags["natural"] == "spring")) WATER
        else (tags["amenity"] ?: tags["shop"] ?: tags["tourism"]) as? String ?: return@mapNotNull null
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
