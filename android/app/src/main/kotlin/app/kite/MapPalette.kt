package app.kite

enum class MapColor(val label: String, val styleKey: String?) {
    LAND("Land", "colorLand"),
    WATER("Water", "colorWater"),
    PARKS("Parks", "colorGreenspace"),
    BUILDINGS("Buildings", "colorBuildings"),
    STREETS("Streets", "colorRoads"),
    HIGHWAYS("Highways", "colorMotorways"),
    ROUTE("Route", null),
}

data class MapPalette(val colors: List<String>) {
    operator fun get(field: MapColor): String = colors[field.ordinal]

    fun change(field: MapColor, color: String): MapPalette = copy(colors = colors.mapIndexed { index, old ->
        if (index == field.ordinal) color else old
    })

    companion object {
        private val colorPattern = Regex("#[0-9A-Fa-f]{6}")
        fun isColor(s: String) = colorPattern.matches(s)
        fun decode(s: String?): MapPalette? = s?.split(',')?.takeIf { it.size == MapColor.entries.size && it.all(::isColor) }
            ?.let(::MapPalette)
        private fun palette(vararg colors: String) = MapPalette(colors.map { "#$it" })
        val day = linkedMapOf(
            "Coast" to palette("F0EEE7", "A3CFE1", "BED7B5", "D9D3CB", "FFFFFF", "EFC581", "079A9A"),
            "Meadow" to palette("F3EEE2", "A5CCD1", "B0CBA4", "D7C8B5", "FFF8E8", "E7B477", "197665"),
            "Alpine" to palette("EDF0F4", "A0C4E8", "BBD2CC", "D3DBE7", "FFFFFF", "C6BBED", "4763C7"),
        )
        val night = linkedMapOf(
            "Twilight" to palette("202B40", "132943", "24483F", "39445A", "48556E", "77658C", "57DDCA"),
            "Midnight" to palette("172330", "101F3D", "263D41", "2A3C56", "394E65", "576F9D", "75CFFF"),
            "Ember" to palette("302A35", "202635", "344841", "4E4048", "5C4B57", "946D5F", "FFC190"),
        )
        fun presets(dark: Boolean) = if (dark) night else day
        fun default(dark: Boolean) = presets(dark).values.first()
    }
}
