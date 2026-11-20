import SwiftUI

@main
struct VelaApp: App {
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
            }
        }
    }
}
