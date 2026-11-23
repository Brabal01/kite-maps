import SwiftUI

@MainActor
final class MapLayerInspection {
    struct Layer: Codable, Identifiable {
        let id: String
        let source: String
        let geometries: Int?
        let points: Int?
        let dataAt: Date?
        let hidden: Bool
    }

    var hidden: Set<String> = []
    var renderer = ""
    var layers: [String: Layer] = [:]
    /// The live-traffic overlay for the visible map (browse and route), from TrafficOverlayState.
    var trafficStatus: String?

    var orderedLayers: [Layer] { layers.values.sorted { $0.id < $1.id } }

    func export() -> String? {
        struct Report: Encodable {
            let renderer: String
            let layers: [Layer]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(Report(renderer: renderer, layers: orderedLayers)))
            .flatMap { String(data: $0, encoding: .utf8) }
    }
}

struct MapLayerInspectorPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let inspection = model.mapLayerInspection
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(inspection.renderer.isEmpty ? "Map Layer Inspector" : inspection.renderer)
                        .font(.headline).accessibilityIdentifier("layer-inspector-renderer")
                    Spacer()
                    if let report = inspection.export() {
                        ShareLink(item: report) {
                            Image(systemName: "square.and.arrow.up").padding(8)
                        }.accessibilityLabel("Share anonymous layer report")
                    }
                    Button {
                        model.setLayerInspection(false)
                    } label: {
                        Image(systemName: "xmark.circle.fill").padding(8)
                    }.accessibilityLabel("Close layer inspector")
                }
                #if targetEnvironment(simulator)
                if UITestSupport.mapLayers {
                    HStack {
                        Button("Switch renderer") { model.settings.useAppleMaps.toggle() }
                        Button(model.nav == nil ? "Start fixture" : "Stop fixture") {
                            if model.nav == nil { UITestSupport.startMapLayerDrive(model) }
                            else { model.endNavigation() }
                        }
                    }
                    .font(.caption).buttonStyle(.bordered)
                }
                #endif
                if let traffic = inspection.trafficStatus {
                    Text(traffic)
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(2)
                        .accessibilityIdentifier("layer-inspector-traffic")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(inspection.orderedLayers) { layer in
                            Button {
                                model.toggleInspectedLayer(layer.id)
                            } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: layer.hidden ? "eye.slash" : "eye")
                                    VStack(alignment: .leading) {
                                        Text(layer.id).font(.caption.monospaced())
                                        Text(layer.source).font(.caption2)
                                        if let count = layer.geometries, let points = layer.points {
                                            Text("\(count) geometries · \(points) points").font(.caption2)
                                        }
                                        if let date = layer.dataAt {
                                            Text(date.formatted(date: .omitted, time: .standard)).font(.caption2)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("inspected-\(layer.id)")
                            .accessibilityValue(layer.hidden ? "Hidden" : "Visible")
                        }
                    }
                }
                .frame(maxHeight: 170)
            }
            .padding(10)
            .frame(maxWidth: 325)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
