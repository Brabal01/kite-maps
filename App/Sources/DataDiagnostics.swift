import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VelaCore

/**
 * "Share diagnostics": checks that the services Kite leans on answer, and packs the results
 * (plus, if you choose, a picture of the map) into a ZIP you can send with a bug report.
 * Adapted from Ausbloke's Kite fork (github.com/NotDiscordOfficial/kite-maps), GPL-3.0.
 * Tests use a fixed spot in central London, never your position.
 */
@MainActor
final class DataDiagnostics: ObservableObject {
    @Published var running = false
    @Published var status = "Ready"
    @Published var report: URL?
    @Published private(set) var entries: [DiagnosticZip.Entry] = []

    private static let version: String = {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }()

    func invalidateExport() {
        if let report { try? FileManager.default.removeItem(at: report) }
        report = nil
        entries = []
    }

    func run(model: AppModel, includeMap: Bool, level: DiagnosticsLog.ReportLevel,
             incident: NavigationReplayIncident?) {
        guard !running else { return }
        invalidateExport()
        running = true
        status = "Testing…"
        let mapImage: Data? = {
            guard includeMap, let map = model.map, map.bounds.width > 0, map.bounds.height > 0 else { return nil }
            return UIGraphicsImageRenderer(bounds: map.bounds).image { _ in
                map.mapView.drawHierarchy(in: map.bounds, afterScreenUpdates: true)
            }.pngData()
        }()
        let s = model.settings
        Task {
            var entries: [DiagnosticZip.Entry] = []
            var lines = [
                "Kite diagnostics",
                "Kite: \(Self.version)",
                "App ID: \(Bundle.main.bundleIdentifier ?? "?")",
                "iOS: \(UIDevice.current.systemVersion), \(Self.deviceModel())",
                "Location allowed: \(model.location.authorized), precise: \(!model.location.reducedAccuracy)",
                "Road alerts: \(s.wazeOn), on map: \(s.wazeOnMap), heat map: \(s.wazeHeatmap), no Google: \(s.noGoogle)",
                "Speed cameras: \(s.speedCameras), plate cameras: \(s.plateCameras), surveillance: \(s.surveillanceCameras)",
                "Navigating: \(model.nav != nil)",
                "Roundabout resolutions: \(model.nav?.roundaboutDiagnostics.count ?? 0)",
                "Map picture included: \(mapImage != nil) (it can show exactly where you are).",
                "Navigation report level: \(level.rawValue) — \(level.explanation)",
                "Incident fixture included: \(incident != nil) (can identify your location).",
                "Account and search data are excluded.",
                "",
                "Service tests (fixed box in central London):",
            ]
            if let mapImage { entries.append(.init(name: "map.png", data: mapImage)) }
            if DiagnosticsLog.shared.count > 0 {
                entries.append(.init(name: "navigation-events.json",
                                     data: DiagnosticsLog.shared.report(appVersion: Self.version, level: level)))
            }
            if let incident {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(incident) {
                    entries.append(.init(name: "navigation-incident.json", data: data))
                }
            }

            @MainActor func timed<T>(_ name: String, _ work: () async -> T?, describe: (T) -> String) async {
                status = L10n.format("Testing %@…", name)
                let t0 = Date()
                let result = await work()
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                lines.append("\(name): " + (result.map(describe) ?? "FAILED") + ", \(ms) ms")
            }
            await timed("Waze live map", { await Waze.alerts(south: 51.49, west: -0.15, north: 51.53, east: -0.08) }) {
                "\($0.count) reports"
            }
            await timed("Speed cameras (OpenStreetMap)", {
                await Overpass.cameras(south: 51.49, west: -0.15, north: 51.53, east: -0.08, speed: true, plate: true)
            }) { "\($0.count) cameras" }

            entries.insert(.init(name: "diagnostics.txt", data: Data(lines.joined(separator: "\n").utf8)), at: 0)
            do {
                let zip = try DiagnosticZip.archive(entries)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Kite-diagnostics-\(UUID().uuidString).zip")
                try zip.write(to: url, options: .atomic)
                self.entries = entries
                report = url
                status = "Ready to share."
            } catch {
                status = L10n.format("Couldn't make the file: %@", error.localizedDescription)
            }
            running = false
        }
    }

    private static func deviceModel() -> String {
        var sys = utsname()
        uname(&sys)
        return withUnsafeBytes(of: &sys.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

struct DataDiagnosticsView: View {
    @ObservedObject var model: AppModel
    @StateObject private var diagnostics = DataDiagnostics()
    @State private var includeMap = false
    @State private var level: DiagnosticsLog.ReportLevel = .technical
    @State private var detailed = DiagnosticsLog.shared.isDetailed
    @State private var confirmReplay = false
    @State private var showPreview = false
    @State private var confirmIncident = false
    @State private var captured: NavigationReplayIncident?
    @State private var includeIncident = false
    @State private var openFixture = false
    @State private var fixtureError = false
    @State private var imported: NavigationReplayIncident?
    @State private var replayed: NavigationReplayIncident.Observation?
    @State private var expectedExit = ""
    @State private var expectedSignals = ""

    var body: some View {
        Form {
            Section {
                Picker("What to include", selection: Binding(
                    get: { level },
                    set: { new in
                        if new == .replay { confirmReplay = true } else { level = new }
                    })) {
                    ForEach(DiagnosticsLog.ReportLevel.allCases, id: \.self) { Text(L10n.text($0.title)).tag($0) }
                }
                Text(L10n.text(level.explanation)).font(.footnote).foregroundColor(.secondary)
                Toggle("Include a picture of the map", isOn: $includeMap)
                Button(L10n.text(diagnostics.running ? "Testing…" : "Run tests")) {
                    var incident = includeIncident ? captured : nil
                    incident?.expectedRoundaboutExit = Int(expectedExit)
                    incident?.expectedTrafficLights = Int(expectedSignals)
                    diagnostics.run(model: model, includeMap: includeMap, level: level, incident: incident)
                }
                Text(L10n.text(diagnostics.status)).font(.footnote).foregroundColor(.secondary)
                if let report = diagnostics.report {
                    Button("Preview every archive file") { showPreview = true }
                    ShareLink(item: report) { Label("Share diagnostics", systemImage: "square.and.arrow.up") }
                }
            } footer: {
                Text("Checks that Waze and OpenStreetMap answer, then makes a file for a bug report. Nothing is sent until you share it. A map picture can show exactly where you are; a movement trace can still identify you if someone knows where you started.")
            }

            Section {
                Toggle("Map Layer Inspector", isOn: Binding(
                    get: { model.layerInspectionEnabled }, set: { model.setLayerInspection($0) }
                ))
            } footer: {
                Text("Return to the map to isolate layers while parked. Close the inspector to restore every layer.")
            }

            Section {
                Toggle("Detailed diagnostics", isOn: $detailed)
                    .onChange(of: detailed) { on in
                        DiagnosticsLog.shared.setDetailed(on)
                        if !on {
                            level = .technical
                            clearIncident()
                        }
                    }
                Button("Delete recorded diagnostics", role: .destructive) {
                    DiagnosticsLog.shared.clear()
                    model.nav?.clearIncidentFixes()
                    clearIncident()
                    diagnostics.invalidateExport()
                }
            } header: { Text("Privacy") } footer: {
                Text("Kite keeps technical events (distance along the route, GPS accuracy, speed) in memory for up to 3 hours. They are never written to disk and end when you close Kite. Detailed mode additionally remembers where they happened so a roundabout or GPS fault can be replayed; turning it off forgets those positions immediately.")
            }

            Section {
                if detailed, let nav = model.nav {
                    Button("Capture the last manoeuvre") {
                        clearIncident()
                        captured = nav.captureReplayIncident()
                        if captured == nil { fixtureError = true }
                    }
                }
                if let captured {
                    Text(captured.observed.instruction)
                    TextField("Expected roundabout exit (optional)", text: $expectedExit).keyboardType(.numberPad)
                    TextField("Expected traffic-light count (optional)", text: $expectedSignals).keyboardType(.numberPad)
                    Button(includeIncident ? "Remove incident from export" : "Include captured incident in export") {
                        if includeIncident { includeIncident = false } else { confirmIncident = true }
                    }
                }
                Button("Import navigation incident JSON") { openFixture = true }
                if let imported, let replayed {
                    LabeledContent("Recorded instruction", value: imported.observed.instruction)
                    LabeledContent("Replayed instruction", value: replayed.instruction)
                    LabeledContent("Replayed roundabout exit", value: replayed.roundaboutExit.map(String.init) ?? "—")
                    if let exit = imported.expectedRoundaboutExit {
                        LabeledContent("Expected exit", value: String(exit))
                    }
                    LabeledContent("Replayed traffic lights", value: String(replayed.trafficLights))
                    if let count = imported.expectedTrafficLights {
                        LabeledContent("Expected traffic lights", value: String(count))
                    }
                    LabeledContent("Replayed off-route state", value: replayed.offRoute ? "Off route" : "On route")
                }
            } header: {
                Text("Navigation incident")
            } footer: {
                Text("After stopping safely, capture up to 45 seconds of recent fixes and nearby route geometry. Import the extracted JSON here to run it through an isolated tracker.")
            }

            if model.nav != nil {
                if let session = model.replaySession {
                    ReplayControlsView(session: session, model: model)
                } else {
                    Section {
                        ForEach(ReplaySession.Fault.allCases) { fault in
                            Button("Replay: \(fault.title)") { model.startReplay(fault) }
                        }
                    } header: { Text("Developer: GPS replay") } footer: {
                        Text("Uses a separate GPS tracker and shows its instructions here. Your actual journey continues independently.")
                    }
                }
            }
            if let nav = model.nav {
                Section("Current instruction evidence") {
                    if let maneuver = nav.nextManeuver {
                        Text(maneuver.instruction)
                        LabeledContent("Routing source", value: nav.route.source)
                        if maneuver.type == .roundabout {
                            LabeledContent("Exit source", value: maneuver.exitSource?.rawValue ?? "Unavailable")
                            if let confidence = maneuver.exitConfidence {
                                LabeledContent("Exit confidence", value: confidence.formatted(.percent.precision(.fractionLength(0))))
                            }
                            if maneuver.exitAmbiguous { Text("Available sources disagree about the exit.") }
                        }
                    }
                    if let signal = nav.upcomingControls.first(where: { $0.control.kind == .light })?.control {
                        LabeledContent("Traffic light source", value: signal.source)
                        LabeledContent("Traffic light confidence", value: signal.confidence.formatted(.percent.precision(.fractionLength(0))))
                        Text(signal.directionCertain ? "Matched to the current approach." : "Approach direction is uncertain.")
                    }
                }
            }
            if let nav = model.nav, !nav.roundaboutDiagnostics.isEmpty {
                Section("Roundabouts on this route") {
                    ForEach(nav.roundaboutDiagnostics, id: \.self) { line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
        }
        .disabled(diagnostics.running)
        .onChange(of: includeMap) { _ in diagnostics.invalidateExport() }
        .onChange(of: level) { _ in diagnostics.invalidateExport() }
        .onChange(of: detailed) { _ in diagnostics.invalidateExport() }
        .onChange(of: includeIncident) { _ in diagnostics.invalidateExport() }
        .onChange(of: expectedExit) { _ in diagnostics.invalidateExport() }
        .onChange(of: expectedSignals) { _ in diagnostics.invalidateExport() }
        .fileImporter(isPresented: $openFixture, allowedContentTypes: [.json]) { result in
            imported = nil
            replayed = nil
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size <= 2_000_000, let incident = NavigationReplayIncident.decode(try Data(contentsOf: url)),
                      let replay = incident.replay() else { fixtureError = true; return }
                imported = incident
                replayed = replay
            } catch { fixtureError = true }
        }
        .alert("No usable navigation incident", isPresented: $fixtureError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Capture needs recent GPS fixes on the current route. Import needs a valid navigation-incident.json file.")
        }
        .kiteList()
        .navigationTitle("Diagnostics")
        .sheet(isPresented: $showPreview) {
            NavigationView {
                List(diagnostics.entries, id: \.name) { entry in
                    NavigationLink(entry.name) {
                        ScrollView([.vertical, .horizontal]) {
                            if entry.name == "map.png", let map = UIImage(data: entry.data) {
                                Image(uiImage: map).resizable().scaledToFit()
                                    .frame(width: 320).padding()
                            } else {
                                Text(String(decoding: entry.data, as: UTF8.self))
                                    .font(.caption.monospaced()).textSelection(.enabled).padding()
                            }
                        }
                        .navigationTitle(entry.name)
                    }
                }
                .navigationTitle("Export preview")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showPreview = false }
                    }
                }
            }
            .navigationViewStyle(.stack)
        }
        .confirmationDialog("Include the exact incident locations?", isPresented: $confirmIncident, titleVisibility: .visible) {
            Button("I consent to including the incident") { includeIncident = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This file includes real GPS coordinates, nearby route geometry and instruction text. It can reveal your identity or where you travelled. Share it only with someone you trust.")
        }
        .confirmationDialog("Share a detailed movement trace?", isPresented: $confirmReplay, titleVisibility: .visible) {
            Button("I consent to including it") { level = .replay }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The export can include your recent movement shape and roundabout road names. Those details can identify you or where you travelled even without coordinates. Share it only with someone you trust.")
        }
    }

    private func clearIncident() {
        captured = nil
        includeIncident = false
        expectedExit = ""
        expectedSignals = ""
        if !detailed { model.nav?.clearIncidentFixes() }
    }

}


/// Controls for a running replay: pause, speed, jump to a turn, and fault injection.
struct ReplayControlsView: View {
    @ObservedObject var session: ReplaySession
    @ObservedObject var model: AppModel

    var body: some View {
        Section {
            HStack {
                Text("\(Int(session.progress * 100))%").monospacedDigit()
                Spacer()
                Text(session.fault.title).foregroundColor(.secondary)
            }
            if !session.instruction.isEmpty { Text(session.instruction).font(.subheadline) }
            if !session.note.isEmpty { Text(session.note).font(.caption).foregroundColor(.secondary) }
            Button(session.paused ? "Resume" : "Pause") {
                session.paused ? model.resumeReplay() : model.pauseReplay()
            }
            .accessibilityIdentifier("replay-pause")
            Picker("Speed", selection: Binding(
                get: { session.speed },
                set: { session.speed = $0 })) {
                ForEach([0.5, 1.0, 2.0, 4.0], id: \.self) { Text("\($0, specifier: "%.1f")×").tag($0) }
            }
            .pickerStyle(.segmented)
            Button("Skip to next manoeuvre") { model.skipToNextManeuver() }
                .accessibilityIdentifier("replay-skip")
            Toggle("Simulate no internet", isOn: Binding(
                get: { session.simulateOffline },
                set: { model.setReplayOffline($0) }))
            Button("Stop replay", role: .destructive) { model.stopReplay() }
                .accessibilityIdentifier("replay-stop-detail")
        } header: { Text("Developer: GPS replay running") } footer: {
            Text("Replay has a separate tracker. Live guidance, history and Live Activity continue to use real GPS.")
        }
    }
}
