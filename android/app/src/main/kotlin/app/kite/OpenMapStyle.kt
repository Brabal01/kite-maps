package app.kite

enum class OpenPlaceGroup(val label: String, val icon: String, vararg val tags: String) {
    WATER("Drinking water", "osm-drinking_water", "drinking_water", "water_point", "water_well", "water_tap"),
    PARKING("Parking", "poi-parking", "parking", "parking_entrance", "parking_space"),
    TOILETS("Toilets", "osm-toilets", "toilets", "shower"),
    BIKE("Bicycle facilities", "osm-bicycle_parking", "bicycle", "bicycle_parking", "bicycle_rental", "bicycle_repair_station"),
    OUTDOORS("Benches, shelters and viewpoints", "poi-park", "bench", "shelter", "viewpoint", "picnic_site", "picnic_table", "park", "camp_site", "playground"),
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
    const val WALK_PATHS = "kite-walk-paths"
    const val BIKE_PATHS = "kite-bike-paths"

    val pathLayers = mapOf(
        WALK_PATHS to ("""["all",["==",["geometry-type"],"LineString"],["match",["get","subclass"],["path","footway","steps"],true,false],["!=",["get","foot"],"no"],["!=",["get","access"],"private"]]""" to 0xFF188858),
        BIKE_PATHS to ("""["all",["==",["geometry-type"],"LineString"],["any",["==",["get","subclass"],"cycleway"],["==",["get","bicycle"],"designated"]],["!=",["get","access"],"private"]]""" to 0xFF3276C6),
    )
    const val ATTRIBUTION = "© OpenStreetMap contributors · Waymarked Trails, CC BY-SA 3.0"
    fun trailTile(kind: String) = "https://tile.waymarkedtrails.org/$kind/{z}/{x}/{y}.png"

    val detailIcons = linkedMapOf(
        "drinking_water" to "water", "water_point" to "water", "water_tap" to "water", "water_well" to "water",
        "bench" to "bench", "shelter" to "shelter", "viewpoint" to "viewpoint", "picnic_site" to "picnic",
        "picnic_table" to "picnic", "camp_site" to "camp", "toilets" to "toilets", "shower" to "toilets",
        "bicycle_repair_station" to "bike-repair", "bicycle_parking" to "bike", "bicycle_rental" to "bike",
        "charging_station" to "charging", "charging-station" to "charging", "cafe" to "coffee",
        "bakery" to "bakery", "pharmacy" to "pharmacy", "hospital" to "health", "bus_stop" to "bus",
        "bus_station" to "bus", "museum" to "culture", "library" to "library", "school" to "education",
        "playground" to "playground", "fire_station" to "fire", "police" to "police", "post_office" to "post",
        "recycling" to "recycling", "waste_basket" to "waste", "atm" to "bank", "bank" to "bank",
        "fountain" to "fountain", "hotel" to "hotel",
    )
    private val category = """["coalesce",["get","subclass"],["get","class"],""]"""
    private fun quote(value: String) = '"' + value + '"'
    private fun groupFor(field: String, otherwise: String): String =
        """["match",$field,${OpenPlaceGroup.entries.filter { it.tags.isNotEmpty() }.joinToString(",") { g ->
            g.tags.joinToString(",", "[", "]", transform = ::quote) + "," + quote(g.name)
        }},$otherwise]"""
    private val classField = """["coalesce",["get","class"],""]"""
    val group = groupFor(category, groupFor(classField, quote("MORE")))
    private val groupIcon = """["match",$group,${OpenPlaceGroup.entries.filter { it != OpenPlaceGroup.MORE }
        .joinToString(",") { quote(it.name) + "," + quote("open-${it.name.lowercase()}") }},"open-more"]"""
    val icon = """["match",$category,${detailIcons.entries.joinToString(",") { (tag, id) ->
        quote(tag) + "," + quote("open-$id")
    }},$groupIcon]"""
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

    fun visibleGroups(model: AppModel): Set<OpenPlaceGroup> = when {
        model.nav != null || model.cruise != null ->
            if (AppSettings.navigationPlaces) AppSettings.navigationPlaceGroups else emptySet()
        model.transitGuidance == null && AppSettings.openMapPlaces -> AppSettings.openPlaceGroups
        else -> emptySet()
    }

    fun title(name: String?, subclass: String?, klass: String?): String =
        name?.takeIf { it.isNotBlank() } ?: (subclass ?: klass ?: "place").replace('_', ' ').replaceFirstChar(Char::titlecase)
}
