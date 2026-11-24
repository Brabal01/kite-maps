import CoreLocation
import MapLibre
import SwiftUI
import VelaCore

private struct OfflineArea: Identifiable {
    let id: String
    let parent: String?
    let name: String
    let south: Double
    let west: Double
    let north: Double
    let east: Double

    static let all: [OfflineArea] = {
        guard let url = Bundle.main.url(forResource: "offline-regions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
        return raw.compactMap { row in
            guard row.count >= 7, let id = row[0] as? String, let name = row[2] as? String,
                  let s = row[3] as? Double, let w = row[4] as? Double, let n = row[5] as? Double, let e = row[6] as? Double,
                  s < n, w < e else { return nil }
            return OfflineArea(id: id, parent: row[1] as? String, name: name, south: s, west: w, north: n, east: e)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    var zoom: Double { min(15, max(8, floor(12 - log2(max(north - south, east - west))))) }
}

@MainActor
private final class OfflineDownloads: ObservableObject {
    @Published var packs: [MLNOfflinePack] = []
    @Published var working: Set<String> = []
    @Published var error: String?
    private let storage = MLNOfflineStorage.shared

    func update() {
        packs = (storage.packs ?? []).filter { $0.state != .invalid }
        packs.filter { $0.state == .unknown }.forEach { $0.requestProgress() }
    }

    func names(_ pack: MLNOfflinePack) -> (String, String)? {
        guard let text = String(data: pack.context, encoding: .utf8), let colon = text.firstIndex(of: "\n") else { return nil }
        return (String(text[..<colon]), String(text[text.index(after: colon)...]))
    }

    func add(_ area: OfflineArea) {
        guard !working.contains(area.id), !packs.contains(where: { names($0)?.0 == area.id }) else { return }
        working.insert(area.id)
        let bounds = MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: area.south, longitude: area.west),
                                         ne: CLLocationCoordinate2D(latitude: area.north, longitude: area.east))
        let region = MLNTilePyramidOfflineRegion(styleURL: VelaMapView.styleURL, bounds: bounds,
                                                  fromZoomLevel: 4, toZoomLevel: area.zoom)
        storage.addPack(for: region, withContext: Data("\(area.id)\n\(area.name)".utf8)) { pack, error in
            Task { @MainActor in
                self.working.remove(area.id)
                self.error = error?.localizedDescription
                pack?.resume()
                self.update()
            }
        }
    }

    func delete(_ pack: MLNOfflinePack) {
        packs.removeAll { $0 === pack }
        storage.removePack(pack) { error in
            Task { @MainActor in self.error = error?.localizedDescription; self.update() }
        }
    }
}

struct OfflineMapsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var downloads = OfflineDownloads()

    var body: some View {
        List {
            Section("On this iPhone") {
                Toggle("Use downloaded basemap", isOn: $settings.offlineBasemap)
                if downloads.packs.isEmpty { Text("No areas downloaded.").foregroundStyle(.secondary) }
                ForEach(downloads.packs, id: \.self) { pack in
                    if let (_, name) = downloads.names(pack) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(name).font(.headline)
                            let progress = pack.progress
                            if pack.state == .complete {
                                Text("Ready offline").font(.caption).foregroundStyle(.secondary)
                            } else if progress.countOfResourcesExpected > 0 {
                                ProgressView(value: Double(progress.countOfResourcesCompleted),
                                             total: Double(max(progress.countOfResourcesCompleted, progress.countOfResourcesExpected)))
                            } else if pack.state == .active { ProgressView() }
                            Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: progress.countOfBytesCompleted),
                                                           countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                if pack.state != .complete {
                                    Button(pack.state == .active ? "Pause" : "Resume") {
                                        if pack.state == .active { pack.suspend() } else { pack.resume() }
                                    }
                                }
                                Button("Delete", role: .destructive) { downloads.delete(pack) }
                            }.buttonStyle(.borderless)
                        }
                    }
                }
            }
            Section("Download by country or region") {
                OfflineAreaList(parent: nil, downloads: downloads)
            }
            if let error = downloads.error { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle("Offline maps")
        .task {
            while !Task.isCancelled {
                downloads.update()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}

private struct OfflineAreaList: View {
    let parent: String?
    @ObservedObject var downloads: OfflineDownloads

    var body: some View {
        ForEach(OfflineArea.all.filter { $0.parent == parent }) { area in
            if OfflineArea.all.contains(where: { $0.parent == area.id }) {
                NavigationLink(area.name) {
                    List { OfflineAreaList(parent: area.id, downloads: downloads) }
                        .navigationTitle(area.name)
                }
            } else {
                let ready = downloads.packs.contains { downloads.names($0)?.0 == area.id }
                Button { downloads.add(area) } label: {
                    HStack {
                        Text(area.name)
                        Spacer()
                        if downloads.working.contains(area.id) { ProgressView() }
                        else { Image(systemName: ready ? "checkmark.circle" : "arrow.down.circle") }
                    }
                }.disabled(ready || downloads.working.contains(area.id))
            }
        }
    }
}
