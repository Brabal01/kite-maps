import SwiftUI

@main
struct VelaApp: App {
    @AppStorage("language") private var languageRaw = ""
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LaunchTrace.mark("app init")
        CrashDiagnostics.shared.start()
        if !SafeMode.active { WazeWeb.install() }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if SafeMode.active {
                    SafeModeView()
                } else {
                    ContentView()
                        .environment(\.locale, KiteLanguage(rawValue: languageRaw)?.locale ?? .current)
                }
            }
            // Going to the background is a clean exit: a crash cannot happen after it, so it is never
            // counted against the launch (opening Kite and swiping it away is not a crash loop).
            .onChange(of: scenePhase) { phase in
                if phase == .background { LaunchHealthStore.markHealthy() }
            }
        }
    }
}
