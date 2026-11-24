package app.kite.core

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlin.math.abs
import kotlin.math.roundToInt

/** Official Prague Integrated Transport feed. A user's API token is needed on this host only. */
object PidRealtime {
    private const val BASE = "https://api.golemio.cz"
    private const val MARKER = "_cz-PID_"
    private val client = Http.client(7).newBuilder().followRedirects(false).followSslRedirects(false).build()

    data class Data(val board: TransitCall? = null, val position: LatLng? = null, val cancelled: Boolean = false)

    suspend fun forLeg(leg: TransitLeg, token: String, now: Long = System.currentTimeMillis()): Data? = coroutineScope {
        val trip = leg.tripId?.substringAfter(MARKER, "")?.takeIf { it.isNotBlank() } ?: return@coroutineScope null
        val start = leg.depart ?: return@coroutineScope null
        val end = leg.arrive ?: start
        if (token.isBlank() || now !in (start - 40 * 60_000)..(end + 15 * 60_000)) return@coroutineScope null
        val headers = mapOf("X-Access-Token" to token, "Accept" to "application/json")
        val call = leg.calls.firstOrNull()
        val stop = call?.stopId?.removePrefix("cz-PID_")?.takeIf { it != call.stopId }
        val board = async {
            if (call == null || stop == null || abs(start - now) > 40 * 60_000) return@async null
            val body = Http.getOrNull("$BASE/v2/public/departureboards?stopIds=${urlEnc(stop)}&limit=35&minutesAfter=50&minutesBefore=15",
                headers, client)?.takeIf { it.ok }?.body ?: return@async null
            parseBoard(body, trip, call)
        }
        val vehicle = async {
            if (now < start - 60_000) return@async null
            val body = Http.getOrNull("$BASE/v2/vehiclepositions/${urlEnc(trip)}", headers, client)
                ?.takeIf { it.ok }?.body ?: return@async null
            parseVehicle(body, trip, now)
        }
        val atStop = board.await()
        val gps = vehicle.await()
        if (atStop == null && gps == null) null else Data(atStop, gps?.position, gps?.cancelled == true || atStop?.cancelled == true)
    }

    internal fun parseVehicle(body: ByteArray, trip: String, now: Long): Data? {
        val obj = Json.obj(body) ?: return null
        val props = obj["properties"].asMap() ?: return null
        if (props["trip"].asMap()?.get("gtfs").asMap()?.get("trip_id") != trip) return null
        val position = props["last_position"].asMap() ?: return null
        val time = Transitous.date(position["origin_timestamp"]) ?: return null
        if (now - time !in -10_000..120_000) return null
        if (position["is_canceled"] == true) return Data(cancelled = true)
        val geometry = obj["geometry"].asMap()?.takeIf { it["type"] == "Point" } ?: return null
        val coords = geometry["coordinates"].asList() ?: return null
        val lon = coords.getOrNull(0).num()?.takeIf { it in -180.0..180.0 } ?: return null
        val lat = coords.getOrNull(1).num()?.takeIf { it in -90.0..90.0 } ?: return null
        return Data(position = LatLng(lat, lon))
    }

    internal fun parseBoard(body: ByteArray, expectedTrip: String, selected: TransitCall): TransitCall? {
        val rows = Json.parse(body).asList().orEmpty().flatMap { item ->
            item.asList().orEmpty().ifEmpty { listOf(item) }
        }.mapNotNull { it.asMap() }
        val scheduled = selected.departure ?: return null
        val row = rows.filter { it["trip"].asMap()?.get("id") == expectedTrip }.minByOrNull {
            val time = Transitous.date(it["departure"].asMap()?.get("timestamp_scheduled"))
            time?.let { abs(it - scheduled) } ?: Long.MAX_VALUE
        } ?: return null
        val departure = row["departure"].asMap().orEmpty()
        val baseline = Transitous.date(departure["timestamp_scheduled"]) ?: return null
        if (abs(baseline - scheduled) > 35 * 60_000) return null
        if (row["trip"].asMap()?.get("is_canceled") == true) return selected.copy(cancelled = true)
        val seconds = departure["delay_seconds"].num() ?: return null
        val actual = Transitous.date(departure["timestamp_predicted"]) ?: (baseline + (seconds * 1000).toLong())
        return selected.copy(departure = actual, departureDelay = (seconds / 60).roundToInt())
    }
}
