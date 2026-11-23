package app.kite.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class KiteLinksTests {
    @Test fun opensMapSearchAndLocalShortcuts() {
        assertEquals(KiteLinks.Target.Map, KiteLinks.parse("kite://map"))
        assertEquals(KiteLinks.Target.Search("Čerpací stanice"), KiteLinks.parse("kite://search?q=%C4%8Cerpac%C3%AD%20stanice"))
        assertEquals(KiteLinks.Target.Shortcut("shortcut:home-2"), KiteLinks.parse("kite://shortcut?id=shortcut%3Ahome-2"))
        assertEquals(KiteLinks.Target.Saved.WORK, KiteLinks.parse("kite://work"))
    }

    @Test fun validatesCoordinatesAndUsesSeparateMapAndRouteActions() {
        val at = LatLng(49.6, 17.25)
        assertEquals(KiteLinks.Target.Place(at, "Olomouc", directions = true),
            KiteLinks.parse("kite://directions?lat=49.6&lng=17.25&name=Olomouc"))
        assertEquals(KiteLinks.Target.Place(at, null, directions = false), KiteLinks.parse("kite://place?lat=49.6&lng=17.25"))
        assertNull(KiteLinks.parse("kite://place?lat=NaN&lng=17"))
        assertNull(KiteLinks.parse("kite://directions?lat=49.6&lng=180.1"))
        assertNull(KiteLinks.parse("kite://shortcut"))
        assertNull(KiteLinks.parse("https://map/?lat=49.6&lng=17.25"))
    }
}
