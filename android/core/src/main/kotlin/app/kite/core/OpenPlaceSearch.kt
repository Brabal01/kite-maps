package app.kite.core

import kotlinx.coroutines.CancellationException
import kotlin.math.max

/** OSM search uses named features from Photon and tagged facilities from Overpass. */
object OpenPlaceSearch {
    suspend fun search(query: String, center: LatLng, span: Double?): List<Place> {
        val category = OutdoorData.kind(query)
        if (category != null) {
            val radius = ((span ?: 4_000.0) / 2).coerceIn(1_200.0, 6_000.0)
            val nearby = OutdoorData.find(category, center, radius)?.filter { it.location.distanceTo(center) <= radius }
                ?: return emptyList()
            if (nearby.isNotEmpty() || radius >= 6_000.0) return nearby
            return OutdoorData.find(category, center, max(4_000.0, radius * 2).coerceAtMost(6_000.0)).orEmpty()
        }
        val global = names(query, center, limit = 30)
        val ranked = PlaceSearch.forMap(query, center, span, global)
        if (ranked.isNotEmpty()) return ranked
        val radius = ((span ?: 10_000.0) * 0.6).coerceIn(4_000.0, 25_000.0)
        return PlaceSearch.forMap(query, center, span, names(query, center, 30, OutdoorData.bounds(center, radius)))
    }

    suspend fun suggestions(query: String, center: LatLng): SuggestParser.Result {
        val shortcuts = OutdoorData.categorySuggestions(query)
        if (shortcuts.isNotEmpty()) return SuggestParser.Result(queries = shortcuts)
        return SuggestParser.Result(places = PlaceSearch.forMap(query, center, null, names(query, center, 8)).take(8))
    }

    private suspend fun names(query: String, center: LatLng, limit: Int, bounds: Box? = null): List<Place> =
        try {
            Photon.search(query, center, limit, bounds)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            emptyList()
        }
}
