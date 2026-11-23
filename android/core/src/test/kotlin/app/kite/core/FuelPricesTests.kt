package app.kite.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class FuelPricesTests {
    @Test fun onlyUsesPriceLikeGoogleLabels() {
        assertEquals("$3.95/Regular", FuelPrices.googleLabel("$3.95/Regular"))
        assertEquals("36,90 Kč/l", FuelPrices.googleLabel("36,90\u00a0Kč/l"))
        assertNull(FuelPrices.googleLabel("Diesel B7"))
        assertNull(FuelPrices.googleLabel("Open until 10 pm"))
    }

    @Test fun onlyMatchesRecentAndUnambiguousPrices() {
        val stations = FuelPrices.readStations(
            """
            brand,lat,lng,e10,e5,b7s,b7p,updated
            "A, Fuels",51.50000,-0.12000,153.9,,160,,1785000000
            B,51.50000,-0.12060,157,,162,,1785000000
            C,52.60,-1.3,999,,,,1785000000
            """.trimIndent().reader(),
        )
        assertEquals(2, stations.size)
        val now = 1785000000 + 100L
        assertEquals(listOf("E10 153.9 p/L", "Diesel 160 p/L"), FuelPrices.match(LatLng(51.5, -0.12), stations, now)?.labels)
        assertNull(FuelPrices.match(LatLng(51.5, -0.1203), stations, now))
        assertNull(FuelPrices.match(LatLng(51.5, -0.12), stations, now + 8 * 86400))
    }
}
