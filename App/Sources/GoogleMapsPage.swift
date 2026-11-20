import SwiftUI
import WebKit

/// A user-visible Google Maps page. Reviews, media and sorting stay in Google's controls.
struct GoogleMapsPage: View {
    enum Section: String {
        case reviews, photos
    }

    let url: URL
    let title: String
    var section: Section? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                GoogleMapsWebView(url: url, section: section, loading: $loading, failed: $failed)
                    .id(retry)
                if loading && !failed {
                    ProgressView().padding(12)
                        .background(.regularMaterial, in: Capsule()).padding()
                }
                if failed {
                    VStack(spacing: 16) {
                        Text(L10n.isCzech ? "Stránku Google Maps se nepodařilo načíst." : "The Google Maps page could not load.")
                        Button(L10n.text("Reload")) {
                            failed = false
                            loading = true
                            retry += 1
                        }
                        Link("Google Maps", destination: url)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Link(destination: url) {
                        Label("Google Maps", systemImage: "arrow.up.right.square")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }.navigationViewStyle(.stack)
    }
}

private struct GoogleMapsWebView: UIViewRepresentable {
    let url: URL
    let section: GoogleMapsPage.Section?
    @Binding var loading: Bool
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(loading: $loading, failed: $failed) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if let section {
            // Select only a visible Maps content tab. If Google changes its layout the normal
            // page stays available so the user can choose the tab directly.
            let labels = section == .reviews
                ? #"^(reviews|recenze|bewertungen|avis|reseñas|recensioni|opinie|recenzie)(\s+.*)?$"#
                : #"^(photos|fotky|fotografie|fotos|fotografías|foto|zdjęcia)(\s+.*)?$"#
            let script = """
            (() => {
              if (location.hostname !== 'www.google.com' || !/^\\/maps(?:\\/|$)/.test(location.pathname)) return;
              const wanted = /\(labels)/i;
              const open = () => {
                const tab = Array.from(document.querySelectorAll('[role="tab"]')).find(element =>
                  element.getClientRects().length && wanted.test((element.getAttribute('aria-label') || element.textContent || '').trim()));
                if (!tab) return false;
                if (tab.getAttribute('aria-selected') !== 'true') tab.click();
                return true;
              };
              if (open()) return;
              const observer = new MutationObserver(() => { if (open()) observer.disconnect(); });
              observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['aria-label'] });
              setTimeout(() => observer.disconnect(), 8000);
            })();
            """
            configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            )
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url, timeoutInterval: 20))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        uiView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding var loading: Bool
        @Binding var failed: Bool

        init(loading: Binding<Bool>, failed: Binding<Bool>) {
            _loading = loading
            _failed = failed
        }

        private func allows(_ url: URL?) -> Bool {
            guard let url, url.scheme == "https", let host = url.host else { return false }
            if host == "consent.google.com" { return true }
            return (host == "www.google.com" || host == "maps.google.com")
                && (url.path == "/" || url.path == "/maps" || url.path.hasPrefix("/maps/") || url.path == "/sorry/index")
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.targetFrame?.isMainFrame == false {
                decisionHandler(.allow)
            } else {
                decisionHandler(allows(action.request.url) ? .allow : .cancel)
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.targetFrame == nil, allows(action.request.url) { webView.load(action.request) }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            showFailure(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            loading = false
            failed = true
        }

        private func showFailure(_ error: Error) {
            guard (error as? URLError)?.code != .cancelled else { return }
            loading = false
            failed = true
        }
    }
}
