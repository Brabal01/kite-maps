package app.kite.core

import java.net.URI

data class PlaceReview(val author: String, val stars: Int?, val relativeTime: String?, val text: String?, val photos: List<String>)

/** Place detail response shapes from Vela Maps' Google client (GPL-3.0). */
object GooglePlaceMedia {
    private val featureIdPattern = Regex("^0x([0-9a-fA-F]{1,16}):0x([0-9a-fA-F]{1,16})$")
    private val size = Regex("=(?:[swh]\\d[\\w-]*|k-no)$")

    fun cid(featureId: String): String? = featureIdPattern.matchEntire(featureId)
        ?.groupValues?.get(2)?.toULong(16)?.toString()

    fun reviewParameter(featureId: String): String? {
        val match = featureIdPattern.matchEntire(featureId) ?: return null
        val high = match.groupValues[1].toULong(16)
        val low = match.groupValues[2].toULong(16)
        return "!1m2!1y$high!2y$low!2m2!2i0!3i20!3e1!5m2!1skite!7e81"
    }

    fun photoRequest(featureId: String): String? {
        if (!featureIdPattern.matches(featureId)) return null
        val inner = """[2,null,["$featureId",null,null,null,null,null,null,null,0],null,[null,[1200,1000],[null,30,null,null,1],null,null,null,[[[1,0,3],[2,1,2],[2,0,3],[8,0,3],[10,0,3],[10,1,2],[10,0,4],[9,1,2]],1],null,0],null,null,null,null,null,null,null,null,null,null,[null,1,null,1]]"""
        return Json.write(listOf(listOf(listOf("hspqX", inner, null, "generic"))))
    }

    fun reviews(root: Any?): List<PlaceReview> = arr(at(root, 2)).orEmpty().mapNotNull { row ->
        val author = gstr(at(row, 0, 1))?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
        PlaceReview(author, gint(at(row, 4))?.takeIf { it in 1..5 }, gstr(at(row, 1)),
            gstr(at(row, 3))?.takeIf { it.isNotBlank() }, imageUrls(row, limit = 8))
    }

    fun reviewFeedRequest(featureId: String): String? {
        if (!featureIdPattern.matches(featureId)) return null
        val inner = """[[["$featureId"],null,null,null,null,[null,null,null,[[1],[3]]]],[10,""],null,null,[null,null,null,null,null,null,81],null,null,[null,1,1,null,1,null,1,null,null,null,null,[1,1,null,[[1]]]],null,null,[3,1,null,null,null,[2]],null,[1]]"""
        return Json.write(listOf(listOf(listOf("qv9Egd", inner, null, "generic"))))
    }

    private fun batchPayload(body: String, rpc: String): Any? =
        body.lineSequence().filter { it.trimStart().startsWith("[[") }
            .flatMap { arr(Json.parse(it)).orEmpty().asSequence() }
            .firstOrNull { at(it, 0) == "wrb.fr" && at(it, 1) == rpc }
            ?.let { (at(it, 2) as? String)?.let(Json::parse) }

    fun reviewFeed(body: String): List<PlaceReview> = arr(at(batchPayload(body, "qv9Egd"), 2)).orEmpty().mapNotNull { entry ->
        val review = at(entry, 0)
        val author = gstr(at(review, 1, 4, 5, 0)) ?: return@mapNotNull null
        PlaceReview(author, gint(at(review, 2, 0, 0))?.takeIf { it in 1..5 }, gstr(at(review, 1, 6)),
            gstr(at(review, 2, 15, 0, 0))?.takeIf { it.isNotBlank() }, imageUrls(at(review, 2, 2), limit = 8))
    }

    fun publicPageReviews(value: String): List<PlaceReview> {
        val pages = Json.parse(value).asMaps().orEmpty()
        return pages.take(24).mapNotNull { item ->
            val author = item["author"].text()?.trim()?.takeIf(String::isNotEmpty) ?: return@mapNotNull null
            val stars = item["rating"].int()?.takeIf { it in 1..5 }
            val text = item["text"].text()?.trim()?.takeIf(String::isNotEmpty)
            val date = item["time"].text()?.trim()?.takeIf(String::isNotEmpty)
            val photos = imageUrls(item["photos"], limit = 8)
            if (stars == null && text == null && photos.isEmpty()) return@mapNotNull null
            PlaceReview(author, stars, date, text, photos)
        }.distinct()
    }

    fun photos(body: String): List<String> = imageUrls(at(batchPayload(body, "hspqX"), 0), limit = 40)

    fun imageUrls(root: Any?, limit: Int): List<String> = strings(root).mapNotNull { value ->
        val uri = if (value.startsWith("//")) "https:$value" else value
        if (!uri.startsWith("https://")) return@mapNotNull null
        val url = runCatching { URI(uri) }.getOrNull() ?: return@mapNotNull null
        val host = url.host ?: return@mapNotNull null
        if (!host.endsWith(".googleusercontent.com") && !host.endsWith(".ggpht.com")) return@mapNotNull null
        val path = url.path ?: return@mapNotNull null
        if (!listOf("/p/", "/gps-cs", "/grass-cs/", "/geougc", "/places/").any(path::startsWith)) return@mapNotNull null
        val base = uri.substringBefore('?').replace(size, "")
        "$base=w800-h600"
    }.distinct().take(limit).toList()

    fun streetViewHint(root: Any?): StreetView.Hint? = strings(root).mapNotNull { value ->
        if (!value.contains("streetviewpixels-pa.googleapis.com/v1/thumbnail?")) return@mapNotNull null
        val url = runCatching { URI(if (value.startsWith("//")) "https:$value" else value) }.getOrNull()
            ?: return@mapNotNull null
        if (url.host != "streetviewpixels-pa.googleapis.com") return@mapNotNull null
        val query = url.query?.split('&').orEmpty().associate { it.substringBefore('=') to it.substringAfter('=', "") }
        val id = query["panoid"]?.takeIf(StreetView::validId) ?: return@mapNotNull null
        StreetView.Hint(id, query["yaw"]?.toDoubleOrNull()?.takeIf(Double::isFinite))
    }.firstOrNull()

    private fun strings(root: Any?): Sequence<String> = sequence {
        when (root) {
            is String -> yield(root)
            is List<*> -> root.forEach { yieldAll(strings(it)) }
        }
    }
}
