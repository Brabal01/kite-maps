package app.kite

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import kotlin.test.assertTrue
import org.junit.Test

class MapChromeTests {
    @Test fun lightCustomPanelsAndDarkAccentsStayReadableWithTheDarkAppTheme() {
        val chrome = MapChrome(accent = Color.Black, panel = Color.White)
        val panel = chrome.panel(dark = true)
        assertTrue(contrast(Vela.muted(true), panel) >= 4.5f)
        assertTrue(contrast(chrome.icon(dark = true), panel) >= 4.5f)
    }

    @Test fun darkCustomPanelsAndLightAccentsStayReadableWithTheLightAppTheme() {
        val chrome = MapChrome(accent = Color.White, panel = Color.Black)
        val panel = chrome.panel(dark = false)
        assertTrue(contrast(Vela.muted(false), panel) >= 4.5f)
        assertTrue(contrast(chrome.icon(dark = false), panel) >= 4.5f)
    }

    private fun contrast(first: Color, second: Color): Float {
        val a = first.luminance()
        val b = second.luminance()
        return (maxOf(a, b) + 0.05f) / (minOf(a, b) + 0.05f)
    }
}
