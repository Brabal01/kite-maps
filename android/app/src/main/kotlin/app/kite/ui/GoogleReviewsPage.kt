package app.kite.ui

import android.annotation.SuppressLint
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.*
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import app.kite.core.GooglePlaceMedia
import app.kite.core.Place
import app.kite.primaryText

/** Google Maps' public reviews tab as an in-app fallback when the native feed is empty. */
@SuppressLint("SetJavaScriptEnabled")
@Composable
internal fun GoogleReviewsPage(place: Place, close: () -> Unit) {
    val ctx = LocalContext.current
    val cid = place.featureId?.let(GooglePlaceMedia::cid)
    val url = cid?.let { "https://www.google.com/maps?cid=$it&hl=en" } ?: place.shareUrl
    var loading by remember(url) { mutableStateOf(true) }
    var error by remember(url) { mutableStateOf(false) }
    TripSheet("Google Maps reviews", "Done", close) {
        Box(Modifier.fillMaxSize()) {
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { context ->
                    WebView(context).apply {
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.allowFileAccess = false
                        settings.allowContentAccess = false
                        webViewClient = object : WebViewClient() {
                            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                                if (!request.isForMainFrame) return false
                                val target = request.url
                                if (target.scheme == "https" && target.host in setOf("www.google.com", "consent.google.com")) return false
                                if (target.scheme == "https" || target.scheme == "http") ctx.open(target.toString())
                                return true
                            }

                            override fun onReceivedError(view: WebView, request: WebResourceRequest, failure: WebResourceError) {
                                if (request.isForMainFrame) { error = true; loading = false }
                            }

                            override fun onPageFinished(view: WebView, URL: String) {
                                loading = false
                                if (view.url?.startsWith("https://www.google.com/maps") == true) {
                                    view.evaluateJavascript(SELECT_REVIEWS, null)
                                }
                            }
                        }
                        loadUrl(url)
                    }
                },
                onReset = null,
                onRelease = { view -> view.stopLoading(); view.destroy() },
            )
            if (loading) CircularProgressIndicator(Modifier.align(Alignment.Center).size(28.dp))
            if (error) Column(Modifier.align(Alignment.Center).padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Google Maps could not load the reviews.", color = primaryText)
                TextButton({ ctx.open(place.shareUrl) }) { Text("Open in Google Maps") }
            }
        }
    }
}

private const val SELECT_REVIEWS = """(() => {
    if (window.kiteReviewTab) return;
    window.kiteReviewTab = true;
    let attempts = 0;
    const timer = setInterval(() => {
        const button = [...document.querySelectorAll('[role="tab"],button')].find(el =>
            /^reviews(?: for .+)?$/i.test((el.getAttribute('aria-label') || el.textContent || '').trim()));
        if (button) button.click();
        if (button || ++attempts === 20) clearInterval(timer);
    }, 400);
})();"""
