import MapKit
import MapLibre
import SwiftUI
import VelaCore

/**
 * The first tile of a place's photos, like Google Maps: Google Street View looking at the place,
 * or Apple's Look Around where Google has none. Tapping it opens the panorama full screen.
 */
struct StreetViewTile: View {
    let place: Place
    var height: CGFloat = 140
    @ObservedObject private var settings = AppSettings.shared

    private enum Found {
        case google(StreetView.Panorama, heading: Double)
        case apple(MKLookAroundScene, UIImage?)
    }

    @State private var found: Found?
    @State private var loaded = false
    @State private var open = false

    var body: some View {
        Group {
            if let found {
                Button { open = true } label: { tile(found) }
                    .buttonStyle(.plain)
                    .transition(.opacity)
            } else if !loaded {
                RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.15))
                    .frame(width: height * 1.4, height: height)
            }
        }
        .task(id: "\(place.id)|\(settings.noGoogle)") { await load() }
        .fullScreenCover(isPresented: $open) {
            switch found {
            case let .google(pano, heading)?: GoogleStreetViewScreen(name: place.name, pano: pano, heading: heading)
            case let .apple(scene, _)?: LookAroundScreen(name: place.name, scene: scene)
            case nil: EmptyView()
            }
        }
    }

    @ViewBuilder
    private func tile(_ f: Found) -> some View {
        ZStack(alignment: .bottomLeading) {
            switch f {
            case let .google(pano, heading):
                AsyncImage(url: StreetView.thumbnailURL(pano, heading: heading)) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() } else { Color.secondary.opacity(0.15) }
                }
            case let .apple(_, image):
                if let image { Image(uiImage: image).resizable().scaledToFill() } else { Color.secondary.opacity(0.15) }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            Label(isGoogle(f) ? "Street View" : "Look Around", systemImage: isGoogle(f) ? "rotate.3d" : "binoculars.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(8)
        }
        .frame(width: height * 1.4, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private func isGoogle(_ f: Found) -> Bool {
        if case .google = f { return true }
        return false
    }

    private func load() async {
        found = nil
        loaded = false
        defer { if !Task.isCancelled { loaded = true } }
        // Google first (the screenshot run can skip it to show Apple's), then Apple.
        if DemoScript.step != "lookaround", !settings.noGoogle,
           let pano = await StreetView.find(near: place.location), !Task.isCancelled, !settings.noGoogle {
            withAnimation { found = .google(pano, heading: Geo.bearing(pano.location, place.location)) }
            if DemoScript.step == "streetview" { open = true }
            return
        }
        let coord = CLLocationCoordinate2D(latitude: place.location.lat, longitude: place.location.lng)
        guard !Task.isCancelled, let scene = try? await MKLookAroundSceneRequest(coordinate: coord).scene else { return }
        let options = MKLookAroundSnapshotter.Options()
        options.size = CGSize(width: height * 1.4 * 2, height: height * 2)
        let image = try? await MKLookAroundSnapshotter(scene: scene, options: options).snapshot.image
        guard !Task.isCancelled else { return }
        withAnimation { found = .apple(scene, image) }
    }
}

struct GoogleStreetViewScreen: View {
    private struct Move: Equatable {
        private let requestID = UUID()
        let location: LatLng
        var panoramaID: String?
    }

    let name: String
    @State private var pano: StreetView.Panorama
    @State private var startingHeading: Double
    @State private var heading: Double
    @State private var move: Move?
    @State private var expanded = false
    @State private var status: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    init(name: String, pano: StreetView.Panorama, heading: Double) {
        self.name = name
        _pano = State(initialValue: pano)
        _startingHeading = State(initialValue: heading)
        _heading = State(initialValue: heading)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()
                PanoramaViewer(pano: pano, heading: startingHeading) { heading = $0 }
                    .id(pano.id).ignoresSafeArea()
                PanoramaBar(name: name, source: "Street View") { dismiss() }
                VStack(alignment: .trailing, spacing: 8) {
                    Spacer()
                    if let status {
                        Text(status).font(.footnote.weight(.semibold))
                            .padding(9).background(.regularMaterial, in: Capsule())
                    }
                    PanoramaMiniMap(pano: pano, heading: heading, dark: scheme == .dark) { move = Move(location: $0) }
                        .frame(maxWidth: expanded ? .infinity : 200)
                        .frame(height: expanded ? min(geometry.size.height * 0.55, 460) : 150)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                            } label: {
                                Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                    .padding(10).background(.regularMaterial, in: Circle())
                            }.accessibilityLabel(expanded ? "Shrink street map" : "Expand street map").padding(7)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    HStack(spacing: 8) {
                        Button {
                            step(bearing: heading + 180)
                        } label: {
                            Label("Back", systemImage: "arrow.down")
                        }
                        Button {
                            step(bearing: heading)
                        } label: {
                            Label("Forward", systemImage: "arrow.up")
                        }
                    }.buttonStyle(.borderedProminent).tint(.teal)
                    if let credit = pano.credit {
                        Text(credit).font(.caption2).foregroundStyle(.white)
                            .padding(4).background(Color.black.opacity(0.65), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(12)
            }
        }
        .task(id: move) {
            guard let move else { return }
            status = "Looking for Street View…"
            var match: StreetView.Panorama?
            if let id = move.panoramaID { match = await StreetView.panorama(id: id) }
            if match == nil, !Task.isCancelled { match = await StreetView.find(near: move.location, radius: 25) }
            guard !Task.isCancelled else { return }
            if let match, match.id != pano.id {
                startingHeading = heading
                pano = match
                status = nil
            } else {
                status = "No other panorama here"
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { status = nil }
            }
        }
    }

    private func step(bearing: Double) {
        if let link = pano.step(facing: bearing) {
            move = Move(location: link.location, panoramaID: link.id)
        } else {
            move = Move(location: Geo.destination(pano.location, bearing: bearing, meters: 23))
        }
    }
}

private struct PanoramaMiniMap: UIViewRepresentable {
    let pano: StreetView.Panorama
    let heading: Double
    let dark: Bool
    let onPick: (LatLng) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: VelaMapView.styleURL)
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.compassView.isHidden = true
        map.attributionButtonPosition = .bottomLeft
        map.setCenter(coordinate, zoomLevel: 17, animated: false)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        for gesture in map.gestureRecognizers ?? [] {
            if let doubleTap = gesture as? UITapGestureRecognizer, doubleTap.numberOfTapsRequired == 2 {
                tap.require(toFail: doubleTap)
            }
        }
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        let changedLocation = coordinator.owner.pano.id != pano.id
        coordinator.owner = self
        if changedLocation { map.setCenter(coordinate, zoomLevel: map.zoomLevel, animated: true) }
        if let style = map.style { coordinator.updatePin(style) }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: pano.location.lat, longitude: pano.location.lng)
    }

    @MainActor
    final class Coordinator: NSObject, MLNMapViewDelegate {
        var owner: PanoramaMiniMap
        init(owner: PanoramaMiniMap) { self.owner = owner }

        nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            MainActor.assumeIsolated {
                MapStyler.apply(style, dark: owner.dark)
                style.setImage(MapIcons.puck(dark: owner.dark), forName: "panorama-heading")
                let source = MLNShapeSource(identifier: "panorama-position", shape: nil, options: nil)
                style.addSource(source)
                let arrow = MLNSymbolStyleLayer(identifier: "panorama-arrow", source: source)
                arrow.iconImageName = NSExpression(forConstantValue: "panorama-heading")
                arrow.iconRotation = NSExpression(forKeyPath: "bearing")
                arrow.iconAllowsOverlap = NSExpression(forConstantValue: true)
                arrow.iconRotationAlignment = NSExpression(forConstantValue: "map")
                style.addLayer(arrow)
                updatePin(style)
            }
        }

        func updatePin(_ style: MLNStyle) {
            let arrow = MLNPointFeature()
            arrow.coordinate = owner.coordinate
            arrow.attributes = ["bearing": owner.heading]
            (style.source(withIdentifier: "panorama-position") as? MLNShapeSource)?.shape = arrow
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MLNMapView else { return }
            let at = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            owner.onPick(LatLng(at.latitude, at.longitude))
        }
    }
}

/** Apple's Look Around, full screen. */
struct LookAroundScreen: View {
    let name: String
    let scene: MKLookAroundScene
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            LookAroundView(scene: scene).ignoresSafeArea()
            PanoramaBar(name: name, source: "Look Around") { dismiss() }
        }
    }
}

/** The close button and the place's name over a panorama. */
struct PanoramaBar: View {
    let name: String
    let source: String
    let close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: close) {
                Image(systemName: "arrow.left").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                    .frame(width: 40, height: 40).background(Circle().fill(Color.black.opacity(0.55)))
            }
            .accessibilityLabel("Close")
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(source).font(.caption).opacity(0.8)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.55)))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

struct LookAroundView: UIViewControllerRepresentable {
    let scene: MKLookAroundScene

    func makeUIViewController(context: Context) -> MKLookAroundViewController {
        let vc = MKLookAroundViewController(scene: scene)
        vc.showsRoadLabels = true
        return vc
    }

    func updateUIViewController(_ vc: MKLookAroundViewController, context: Context) {}
}
