import MapLibre
import SwiftUI

private struct OfflineRegion: Decodable, Identifiable {
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
        func mercator(_ lat: Double) -> Double {
            asinh(tan(lat * .pi / 180)) / (2 * .pi)
        }
        return Double((4...15).reversed().first { zoom in
            let side = Double(1 << zoom)
            return (ceil((east - west) / 360 * side) + 1)
                * (ceil((mercator(north) - mercator(south)) * side) + 1) <= 1800
        } ?? 4)
    }

    static let catalogue: [Self] = {
        guard let url = Bundle.main.url(forResource: "offline-regions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let regions = try? JSONDecoder().decode([Self].self, from: data) else { return [] }
        return regions.filter { $0.south >= -85 && $0.north <= 85 && $0.south < $0.north && $0.west < $0.east }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()
}

struct OfflineRegionsView: View {
    @State private var query = ""
    @State private var busy = false
    @State private var error: String?
    private var storage: MLNOfflineStorage { .shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let packs = storage.packs ?? []
            let downloading = busy || packs.contains { $0.state == .active }
            let ids = Set(packs.compactMap { String(data: $0.context, encoding: .utf8) })
            List {
                Section {
                    if storage.packs == nil { ProgressView() }
                    else if packs.isEmpty { Text("No downloaded areas").foregroundStyle(.secondary) }
                    ForEach(packs, id: \.self) { pack in
                        HStack {
                            VStack(alignment: .leading) {
                                let id = String(data: pack.context, encoding: .utf8) ?? ""
                                Text(OfflineRegion.catalogue.first { $0.id == id }?.name ?? "Offline area")
                                Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: pack.progress.countOfBytesCompleted),
                                                               countStyle: .file))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if pack.state == .active {
                                Button { pack.suspend() } label: { Image(systemName: "pause.circle") }
                                    .accessibilityLabel("Pause download")
                            } else if pack.state == .inactive {
                                Button { pack.resume() } label: { Image(systemName: "play.circle") }
                                    .disabled(downloading).accessibilityLabel("Resume download")
                            } else if pack.state == .complete {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    .accessibilityLabel("Downloaded")
                            }
                        }
                        .buttonStyle(.borderless)
                        .swipeActions {
                            Button(role: .destructive) {
                                busy = true
                                storage.removePack(pack) { failure in
                                    busy = false
                                    if let failure {
                                        error = failure.localizedDescription
                                        storage.reloadPacks()
                                    }
                                }
                            } label: { Label("Remove", systemImage: "trash") }
                            .disabled(busy)
                        }
                    }
                } header: { Text("Downloads") }
                  footer: { Text("Downloaded regions are available for browsing offline.") }
                Section("Regions") {
                    ForEach(OfflineRegion.catalogue.filter {
                        !ids.contains($0.id) && (query.isEmpty || $0.name.localizedStandardContains(query))
                    }) { region in
                        Button {
                            busy = true
                            let zoom = region.maximumZoom
                            let definition = MLNTilePyramidOfflineRegion(styleURL: VelaMapView.styleURL, bounds: region.bounds,
                                                                         fromZoomLevel: min(7, zoom - 2), toZoomLevel: zoom)
                            storage.addPack(for: definition, withContext: Data(region.id.utf8)) { pack, failure in
                                busy = false
                                if let failure { error = failure.localizedDescription }
                                else { pack?.resume() }
                            }
                        } label: { Label(region.name, systemImage: "arrow.down.circle") }
                        .disabled(downloading || storage.packs == nil)
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("Offline maps")
        .task {
            while !Task.isCancelled, storage.packs == nil {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            if !Task.isCancelled { storage.packs?.forEach { $0.requestProgress() } }
        }
        .alert("Offline maps", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
}
