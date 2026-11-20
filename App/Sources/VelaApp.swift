import SwiftUI

@main
struct VelaApp: App {
    @AppStorage("language") private var languageRaw = ""

    init() {
        LaunchTrace.mark("app init")
        CrashDiagnostics.shared.start()
        if !SafeMode.active { WazeWeb.install() }
    }

    var body: some Scene {
        WindowGroup {
            if SafeMode.active {
                SafeModeView()
            } else {
                ContentView()
                    .environment(\.locale, KiteLanguage(rawValue: languageRaw)?.locale ?? .current)
            }
        }
    }
}
