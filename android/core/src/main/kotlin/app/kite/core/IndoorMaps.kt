package app.kite.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object IndoorMaps {
    data class Feature(val floors: Set<String>, val kind: String, val name: String?, val geometry: List<LatLng>)
    data class Entrance(val at: LatLng, val name: String, val wheelchair: Boolean?)
    data class Plan(val features: List<Feature>) {
        val floors = features.flatMap { it.floors }.distinct().sortedByDescending { it.toDoubleOrNull() }
    }

    suspend fun plan(at: LatLng): Plan? = withContext(Dispatchers.Default) {
        val b = OutdoorData.bounds(at, 210.0)
        if (b.w >= b.e || b.s >= b.n) return@withContext null
        val box = "${b.s},${b.w},${b.n},${b.e}"
        val query = """
            [out:json][timeout:10];(
              way["indoor"]["level"]($box);
              way["highway"="steps"]["level"]($box);
              nwr["shop"]["level"]($box);
              nwr["amenity"~"^(toilets|restaurant|cafe|food_court|pharmacy)$"]["level"]($box);
              node["door"]["level"]($box);
              nwr["highway"="elevator"]["level"]($box);
              node["entrance"]["level"]($box);
            );out tags geom 950;
        """.trimIndent()
        Overpass.queryLocal(query)?.let(::parsePlan)
    }

    suspend fun entrances(at: LatLng): List<Entrance>? = withContext(Dispatchers.Default) {
        val query = """
            [out:json][timeout:8];(
              node["railway"="subway_entrance"](around:320,${at.lat},${at.lng});
              node["entrance"]["public_transport"="station"](around:240,${at.lat},${at.lng});
              node["entrance"]["railway"="station"](around:240,${at.lat},${at.lng});
            );out 50;
        """.trimIndent()
        Overpass.queryLocal(query)?.let { data ->
            Json.obj(data)?.get("elements").asMaps().orEmpty().mapNotNull { item ->
                val location = coordinate(item) ?: return@mapNotNull null
                val tags = item["tags"].asMap().orEmpty()
                if (tags["access"] in listOf("private", "no", "customers")) return@mapNotNull null
                val ref = tags["ref"] as? String
                val name = tags["name"] as? String ?: ref?.let { "Entrance $it" } ?: "Station entrance"
                val wheelchair = when (tags["wheelchair"]) { "yes" -> true; "no" -> false; else -> null }
                Entrance(location, name, wheelchair)
            }.distinctBy { it.at }.sortedBy { it.at.distanceTo(at) }.take(12)
        }
    }

    internal fun parsePlan(data: ByteArray): Plan {
        return Plan(Json.obj(data)?.get("elements").asMaps().orEmpty().mapNotNull { item ->
            val tags = item["tags"].asMap().orEmpty()
            if (tags["access"] in listOf("private", "no")) return@mapNotNull null
            val floors = (tags["level"] as? String).orEmpty().split(';').mapNotNull {
                val value = it.trim().toDoubleOrNull()?.takeIf(Double::isFinite) ?: return@mapNotNull null
                if (value % 1.0 == 0.0) value.toInt().toString() else value.toString()
            }.toSet()
            if (floors.isEmpty()) return@mapNotNull null
            val geometry = coordinate(item)?.let(::listOf) ?: item["geometry"].asMaps().orEmpty().mapNotNull(::coordinate)
            if (geometry.isEmpty()) return@mapNotNull null
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
            Feature(floors, kind, name, geometry)
        })
    }

    private fun coordinate(item: Map<String, Any?>): LatLng? {
        val lat = item["lat"].num()?.takeIf { it in -90.0..90.0 } ?: return null
        val lon = item["lon"].num()?.takeIf { it in -180.0..180.0 } ?: return null
        return LatLng(lat, lon)
    }
}
