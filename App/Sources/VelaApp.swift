import SwiftUI

@main
struct VelaApp: App {
    @ObservedObject private var settings = AppSettings.shared

    init() { WazeWeb.install() }

    var body: some Scene {
        WindowGroup {
            ContentView().environment(\.locale, settings.language.locale)
        }
    }
}
