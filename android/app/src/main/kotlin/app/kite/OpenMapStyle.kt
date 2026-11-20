package app.kite

enum class OpenPlaceGroup(val label: String, val icon: String, vararg val tags: String) {
    WATER("Drinking water", "osm-drinking_water", "drinking_water", "water_point", "water_well"),
    PARKING("Parking", "poi-parking", "parking", "parking_entrance", "parking_space"),
    TOILETS("Toilets", "osm-toilets", "toilets", "shower"),
    BIKE("Bicycle facilities", "osm-bicycle_parking", "bicycle", "bicycle_parking", "bicycle_rental", "bicycle_repair_station"),
    OUTDOORS("Benches, shelters and viewpoints", "poi-park", "bench", "shelter", "viewpoint", "picnic_site", "picnic_table", "park", "camp_site"),
    FOOD("Food and cafés", "poi-food", "restaurant", "cafe", "ice_cream", "food_court", "fast_food", "pub", "bar"),
    SHOP("Shops", "poi-shop", "shop", "supermarket", "bakery", "convenience", "mall", "clothes"),
    FUEL("Fuel and charging", "poi-gas", "fuel", "charging_station", "charging-station"),
    MEDICAL("Pharmacies and health", "poi-health", "pharmacy", "hospital", "clinic", "doctors", "dentist"),
    TRANSIT("Transit stops", "osm-transit", "bus", "bus_stop", "bus_station", "tram_stop", "rail", "railway", "station", "subway", "halt"),
    MORE("Other mapped places", "poi-default"),
}

object OpenMapStyle {
    const val TILEJSON = "https://tiles.openfreemap.org/planet"
    const val POIS = "kite-osm-pois"
    const val SOURCE = "kite-osm-tiles"
    const val HIKING = "kite-hiking"
    const val CYCLING = "kite-cycling"
    const val ATTRIBUTION = "© OpenStreetMap contributors · Waymarked Trails, CC BY-SA 3.0"
    fun trailTile(kind: String) = "https://tile.waymarkedtrails.org/$kind/{z}/{x}/{y}.png"

    private val category = """["coalesce",["get","subclass"],["get","class"],""]"""
    val group = """["match",$category,${OpenPlaceGroup.entries.filter { it.tags.isNotEmpty() }.joinToString(",") { g ->
        "${g.tags.joinToString(",", "[", "]") { "\"$it\"" }},\"${g.name}\""
    }},"MORE"]"""
    val icon = """["match",$group,${OpenPlaceGroup.entries.filter { it != OpenPlaceGroup.MORE }
        .joinToString(",") { "\"${it.name}\",\"${it.icon}\"" }},"poi-default"]"""
    fun filter(groups: Set<OpenPlaceGroup>): String {
        fun matches(values: Set<OpenPlaceGroup>): String {
            val names = values.joinToString(",") { '"' + it.name + '"' }
            return """["in",$group,["literal",[$names]]]"""
        }
        val enabled = matches(groups)
        val facilities = matches(setOf(OpenPlaceGroup.WATER, OpenPlaceGroup.TOILETS))
        val closeFacilities = matches(setOf(OpenPlaceGroup.WATER, OpenPlaceGroup.TOILETS,
            OpenPlaceGroup.PARKING, OpenPlaceGroup.BIKE, OpenPlaceGroup.TRANSIT))
        fun show(rank: Int, more: String = "false") =
            """["all",$enabled,["any",["<=",["number",["get","rank"],999],$rank],$more]]"""
        return """["step",["zoom"],${show(4)},14,${show(8)},15,${show(18, facilities)},
            16,${show(32, closeFacilities)},17,${show(68, closeFacilities)}]"""
    }

    fun title(name: String?, subclass: String?, klass: String?): String =
        name?.takeIf { it.isNotBlank() } ?: (subclass ?: klass ?: "place").replace('_', ' ').replaceFirstChar(Char::titlecase)
}
