import SwiftUI
import VelaCore

/**
 * A diagnostic launch path that avoids MapLibre/MapKit, AppModel, location updates, network calls,
 * background services and Live Activities. It never touches saved places or settings. It activates
 * with `--safe-mode`, with the persisted safe-mode switch, or after a launch that did not survive
 * its first fifteen seconds.
 */
enum SafeMode {
    static let active: Bool = {
        let defaults = UserDefaults.standard
        if ProcessInfo.processInfo.arguments.contains("--safe-mode") { return true }
        // The screenshot and UI-test demo launches must always show the real
        // screens, even when an earlier debug launch left the switch on.
        if ProcessInfo.processInfo.arguments.contains("-demo") { return false }
        if defaults.bool(forKey: "safeMode") { return true }
        // Two launches in a row that neither became healthy nor went to the background cleanly.
        // One crash is not a loop, and a user who opens and swipes away the app is not a crash.
        var health = defaults.data(forKey: LaunchHealthStore.key).flatMap { try? JSONDecoder().decode(LaunchHealth.self, from: $0) }
            ?? LaunchHealth()
        let enter = health.launch()
        LaunchHealthStore.save(health)
        if enter {
            defaults.set(true, forKey: "safeMode")
            LaunchTrace.mark("two launches in a row did not reach ready; safe mode enabled")
            return true
        }
        return false
    }()

    static func leave() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "safeMode")
        LaunchHealthStore.markHealthy()
    }
}

enum LaunchHealthStore {
    static let key = "launchHealth"

    static func save(_ health: LaunchHealth) {
        if let data = try? JSONEncoder().encode(health) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func markHealthy() {
        var health = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(LaunchHealth.self, from: $0) }
            ?? LaunchHealth()
        health.markHealthy()
        save(health)
    }
}

/** Small, privacy-safe breadcrumbs for the next launch after a crash. No coordinates or queries. */
enum LaunchTrace {
    private static let key = "kiteLaunchTrace"
    private static let lock = NSLock()

    static func mark(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        let defaults = UserDefaults.standard
        var lines = defaults.stringArray(forKey: key) ?? []
        let stamp = ISO8601DateFormatter().string(from: Date())
        lines.append("\(stamp) \(event)")
        if lines.count > 40 { lines.removeFirst(lines.count - 40) }
        defaults.set(lines, forKey: key)
    }

    static var lines: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /** Called after the first screen has stayed up long enough to count as a healthy launch. */
    static func markReady() {
        LaunchHealthStore.markHealthy()
    }
}

struct SafeModeView: View {
    @AppStorage("safeMode") private var safeMode = true
    @State private var note: String?

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Kite started in safe mode because the previous launch may have crashed.")
                    Text("Maps, navigation, location updates, live transit, background services and Live Activities are disabled. Your saved places and settings were not changed.")
                        .font(.footnote).foregroundColor(.secondary)
                } header: {
                    Text("Safe mode")
                }
                Section("Build") {
                    LabeledContent("Version", value: version)
                    LabeledContent("Bundle", value: Bundle.main.bundleIdentifier ?? "?")
                }
                Section {
                    Toggle("Start in safe mode next time", isOn: $safeMode)
                    Button("Leave safe mode") {
                        SafeMode.leave()
                        safeMode = false
                        note = "Safe mode is off. Close Kite completely and open it again."
                    }
                    if let note { Text(note).font(.footnote).foregroundColor(.secondary) }
                } footer: {
                    Text("If Kite still crashes with safe mode on, the problem is in startup, signing, frameworks or a stored setting. Send this screen and the last launch log to the developer.")
                }
                Section("Last MetricKit crash") {
                    if let crash = CrashDiagnostics.last, !crash.isEmpty {
                        Text(crash).font(.caption.monospaced()).textSelection(.enabled)
                    } else {
                        Text("No crash diagnostic delivered yet. iOS usually delivers it on a later launch.")
                            .foregroundColor(.secondary)
                    }
                }
                Section("Last launch trace") {
                    let lines = LaunchTrace.lines
                    if lines.isEmpty {
                        Text("No trace recorded.").foregroundColor(.secondary)
                    } else {
                        ForEach(Array(lines.suffix(12).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Kite safe mode")
        }
        .navigationViewStyle(.stack)
    }
}
