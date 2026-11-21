import Foundation
import SwiftUI
import UIKit
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
    @Published var preview = ""

    private static let version: String = {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }()

    /// What the user would share, before anything is written or sent.
    func refreshPreview(level: DiagnosticsLog.ReportLevel) {
        let data = DiagnosticsLog.shared.report(appVersion: Self.version, level: level)
        preview = String(decoding: data.prefix(8_000), as: UTF8.self)
    }

    func run(model: AppModel, includeMap: Bool, level: DiagnosticsLog.ReportLevel) {
        guard !running else { return }
        running = true; report = nil; status = "Testing…"
        let mapImage: Data? = {
            guard includeMap, let map = model.map, map.bounds.width > 0, map.bounds.height > 0 else { return nil }
            return UIGraphicsImageRenderer(bounds: map.bounds).image { _ in
                map.mapView.drawHierarchy(in: map.bounds, afterScreenUpdates: true)
            }.pngData()
        }()
        let s = model.settings
        let info = Bundle.main.infoDictionary
        Task {
            var entries: [DiagnosticZip.Entry] = []
            var lines = [
                "Kite diagnostics",
                "Created (UTC): \(ISO8601DateFormatter().string(from: Date()))",
                "Kite: \(Self.version)",
                "App ID: \(Bundle.main.bundleIdentifier ?? "?")",
                "iOS: \(UIDevice.current.systemVersion), \(Self.deviceModel())",
                "Location allowed: \(model.location.authorized), precise: \(!model.location.reducedAccuracy)",
                "GPS accuracy now: \(model.location.last.map { "\(Int($0.horizontalAccuracy)) m" } ?? "no fix")",
                "Road alerts: \(s.wazeOn), on map: \(s.wazeOnMap), heat map: \(s.wazeHeatmap), no Google: \(s.noGoogle)",
                "Speed cameras: \(s.speedCameras), plate cameras: \(s.plateCameras), surveillance: \(s.surveillanceCameras)",
                "Live cameras: \(s.liveCams) (road \(s.liveRoadCams), webcams \(s.liveWebcams), route \(s.liveCamsOnRoute)), list: \(LiveCamStore.shared.status ?? "not loaded")",
                "Navigating: \(model.nav != nil)",
                "Roundabout resolutions: \(model.nav?.roundaboutDiagnostics.count ?? 0)",
                "Map picture included: \(mapImage != nil) (it can show exactly where you are).",
                "Navigation report level: \(level.rawValue) — \(level.explanation)",
                "No GPS position, searches, saved places or accounts are in this file.",
                "",
                "Service tests (fixed box in central London):",
            ]
            if let mapImage { entries.append(.init(name: "map.png", data: mapImage)) }
            if DiagnosticsLog.shared.count > 0 {
                entries.append(.init(name: "navigation-events.json",
                                     data: DiagnosticsLog.shared.report(appVersion: Self.version, level: level)))
            }
            if let nav = model.nav, !nav.roundaboutDiagnostics.isEmpty {
                lines.append("")
                lines.append("Roundabout resolutions (route distances only, no coordinates):")
                lines += nav.roundaboutDiagnostics
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
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Kite-diagnostics.zip")
                try zip.write(to: url, options: .atomic)
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
                Button("Preview what will be shared") {
                    diagnostics.refreshPreview(level: level)
                    showPreview = true
                }
                Button(L10n.text(diagnostics.running ? "Testing…" : "Run tests")) {
                    diagnostics.run(model: model, includeMap: includeMap, level: level)
                }
                .disabled(diagnostics.running)
                Text(L10n.text(diagnostics.status)).font(.footnote).foregroundColor(.secondary)
                if let report = diagnostics.report {
                    ShareLink(item: report) { Label("Share diagnostics", systemImage: "square.and.arrow.up") }
                }
            } footer: {
                Text("Checks that Waze and OpenStreetMap answer, then makes a file for a bug report. Nothing is sent until you share it. A map picture can show exactly where you are; a movement trace can still identify you if someone knows where you started.")
            }

            Section {
                Toggle("Detailed diagnostics", isOn: $detailed)
                    .onChange(of: detailed) { on in
                        DiagnosticsLog.shared.setDetailed(on)
                        if !on, level != .technical { level = .technical }
                    }
                Button("Delete recorded diagnostics", role: .destructive) { DiagnosticsLog.shared.clear() }
            } header: { Text("Privacy") } footer: {
                Text("Kite keeps technical events (distance along the route, GPS accuracy, speed) in memory for up to 3 hours. They are never written to disk and end when you close Kite. Detailed mode additionally remembers where they happened so a roundabout or GPS fault can be replayed; turning it off forgets those positions immediately.")
            }

            if model.nav != nil {
                Section {
                    if model.isReplaying {
                        Button("Stop the simulated drive", role: .destructive) { model.stopReplay() }
                    } else {
                        Button("Replay this route (clean GPS)") { model.startReplay(.clean) }
                        Button("Replay with noisy GPS and a tunnel") { model.startReplay(.rough) }
                    }
                } header: { Text("Developer: GPS replay") } footer: {
                    Text("Drives the current route with a simulated GPS. Your real position is ignored meanwhile, nothing is saved, and an orange banner stays on screen until you stop it.")
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
        .kiteList()
        .navigationTitle("Diagnostics")
        .sheet(isPresented: $showPreview) {
            NavigationView {
                ScrollView {
                    Text(diagnostics.preview).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
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
        .confirmationDialog("Share a detailed movement trace?", isPresented: $confirmReplay, titleVisibility: .visible) {
            Button("I consent to including it") { level = .replay }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The export holds the shape of your recent movement as metres from an unknown start. It has no coordinates, but someone who knows your home, work or usual route could still recognise it. Share it only with someone you trust with that.")
        }
    }
}
