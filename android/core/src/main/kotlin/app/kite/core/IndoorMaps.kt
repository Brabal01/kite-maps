package app.kite.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object IndoorMaps {
    private val mapClient = Http.client(7)
    private val supportedAmenities = setOf("toilets", "restaurant", "cafe", "food_court", "pharmacy")

    data class Feature(val floors: Set<String>, val kind: String, val name: String?, val geometry: List<LatLng>,
                       val category: String? = null, val holes: List<List<LatLng>> = emptyList()) {
        val polygon: Boolean get() = geometry.size >= 4 && geometry.first() == geometry.last()
        val center: LatLng get() = LatLng(geometry.map { it.lat }.average(), geometry.map { it.lng }.average())
        fun covers(at: LatLng): Boolean = polygon && contains(geometry, at) && holes.none { contains(it, at) }
    }
    data class Entrance(val at: LatLng, val name: String, val wheelchair: Boolean?)
    data class Plan(val features: List<Feature>, val building: List<LatLng>? = null,
                    val buildingName: String? = null, val buildings: List<Pair<String?, List<LatLng>>> = emptyList()) {
        val floors = features.flatMap { it.floors }.distinct().sortedByDescending { it.toDoubleOrNull() }

        fun covers(at: LatLng): Boolean = building?.let { contains(it, at) } ?: features.any { it.covers(at) || it.center.distanceTo(at) < 14 }

        fun at(at: LatLng): Plan? {
            val footprint = buildings.filter { (_, ring) -> contains(ring, at) }
                .minByOrNull { (_, ring) -> footprintArea(ring) }
            val nearby = if (footprint != null) features.filter { feature ->
                contains(footprint.second, feature.center) || feature.geometry.any { contains(footprint.second, it) }
            } else features.takeIf { list -> list.any { it.covers(at) || it.center.distanceTo(at) < 14 } }.orEmpty()
            if (nearby.none { it.kind in setOf("shop", "room", "area", "corridor", "toilets", "elevator", "stairs") }) return null
            return Plan(nearby, footprint?.second, footprint?.first)
        }
    }

    private fun footprintArea(ring: List<LatLng>): Double {
        val base = ring.first()
        return kotlin.math.abs(ring.zipWithNext().sumOf { (a, b) ->
            (a.lng - base.lng) * (b.lat - base.lat) - (b.lng - base.lng) * (a.lat - base.lat)
        })
    }

    fun contains(ring: List<LatLng>, at: LatLng): Boolean {
        var inside = false
        for ((a, b) in ring.zipWithNext()) {
            if ((a.lat > at.lat) != (b.lat > at.lat) &&
                at.lng < (b.lng - a.lng) * (at.lat - a.lat) / (b.lat - a.lat) + a.lng) inside = !inside
        }
        return inside
    }

    suspend fun plan(at: LatLng): Plan? = withContext(Dispatchers.Default) {
        val b = OutdoorData.bounds(at, 210.0)
        if (b.w >= b.e || b.s >= b.n) return@withContext null
        val box = "${b.s},${b.w},${b.n},${b.e}"
        val query = """
            [out:json][timeout:10];(
              nwr["indoor"]["level"]($box);
              way["building"]($box);
              relation["building"]["type"="multipolygon"]($box);
              way["highway"="steps"]["level"]($box);
              nwr["shop"]["level"]($box);
              nwr["amenity"~"^(toilets|restaurant|cafe|food_court|pharmacy)$"]["level"]($box);
              node["door"]["level"]($box);
              nwr["highway"="elevator"]["level"]($box);
              node["entrance"]["level"]($box);
            );out body geom 2200;
        """.trimIndent()
        val overpass = Overpass.queryLocal(query)?.let(::parsePlan)?.at(at)
        overpass ?: osmMap(b)?.let(::parsePlan)?.at(at)
    }

    suspend fun entrances(at: LatLng): List<Entrance>? = withContext(Dispatchers.Default) {
        val query = """
            [out:json][timeout:8];(
              node["railway"="subway_entrance"](around:320,${at.lat},${at.lng});
              node["entrance"]["public_transport"="station"](around:240,${at.lat},${at.lng});
              node["entrance"]["railway"="station"](around:240,${at.lat},${at.lng});
            );out 50;
        """.trimIndent()
        val data = Overpass.queryLocal(query) ?: osmMap(OutdoorData.bounds(at, 320.0))
        data?.let { body ->
            Json.obj(body)?.get("elements").asMaps().orEmpty().mapNotNull { item ->
                val location = coordinate(item) ?: return@mapNotNull null
                val tags = item["tags"].asMap().orEmpty()
                if (tags["railway"] != "subway_entrance" &&
                    !(tags["entrance"] != null && (tags["railway"] == "station" || tags["public_transport"] == "station"))) return@mapNotNull null
                if (tags["access"] in listOf("private", "no", "customers")) return@mapNotNull null
                val ref = tags["ref"] as? String
                val name = tags["name"] as? String ?: ref?.let { "Entrance $it" } ?: "Station entrance"
                val wheelchair = when (tags["wheelchair"]) { "yes" -> true; "no" -> false; else -> null }
                Entrance(location, name, wheelchair)
            }.distinctBy { it.at }.sortedBy { it.at.distanceTo(at) }.take(12)
        }
    }

    private suspend fun osmMap(box: Box): ByteArray? {
        if (box.w >= box.e || box.s >= box.n) return null
        val bbox = "${box.w.plain()},${box.s.plain()},${box.e.plain()},${box.n.plain()}"
        return Http.getOrNull("https://api.openstreetmap.org/api/0.6/map.json?bbox=$bbox",
            headers = mapOf("User-Agent" to "Kite Driving (https://github.com/Gordicek/kite-maps)"),
            client = mapClient)?.takeIf { it.ok }?.body
    }

    internal fun parsePlan(data: ByteArray): Plan {
        val elements = Json.obj(data)?.get("elements").asMaps().orEmpty()
        val nodes = elements.asSequence().filter { it["type"] == "node" }
            .mapNotNull { node -> node["id"].long()?.let { id -> coordinate(node)?.let { id to it } } }.toMap()
        fun coordinates(item: Map<String, Any?>): List<LatLng> = coordinate(item)?.let(::listOf)
            ?: item["geometry"].asMaps()?.mapNotNull(::coordinate)
            ?: item["nodes"].asList().orEmpty().mapNotNull { ref -> nodes[ref.long()] }
        val ways = elements.filter { it["type"] == "way" }.mapNotNull { way ->
            way["id"].long()?.let { it to coordinates(way) }
        }.toMap()
        fun rings(item: Map<String, Any?>, inner: Boolean): List<List<LatLng>> {
            if (item["type"] != "relation") return if (inner) emptyList() else listOf(coordinates(item))
            val pieces = item["members"].asMaps().orEmpty().filter {
                it["type"] == "way" && (it["role"] == "inner") == inner
            }.mapNotNull { member ->
                coordinates(member).ifEmpty { ways[member["ref"].long()].orEmpty() }.takeIf { it.size >= 2 }
            }.toMutableList()
            return buildList {
                while (pieces.isNotEmpty()) {
                    val ring = pieces.removeAt(0).toMutableList()
                    while (ring.first() != ring.last()) {
                        val tail = ring.last()
                        val next = pieces.indexOfFirst { it.first() == tail || it.last() == tail }
                        if (next < 0) break
                        val path = pieces.removeAt(next)
                        ring += (if (path.first() == tail) path else path.asReversed()).drop(1)
                    }
                    if (ring.size >= 4 && ring.first() == ring.last()) add(ring)
                }
            }
        }
        val buildings = elements.flatMap { item ->
            val tags = item["tags"].asMap().orEmpty()
            if (tags["building"] == null) emptyList() else rings(item, false)
                .filter { it.size >= 4 && it.first() == it.last() }.map { tags["name"] as? String to it }
        }
        val features = elements.flatMap { item ->
            val tags = item["tags"].asMap().orEmpty()
            if (tags["access"] in listOf("private", "no")) return@flatMap emptyList()
            if (tags["indoor"] == null && tags["shop"] == null && tags["door"] == null && tags["entrance"] == null &&
                tags["highway"] !in listOf("steps", "elevator") && tags["amenity"] !in supportedAmenities) return@flatMap emptyList()
            val floors = (tags["level"] as? String).orEmpty().split(';').mapNotNull {
                val value = it.trim().toDoubleOrNull()?.takeIf(Double::isFinite) ?: return@mapNotNull null
                if (value % 1.0 == 0.0) value.toInt().toString() else value.toString()
            }.toSet()
            if (floors.isEmpty()) return@flatMap emptyList()
            val shapes = rings(item, false).filter { it.isNotEmpty() }
            val holes = rings(item, true)
            val kind = when {
                tags["amenity"] == "toilets" -> "toilets"
                tags["highway"] == "elevator" -> "elevator"
                tags["highway"] == "steps" -> "stairs"
                tags["entrance"] != null || tags["door"] != null -> "door"
                tags["shop"] != null -> "shop"
                else -> (tags["indoor"] as? String) ?: "room"
            }
            val name = (tags["name"] ?: tags["ref"]) as? String ?: when (kind) {
                "toilets" -> "Toilets"
                "elevator" -> "Lift"
                "stairs" -> "Stairs"
                else -> null
            }
            val category = (tags["shop"] ?: tags["amenity"] ?: tags["room"]) as? String
            shapes.map { shape ->
                Feature(floors, kind, name, shape, category, holes.filter { contains(shape, it.first()) })
            }
        }
        val labelled = features.filter { it.name != null && !it.polygon && it.geometry.size == 1 }
        val used = mutableSetOf<Feature>()
        val plans = features.map { shape ->
            val shop = labelled.firstOrNull { point -> shape.polygon && shape.kind == "room" &&
                shape.floors.any { it in point.floors } && shape.covers(point.center) &&
                (shape.name == null || shape.name.equals(point.name, ignoreCase = true)) }
            if (shop == null) shape else {
                used += shop
                shape.copy(name = shop.name, category = shop.category ?: shape.category)
            }
        }
        return Plan(plans.filterNot { it in used }, buildings = buildings)
    }

    private fun coordinate(item: Map<String, Any?>): LatLng? {
        val lat = item["lat"].num()?.takeIf { it in -90.0..90.0 } ?: return null
        val lon = item["lon"].num()?.takeIf { it in -180.0..180.0 } ?: return null
        return LatLng(lat, lon)
    }
}
