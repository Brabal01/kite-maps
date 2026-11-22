package app.kite

/** A standalone basemap puts the imagery below every overlay without another opaque basemap. */
internal object SatelliteStyle {
    const val URL = "https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer"
    private const val TILES = "$URL/tile/{z}/{y}/{x}"
    const val CREDIT = "Imagery © Esri, Vantor, Earthstar Geographics and the GIS User Community"
    private const val ATTRIBUTION = "<a href='$URL'>$CREDIT</a>"

    fun json(mapbox: Boolean): String {
        val glyphs = if (mapbox) "mapbox://fonts/mapbox/{fontstack}/{range}.pbf"
            else "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf"
        val slots = if (mapbox) """,""" + listOf("bottom", "middle", "top").joinToString(",") {
            """{"id":"$it","type":"slot"}"""
        } else ""
        return """{
            "version":8,
            "glyphs":"$glyphs",
            "sources":{"kite-imagery":{"type":"raster","tiles":["$TILES"],"tileSize":256,
                       "maxzoom":19,"attribution":"$ATTRIBUTION"}},
            "layers":[
                {"id":"kite-imagery-background","type":"background","paint":{"background-color":"#293333"}},
                {"id":"kite-imagery","type":"raster","source":"kite-imagery","paint":{"raster-fade-duration":120}}
                $slots
            ]
        }""".trimIndent()
    }
}
