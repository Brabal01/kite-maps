import CoreGraphics
import ImageIO
import SwiftUI
import VelaCore

private enum ElevationSamples {
    struct Tile: Hashable, Sendable { let x: Int; let y: Int }
    struct Pixel: Sendable { let tile: Tile; let x: Int; let y: Int; let index: Int }

    static func sample(_ route: Route) async -> [Double]? {
        let line = route.polyline
        let cumulative = Geo.cumulative(line)
        guard line.count >= 2, let length = cumulative.last, length > 0 else { return nil }
        let zoom = length > 35_000 ? 10 : 12
        let world = 256 << zoom
        let count = Int(min(64, max(24, (length / 35).rounded())))
        let pixels = (0...count).map { index -> Pixel in
            let point = Geo.point(along: line, meters: length * Double(index) / Double(count), cumulative: cumulative)
            let lat = min(85.05112878, max(-85.05112878, point.lat)) * .pi / 180
            let x = (Int(floor((point.lng + 180) * Double(world) / 360)) % world + world) % world
            let y = min(world - 1, max(0, Int(floor((1 - asinh(tan(lat)) / .pi) * Double(world) / 2))))
            return Pixel(tile: Tile(x: x / 256, y: y / 256), x: x % 256, y: y % 256, index: index)
        }
        let groups = Array(Dictionary(grouping: pixels, by: \.tile))
        var result: [Int: Double] = [:]
        for i in stride(from: 0, to: groups.count, by: 4) {
            if Task.isCancelled { return nil }
            await withTaskGroup(of: [Int: Double].self) { tasks in
                for (tile, points) in groups[i..<min(groups.count, i + 4)] {
                    tasks.addTask { await elevations(of: tile, points: points, zoom: zoom) }
                }
                for await batch in tasks { result.merge(batch) { _, rhs in rhs } }
            }
        }
        guard result.count == pixels.count else { return nil }
        return (0...count).compactMap { i in
            guard let height = result[i] else { return nil }
            if let a = result[i - 1], let b = result[i + 1] { return (a + height * 2 + b) / 4 }
            return height
        }
    }

    private static func elevations(of tile: Tile, points: [Pixel], zoom: Int) async -> [Int: Double] {
        guard let url = URL(string: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/\(zoom)/\(tile.x)/\(tile.y).png"),
              let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [:] }
        return points.reduce(into: [:]) { output, point in
            guard let crop = image.cropping(to: CGRect(x: CGFloat(point.x), y: CGFloat(point.y), width: 1, height: 1)) else { return }
            var bytes = [UInt8](repeating: 0, count: 4)
            bytes.withUnsafeMutableBytes { memory in
                let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                let context = CGContext(data: memory.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)
                context?.setBlendMode(.copy)
                context?.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            output[point.index] = Double(bytes[0]) * 256 + Double(bytes[1]) + Double(bytes[2]) / 256 - 32768
        }
    }
}

@MainActor
final class RouteProfileCache {
    private var entries: [UUID: Task<Profile, Never>] = [:]
    struct Profile: Sendable {
        let elevation: [Double]?
        let surfaces: [Valhalla.SurfaceSection]
    }

    func load(_ route: Route) -> Task<Profile, Never> {
        if let match = entries[route.id] { return match }
        if entries.count >= 4, let key = entries.keys.first { entries.removeValue(forKey: key)?.cancel() }
        let task = Task {
            async let samples = ElevationSamples.sample(route)
            async let surfaces = Valhalla.surfaces(on: route)
            return await Profile(elevation: samples, surfaces: surfaces)
        }
        entries[route.id] = task
        return task
    }
}

struct RouteProfileView: View {
    @ObservedObject var model: AppModel
    let route: Route
    @State private var profile: RouteProfileCache.Profile?
    @State private var cursor: Double?
    @Environment(\.dismiss) private var dismiss

    private var total: Double { Geo.length(route.polyline) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if let profile {
                        if let values = profile.elevation, values.count > 1 { chart(values) }
                        else { Text("Elevation data is unavailable.").foregroundStyle(.secondary) }
                        Text("Road surface").font(.headline)
                        if profile.surfaces.isEmpty { Text("No matched OpenStreetMap surface data.").foregroundStyle(.secondary) }
                        ForEach(profile.surfaces) { section in
                            Button {
                                model.inspectProfileSection(route, from: section.from, to: section.to)
                            } label: {
                                HStack {
                                    Text(section.surface)
                                    Spacer()
                                    Text(Fmt.distance(section.to - section.from)).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.bordered)
                        }
                    } else { ProgressView("Loading the route profile…") }
                }.padding(16)
            }
            .navigationTitle("Route profile").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .modifier(ProfileMapInteraction())
        .task(id: route.id) { profile = await model.routeProfiles.load(route).value }
    }

    private func chart(_ values: [Double]) -> some View {
        let low = values.min() ?? 0
        let high = max(low + 1, values.max() ?? 1)
        let deltas = zip(values, values.dropFirst()).map { pair in pair.1 - pair.0 }.filter { abs($0) > 2 }
        let up = deltas.filter { $0 > 0 }.reduce(0, +), down = -deltas.filter { $0 < 0 }.reduce(0, +)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("\(Int(up)) m", systemImage: "arrow.up.right")
                Label("\(Int(down)) m", systemImage: "arrow.down.right")
                Spacer()
                if let cursor {
                    let index = Int((cursor * Double(values.count - 1)).rounded())
                    Text("\(Int(values[index])) m · \(Fmt.distance(total * cursor))")
                }
            }.font(.subheadline.monospacedDigit())
            GeometryReader { geo in
                Canvas { context, size in
                    let points = values.enumerated().map { index, value in
                        CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                                y: size.height * (1 - CGFloat((value - low) / (high - low))))
                    }
                    var stroke = Path()
                    stroke.addLines(points)
                    var fill = stroke
                    fill.addLine(to: CGPoint(x: size.width, y: size.height))
                    fill.addLine(to: CGPoint(x: 0, y: size.height))
                    fill.closeSubpath()
                    context.fill(fill, with: .linearGradient(Gradient(colors: [.teal.opacity(0.35), .teal.opacity(0.03)]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    context.stroke(stroke, with: .color(.teal), lineWidth: 3)
                    if let cursor {
                        let at = points[Int((cursor * Double(points.count - 1)).rounded())]
                        context.fill(Path(ellipseIn: CGRect(x: at.x - 4, y: at.y - 4, width: 8, height: 8)), with: .color(.orange))
                    }
                }.padding(.vertical, 7).contentShape(Rectangle()).gesture(
                    DragGesture(minimumDistance: 0).onChanged {
                        let fraction = Double(min(1, max(0, $0.location.x / max(1, geo.size.width))))
                        cursor = fraction
                        model.profileProbe = Geo.point(along: route.polyline, meters: total * fraction)
                    }
                )
            }.frame(height: 110)
        }
    }
}

private struct ProfileMapInteraction: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackgroundInteraction(.enabled(upThrough: .medium))
        } else {
            content
        }
    }
}
