import MapLibre
import SwiftUI

/// Region bounds from the GPLv3 Kite Driving catalogue (Geofabrik and Eurostat GISCO).
private struct OfflineMapRegion: Decodable, Identifiable {
    let id: String
    let name: String
    let south: Double
    let west: Double
    let north: Double
    let east: Double

    init(from decoder: Decoder) throws {
        var row = try decoder.unkeyedContainer()
        id = try row.decode(String.self)
        _ = try row.decode(String?.self)
        name = try row.decode(String.self)
        south = try row.decode(Double.self)
        west = try row.decode(Double.self)
        north = try row.decode(Double.self)
        east = try row.decode(Double.self)
    }

    var bounds: MLNCoordinateBounds {
        MLNCoordinateBounds(sw: .init(latitude: south, longitude: west),
                            ne: .init(latitude: north, longitude: east))
    }

    var maximumZoom: Double {
        func mercator(_ latitude: Double) -> Double {
            asinh(tan(latitude * .pi / 180)) / (2 * .pi)
        }
        return Double((4...15).reversed().first { zoom in
            let side = Double(1 << zoom)
            let width = ceil((east - west) / 360 * side) + 1
            let height = ceil((mercator(north) - mercator(south)) * side) + 1
            return width * height <= 1800
        } ?? 4)
    }

    static let catalogue: [OfflineMapRegion] = {
        guard let url = Bundle.main.url(forResource: "offline-regions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let regions = try? JSONDecoder().decode([OfflineMapRegion].self, from: data) else { return [] }
        return regions.filter { $0.south >= -85 && $0.north <= 85 && $0.south < $0.north && $0.west < $0.east }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()
}

struct OfflineMapsPage: View {
    @State private var query = ""
    @State private var busy = false
    @State private var error: String?
    @State private var pendingRemoval: MLNOfflinePack?

    private var storage: MLNOfflineStorage { .shared }
    private var title: String { L10n.isCzech ? "Offline mapy" : "Offline maps" }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let packs = storage.packs ?? []
            let active = packs.contains { $0.state == .active }
            let downloaded = Set(packs.compactMap { String(data: $0.context, encoding: .utf8) })
            List {
                Section {
                    if storage.packs == nil {
                        ProgressView()
                    } else if packs.isEmpty {
                        Text(L10n.isCzech ? "Zatím žádné oblasti" : "No downloaded areas").foregroundStyle(.secondary)
                    }
                    ForEach(packs, id: \.self) { pack in
                        packRow(pack, downloading: active)
                    }
                } header: {
                    Text(L10n.isCzech ? "Stažené oblasti" : "Downloaded areas")
                } footer: {
                    Text(L10n.isCzech
                         ? "Stažené oblasti slouží k prohlížení v režimu OpenFreeMap."
                         : "Downloaded areas are available for browsing in OpenFreeMap mode.")
                }
                Section(L10n.isCzech ? "Katalog oblastí" : "Region catalogue") {
                    ForEach(OfflineMapRegion.catalogue.filter { region in
                        !downloaded.contains(region.id) &&
                        (query.isEmpty || region.name.localizedStandardContains(query) || region.id.localizedStandardContains(query))
                    }) { region in
                        Button { download(region) } label: {
                            Label(region.name, systemImage: "arrow.down.circle")
                        }
                        .disabled(active || busy || storage.packs == nil)
                    }
                }
            }
        }
        .navigationTitle(title)
        .searchable(text: $query)
        .task {
            while !Task.isCancelled, storage.packs == nil {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard !Task.isCancelled else { return }
            storage.packs?.forEach { $0.requestProgress() }
        }
        .alert(title, isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
        .confirmationDialog(L10n.isCzech ? "Smazat staženou oblast?" : "Remove downloaded area?",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible) {
            Button(L10n.isCzech ? "Smazat" : "Remove", role: .destructive) {
                if let pack = pendingRemoval {
                    pendingRemoval = nil
                    remove(pack)
                }
            }
        }
    }

    private func packRow(_ pack: MLNOfflinePack, downloading: Bool) -> some View {
        let id = String(data: pack.context, encoding: .utf8) ?? ""
        let name = OfflineMapRegion.catalogue.first { $0.id == id }?.name ?? id
        let progress = pack.progress
        return HStack {
            VStack(alignment: .leading) {
                Text(name)
                Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: progress.countOfBytesCompleted),
                                               countStyle: .file))
                    .font(.caption).foregroundStyle(.secondary)
                if pack.state == .active {
                    if progress.countOfResourcesExpected > 0,
                       progress.maximumResourcesExpected == progress.countOfResourcesExpected {
                        ProgressView(value: Double(progress.countOfResourcesCompleted),
                                     total: Double(progress.countOfResourcesExpected))
                    } else {
                        ProgressView()
                    }
                }
            }
            Spacer()
            if pack.state == .active {
                Button { pack.suspend() } label: { Image(systemName: "pause.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L10n.isCzech ? "Pozastavit stahování" : "Pause download")
            } else if pack.state == .inactive {
                Button { pack.resume() } label: { Image(systemName: "play.circle") }
                    .buttonStyle(.borderless)
                    .disabled(downloading || busy)
                    .accessibilityLabel(L10n.isCzech ? "Pokračovat ve stahování" : "Resume download")
            } else if pack.state == .complete {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .accessibilityLabel(L10n.isCzech ? "Staženo" : "Downloaded")
            }
            Button(role: .destructive) { pendingRemoval = pack } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(busy)
                .accessibilityLabel(L10n.isCzech ? "Smazat oblast" : "Remove area")
        }
    }

    private func download(_ area: OfflineMapRegion) {
        guard !busy, let packs = storage.packs,
              !packs.contains(where: { $0.state == .active || $0.context == Data(area.id.utf8) }) else { return }
        busy = true
        let maxZoom = area.maximumZoom
        let region = MLNTilePyramidOfflineRegion(styleURL: VelaMapView.styleURL, bounds: area.bounds,
                                                  fromZoomLevel: min(7, maxZoom - 2), toZoomLevel: maxZoom)
        storage.addPack(for: region, withContext: Data(area.id.utf8)) { pack, failure in
            busy = false
            if let failure { error = failure.localizedDescription }
            else { pack?.resume() }
        }
    }

    private func remove(_ pack: MLNOfflinePack) {
        guard !busy else { return }
        busy = true
        storage.removePack(pack) { failure in
            busy = false
            if let failure {
                error = failure.localizedDescription
                storage.reloadPacks()
            }
        }
    }
}
