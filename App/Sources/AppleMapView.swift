import MapKit
import MapLibre
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import VelaCore

struct KiteAppleMapView: UIViewRepresentable {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let dark: Bool

    func makeCoordinator() -> VelaMapView.Coordinator { .init(model: model) }

    func makeUIView(context: Context) -> AppleMapSurface {
        let surface = AppleMapSurface(coordinator: context.coordinator)
        let coordinator = context.coordinator
        coordinator.dark = dark
        coordinator.surface = surface
        coordinator.movedToUser = model.attachMap(surface)
        WazeHistory.shared.onChange = { [weak coordinator, weak surface] in
            if let surface { coordinator?.render(surface) }
        }
        LiveCamStore.shared.onChange = { [weak coordinator, weak surface] in
            if let surface { coordinator?.render(surface) }
        }
        if (settings.welcomed && !settings.needsWazeChoice) || DemoScript.active { model.location.start() }
        return surface
    }

    func updateUIView(_ surface: AppleMapSurface, context: Context) {
        let coordinator = context.coordinator
        coordinator.dark = dark
        coordinator.render(surface)
        if let location = model.location.last { coordinator.firstUserLocation(location, on: surface) }
    }

    static func dismantleUIView(_ surface: AppleMapSurface, coordinator: VelaMapView.Coordinator) {
        coordinator.model.detachMap(surface)
    }
}

@MainActor
final class AppleMapSurface: UIView, KiteMapSurface, MKMapViewDelegate, UIGestureRecognizerDelegate {
    private let native = MKMapView()
    private weak var coordinator: VelaMapView.Coordinator?
    private var pendingCamera: MLNMapCamera?
    private var regionUpdate: Task<Void, Never>?
    private var pins: [String: [FeaturePin]] = [:]
    private var lines: [String: [MKPolyline]] = [:]
    private var paints: [ObjectIdentifier: LinePaint] = [:]
    private var railGeometry: [MLNPolylineFeature] = []
    private var showsRail = false
    private var heatLayer: AppleHeatTiles?
    private var puck: FeaturePin?
    private var puckBearing: Double = 0
    private var arrowScale = 1.0
    private var dark = false
    private var navigating = false
    private var satellite: Bool?
    private var terrain = false
    private var showsNativeTraffic: Bool?
    private var showsNativePOI: Bool?
    private var showsNativeBuildings: Bool?
    private var pendingRouteFit: (rect: MKMapRect, padding: UIEdgeInsets)?
    private var measurementPoints: [MKPointAnnotation] = []
    private var measurementLine: MKGeodesicPolyline?
    private var measurementLabel: MKPointAnnotation?
    private var choosingMeasurementEndpoint = false
    private weak var measureGesture: UILongPressGestureRecognizer?
    private static let images: [String: UIImage] = {
        var result: [String: UIImage] = [:]
        MapIcons.registerImages { result[$1] = $0 }
        return result
    }()
    private static let lightPuck = MapIcons.puck(dark: false)
    private static let start = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)

    init(coordinator: VelaMapView.Coordinator) {
        LaunchTrace.mark("MapKit makeUIView")
        self.coordinator = coordinator
        super.init(frame: .zero)
        addSubview(native)
        native.frame = bounds
        native.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        native.showsCompass = false
        if #available(iOS 17.0, *) {
            native.traitOverrides.preferredContentSizeCategory = .medium
        }
        native.layoutMargins.bottom = 108
        let start = coordinator.model.mapStart
        setCenter(start.center, zoomLevel: start.zoom, animated: false)
        native.selectableMapFeatures = [.pointsOfInterest, .physicalFeatures, .territories]
        native.delegate = self

        // Observe the touch itself. MapKit's region callback can arrive before its pinch
        // recognizer becomes active, while the navigation display link is still moving the camera.
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delegate = self
        native.addGestureRecognizer(pinch)

        let measure = UILongPressGestureRecognizer(target: self, action: #selector(measureHeld(_:)))
        measure.numberOfTouchesRequired = 2
        measure.minimumPressDuration = 0.35
        measure.allowableMovement = 12
        measure.delegate = self
        native.addGestureRecognizer(measure)
        measureGesture = measure

        let measureTap = MapMeasurementTap(target: self, action: #selector(measureTapped(_:)))
        measureTap.delegate = self
        native.addGestureRecognizer(measureTap)
        for case let tap as UITapGestureRecognizer in allGestures(in: native) where tap.numberOfTouchesRequired == 2 {
            tap.require(toFail: measureTap)
        }

        let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        for gesture in allGestures(in: native) {
            if let doubleTap = gesture as? UITapGestureRecognizer, doubleTap.numberOfTapsRequired > 1 {
                tap.require(toFail: doubleTap)
            }
        }
        tap.require(toFail: press)
        tap.delegate = self
        press.delegate = self
        native.addGestureRecognizer(press)
        native.addGestureRecognizer(tap)

        if let camera = pendingCamera {
            camera.pitch = coordinator.model.browsePitch
            pendingCamera = camera
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let fit = pendingRouteFit, bounds.width > 0, bounds.height > 0 {
            pendingRouteFit = nil
            fitRoute(in: fit.rect, padding: fit.padding)
        } else if let pending = pendingCamera, bounds.width > 0, bounds.height > 0 {
            pendingCamera = nil
            camera = pending
            queueRegionUpdate()
        }
    }

    var mapView: UIView { self }
    var centerCoordinate: CLLocationCoordinate2D { pendingCamera?.centerCoordinate ?? native.centerCoordinate }
    var direction: CLLocationDirection { pendingCamera?.heading ?? native.camera.heading }
    var locationCoordinate: CLLocationCoordinate2D? { native.userLocation.location?.coordinate }
    var showsUserLocation: Bool {
        get { native.showsUserLocation }
        set { native.showsUserLocation = newValue }
    }

    var visibleCoordinateBounds: MLNCoordinateBounds {
        let region = native.region
        let half = region.span.longitudeDelta / 2
        return MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: max(-85.05, region.center.latitude - region.span.latitudeDelta / 2),
                                       longitude: max(-180, region.center.longitude - half)),
            ne: CLLocationCoordinate2D(latitude: min(85.05, region.center.latitude + region.span.latitudeDelta / 2),
                                       longitude: min(180, region.center.longitude + half))
        )
    }

    var zoomLevel: Double {
        let span = native.region.span.longitudeDelta
        guard span > 0, bounds.width > 0 else { return 12 }
        return min(22, max(0, log2(360 / span * Double(bounds.width) / 512)))
    }

    var camera: MLNMapCamera {
        get {
            if let pendingCamera { return pendingCamera }
            let current = native.camera
            return MLNMapCamera(lookingAtCenter: current.centerCoordinate, altitude: current.altitude,
                                pitch: current.pitch, heading: current.heading)
        }
        set {
            setCamera(newValue, withDuration: 0, animationTimingFunction: nil,
                      edgePadding: .zero, completionHandler: nil)
        }
    }

    func setCenter(_ coordinate: CLLocationCoordinate2D, zoomLevel: Double, animated: Bool) {
        let width = MKMapRect.world.size.width * Double(max(bounds.width, 320)) / (512 * pow(2, zoomLevel))
        let altitude = altitudeForWidth(width, latitude: coordinate.latitude)
        let next = MLNMapCamera(lookingAtCenter: coordinate, altitude: altitude, pitch: camera.pitch, heading: direction)
        setCamera(next, withDuration: animated ? 0.35 : 0, animationTimingFunction: nil)
    }

    func setDirection(_ heading: CLLocationDirection, animated: Bool) {
        let next = camera
        next.heading = heading
        setCamera(next, withDuration: animated ? 0.35 : 0, animationTimingFunction: nil)
    }

    func cameraThatFitsCoordinateBounds(_ bounds: MLNCoordinateBounds, edgePadding: UIEdgeInsets) -> MLNMapCamera {
        let sw = MKMapPoint(bounds.sw), ne = MKMapPoint(bounds.ne)
        let rect = MKMapRect(x: min(sw.x, ne.x), y: min(sw.y, ne.y),
                             width: max(1, abs(ne.x - sw.x)), height: max(1, abs(ne.y - sw.y)))
        let fitted = native.mapRectThatFits(rect, edgePadding: edgePadding)
        let center = MKMapPoint(x: fitted.midX, y: fitted.midY).coordinate
        return MLNMapCamera(lookingAtCenter: center, altitude: altitudeForWidth(fitted.width, latitude: center.latitude),
                            pitch: 0, heading: 0)
    }

    private func altitudeForWidth(_ width: Double, latitude: Double) -> Double {
        let scale = MKMetersPerMapPointAtLatitude(latitude)
        return max(20, width * scale * Double(max(bounds.height, 320) / max(bounds.width, 320)) * 1.15)
    }

    func frameRoute(_ bounds: MLNCoordinateBounds, padding: UIEdgeInsets) {
        let sw = MKMapPoint(bounds.sw), ne = MKMapPoint(bounds.ne)
        let rect = MKMapRect(x: min(sw.x, ne.x), y: min(sw.y, ne.y),
                             width: max(1, abs(ne.x - sw.x)), height: max(1, abs(ne.y - sw.y)))
        pendingCamera = nil
        guard native.bounds.width > 0, native.bounds.height > 0 else {
            pendingRouteFit = (rect, padding)
            return
        }
        pendingRouteFit = nil
        fitRoute(in: rect, padding: padding)
    }

    private func fitRoute(in rect: MKMapRect, padding: UIEdgeInsets) {
        let maxTop = max(0, native.bounds.height - padding.bottom - 44)
        let maxLeft = max(0, native.bounds.width - padding.right - 44)
        let insets = UIEdgeInsets(top: min(padding.top, maxTop), left: min(padding.left, maxLeft),
                                 bottom: padding.bottom, right: padding.right)
        let camera = native.camera
        camera.heading = 0
        camera.pitch = 0
        native.setCamera(camera, animated: false)
        native.setVisibleMapRect(rect, edgePadding: insets, animated: true)
    }

    func setCamera(_ camera: MLNMapCamera, withDuration duration: TimeInterval,
                   animationTimingFunction: CAMediaTimingFunction?, edgePadding: UIEdgeInsets,
                   completionHandler: (() -> Void)?) {
        pendingRouteFit = nil
        guard bounds.width > 0, bounds.height > 0 else {
            pendingCamera = camera
            completionHandler?()
            return
        }
        var center = camera.centerCoordinate
        let angle = camera.heading * .pi / 180
        let metersPerPoint = camera.altitude / (Double(bounds.height) * 1.15)
        let mapPointsPerPoint = metersPerPoint * MKMapPointsPerMeterAtLatitude(center.latitude)
        // Move the camera away from the focus so the route stays visible around Kite's controls.
        let east = Double(edgePadding.right - edgePadding.left) * 0.5 * mapPointsPerPoint
        let south = Double(edgePadding.bottom - edgePadding.top) * 0.5 * mapPointsPerPoint
        if east != 0 || south != 0 {
            let point = MKMapPoint(center)
            let x = point.x + east * cos(angle) - south * sin(angle)
            let y = point.y + east * sin(angle) + south * cos(angle)
            let world = MKMapRect.world.size
            let wrappedX = (x.truncatingRemainder(dividingBy: world.width) + world.width)
                .truncatingRemainder(dividingBy: world.width)
            center = MKMapPoint(x: wrappedX, y: min(world.height, max(0, y))).coordinate
        }
        let next = MKMapCamera()
        next.centerCoordinate = center
        next.pitch = camera.pitch
        next.heading = camera.heading
        next.altitude = max(20, camera.altitude)
        native.setCamera(next, animated: duration > 0)
        updateBearingViews(heading: native.camera.heading)
        completionHandler?()
    }

    func apply(settings: AppSettings, dark: Bool, navigating: Bool, showsRail: Bool) {
        let oldDark = self.dark
        let oldNavigating = self.navigating
        self.dark = dark
        self.navigating = navigating
        let interfaceStyle: UIUserInterfaceStyle = dark ? .dark : .light
        if overrideUserInterfaceStyle != interfaceStyle { overrideUserInterfaceStyle = interfaceStyle }
        let preset: MapPreset = navigating && settings.mapPreset != .minimal ? .navigation : settings.mapPreset
        let profile = MapPresetCatalog.profile(for: preset)
        let showTraffic = settings.traffic
        let hasAppleSearchPins = coordinator?.model.results.contains { $0.source == "apple" } == true
        let showsPOI = profile.showPOI && settings.showApplePOI && !hasAppleSearchPins
        let showBuildings = !settings.satellite && profile.showBuildings && (!navigating || settings.navBuildings)
        if showsNativeBuildings != showBuildings {
            native.showsBuildings = showBuildings
            showsNativeBuildings = showBuildings
        }

        let configuredTraffic = (native.preferredConfiguration as? MKStandardMapConfiguration)?.showsTraffic
            ?? (native.preferredConfiguration as? MKHybridMapConfiguration)?.showsTraffic
        if satellite != settings.satellite || terrain != settings.terrain || showsNativeTraffic != showTraffic
            || showsNativePOI != showsPOI || configuredTraffic != showTraffic {
            satellite = settings.satellite
            terrain = settings.terrain
            showsNativeTraffic = showTraffic
            showsNativePOI = showsPOI
            let poiFilter: MKPointOfInterestFilter = showsPOI ? .includingAll : .excludingAll
            let elevation: MKMapConfiguration.ElevationStyle = terrain ? .realistic : .flat
            if settings.satellite {
                let config = MKHybridMapConfiguration(elevationStyle: elevation)
                config.showsTraffic = showTraffic
                config.pointOfInterestFilter = poiFilter
                native.preferredConfiguration = config
            } else {
                let config = MKStandardMapConfiguration(elevationStyle: elevation, emphasisStyle: .default)
                config.showsTraffic = showTraffic
                config.pointOfInterestFilter = poiFilter
                native.preferredConfiguration = config
            }
        }
        native.selectableMapFeatures = showsPOI ? [.pointsOfInterest, .physicalFeatures, .territories] : [.physicalFeatures, .territories]
        let showHeat = settings.wazeOn && settings.wazeHeatmap && settings.wazePolice
        if showHeat && heatLayer == nil {
            let layer = AppleHeatTiles()
            heatLayer = layer
            if let first = native.overlays(in: .aboveRoads).first {
                native.insertOverlay(layer, below: first)
            } else {
                native.addOverlay(layer, level: .aboveRoads)
            }
        } else if !showHeat, let heatLayer {
            native.removeOverlay(heatLayer)
            self.heatLayer = nil
        }
        if showsRail != self.showsRail {
            self.showsRail = showsRail
            replaceLines(showsRail ? railGeometry : [], source: "vela-rail")
        }
        if oldDark != dark || oldNavigating != navigating { refreshLineColors() }
        if settings.navArrowScale != arrowScale || oldDark != dark {
            arrowScale = settings.navArrowScale
            if let puck, let view = native.view(for: puck) { configure(view, for: puck) }
        }
    }

    private final class FeaturePin: NSObject, MKAnnotation {
        @objc dynamic var coordinate: CLLocationCoordinate2D
        let feature: MLNPointFeature
        let source: String
        init(_ feature: MLNPointFeature, source: String) {
            self.feature = feature
            self.source = source
            coordinate = feature.coordinate
        }
    }

    private struct LinePaint {
        let source: String
        let color: UInt32?
        let traffic: Int
        let walking: Bool
        let phase: String?
        let rank: Int
    }

    private static let lineRank = ["vela-route-done", "vela-route-alt", "vela-route", "vela-transit",
                                   "vela-route-traffic", "vela-rail", "vela-turn-arrow"]

    func replaceFeatures(_ shape: MLNShape?, source: String) {
        let shapes: [MLNShape]
        if let collection = shape as? MLNShapeCollectionFeature {
            shapes = collection.shapes.map { $0 }
        } else {
            shapes = shape.map { [$0] } ?? []
        }
        let geometry = shapes.compactMap { $0 as? MLNPolylineFeature }
        if source == "vela-rail" { railGeometry = geometry }
        replaceLines(source == "vela-rail" && !showsRail ? [] : geometry, source: source)
        let old = pins.removeValue(forKey: source) ?? []
        if !old.isEmpty { native.removeAnnotations(old) }
        let next = shapes.compactMap { ($0 as? MLNPointFeature).map { FeaturePin($0, source: source) } }
        if !next.isEmpty {
            pins[source] = next
            native.addAnnotations(next)
        }
    }

    private func replaceLines(_ geometry: [MLNPolylineFeature], source: String) {
        guard let rank = Self.lineRank.firstIndex(of: source) else { return }
        if let old = lines.removeValue(forKey: source) {
            native.removeOverlays(old)
            for line in old { paints.removeValue(forKey: ObjectIdentifier(line)) }
        }
        guard !geometry.isEmpty else { return }
        let upper = native.overlays(in: .aboveRoads).first { paints[ObjectIdentifier($0)]?.rank ?? -1 > rank }
        var rendered: [MKPolyline] = []
        for feature in geometry where feature.pointCount >= 2 {
            let line = MKPolyline(coordinates: feature.coordinates, count: Int(feature.pointCount))
            let attr = feature.attributes
            let color = (attr["color"] as? String).flatMap { UInt32($0.dropFirst(), radix: 16) }
            paints[ObjectIdentifier(line)] = LinePaint(source: source, color: color, traffic: attr["level"] as? Int ?? 0,
                                                       walking: (attr["walk"] as? Int) == 1,
                                                       phase: attr["phase"] as? String, rank: rank)
            if let upper { native.insertOverlay(line, below: upper) }
            else { native.addOverlay(line, level: .aboveRoads) }
            rendered.append(line)
        }
        lines[source] = rendered
    }

    private func refreshLineColors() {
        for line in lines.values.joined() {
            guard let renderer = native.renderer(for: line) as? MKPolylineRenderer,
                  let paint = paints[ObjectIdentifier(line)] else { continue }
            style(renderer, with: paint)
            renderer.setNeedsDisplay()
        }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
        if let measure = overlay as? MKGeodesicPolyline, measure === measurementLine {
            let renderer = MKPolylineRenderer(polyline: measure)
            renderer.strokeColor = UIColor.systemTeal
            renderer.lineWidth = 4
            renderer.lineDashPattern = [6, 4]
            return renderer
        }
        if let tile = overlay as? AppleHeatTiles { return MKTileOverlayRenderer(tileOverlay: tile) }
        guard let line = overlay as? MKPolyline, let paint = paints[ObjectIdentifier(line)] else {
            return MKOverlayRenderer(overlay: overlay)
        }
        let renderer = MKPolylineRenderer(polyline: line)
        style(renderer, with: paint)
        return renderer
    }

    private func style(_ renderer: MKPolylineRenderer, with paint: LinePaint) {
        renderer.lineJoin = .round
        renderer.lineCap = .round
        switch paint.source {
        case "vela-route-alt":
            renderer.strokeColor = UIColor(hex: dark ? 0x94A3B8 : 0x64748B)
            renderer.lineWidth = 6
        case "vela-route-done":
            renderer.strokeColor = UIColor(hex: 0x64748B).withAlphaComponent(0.55)
            renderer.lineWidth = 9
        case "vela-route":
            renderer.strokeColor = UIColor(hex: dark ? 0x409CFF : 0x007AFF)
            renderer.lineWidth = navigating ? 13 : 10
        case "vela-transit":
            let alpha: CGFloat = paint.phase == "done" ? 0.28 : paint.phase == "upcoming" ? 0.60 : 1
            renderer.strokeColor = UIColor(hex: paint.walking ? 0x5F6368 : paint.color ?? 0x1F6FEB).withAlphaComponent(alpha)
            renderer.lineWidth = paint.walking ? 4 : paint.phase == "active" ? 9 : paint.phase == "done" ? 5 : 7
            renderer.lineDashPattern = paint.walking ? [1, 7] : nil
        case "vela-route-traffic":
            renderer.strokeColor = UIColor(hex: paint.traffic >= 3 ? 0xB91C1C : paint.traffic == 2 ? 0xEF4444 : 0xF59E0B)
            renderer.lineWidth = 4
        case "vela-rail":
            renderer.strokeColor = UIColor(hex: paint.color ?? 0x64748B)
            renderer.lineWidth = 3
        case "vela-turn-arrow":
            renderer.strokeColor = .white
            renderer.lineWidth = 6
        default: break
        }
    }

    func drawPuck(at coordinate: CLLocationCoordinate2D?, bearing: Double) {
        guard let coordinate else {
            if let puck { native.removeAnnotation(puck) }
            puck = nil
            return
        }
        puckBearing = bearing
        if let puck {
            puck.coordinate = coordinate
            if let view = native.view(for: puck) { rotate(view, bearing: bearing, heading: direction, scale: arrowScale) }
        } else {
            let point = MLNPointFeature()
            point.coordinate = coordinate
            point.attributes = ["icon": "puck"]
            let pin = FeaturePin(point, source: "vela-puck")
            puck = pin
            native.addAnnotation(pin)
        }
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        if let point = annotation as? MKPointAnnotation {
            if point === measurementLabel {
                let view = MKAnnotationView(annotation: point, reuseIdentifier: nil)
                let label = point.title ?? ""
                view.image = pill(label, background: UIColor(hex: 0x0F172A), foreground: .white)
                view.accessibilityLabel = label
                view.displayPriority = .required
                return view
            }
            if measurementPoints.contains(where: { $0 === point }) {
                let view = MKMarkerAnnotationView(annotation: point, reuseIdentifier: nil)
                view.glyphText = point.title
                view.markerTintColor = .systemTeal
                view.isDraggable = true
                view.displayPriority = .required
                return view
            }
        }
        if let cluster = annotation as? MKClusterAnnotation {
            let view = MKAnnotationView(annotation: cluster, reuseIdentifier: nil)
            view.image = pill(String(cluster.memberAnnotations.count), background: UIColor(hex: 0x0F172A), foreground: .white)
            return view
        }
        // Kite draws the teal heading arrow itself; hide MapKit's default blue dot.
        if annotation is MKUserLocation {
            let view = MKAnnotationView(annotation: annotation, reuseIdentifier: "kite-hidden-user")
            view.isHidden = true
            view.alpha = 0
            return view
        }
        guard let pin = annotation as? FeaturePin else { return nil }
        let view = MKAnnotationView(annotation: pin, reuseIdentifier: nil)
        configure(view, for: pin)
        return view
    }

    private func configure(_ view: MKAnnotationView, for pin: FeaturePin) {
        let attrs = pin.feature.attributes
        let label = attrs["label"] as? String ?? ""
        let icon = attrs["icon"] as? String ?? (pin.source == "vela-turn-arrow" ? "turn-head" : "")
        view.displayPriority = .required
        view.accessibilityLabel = label.isEmpty ? nil : label
        view.alpha = CGFloat(attrs["op"] as? Double ?? 1)
        view.canShowCallout = false
        view.centerOffset = .zero
        view.transform = .identity

        switch pin.source {
        case "vela-route-bubbles":
            let selected = (attrs["sel"] as? Int) == 1
            view.image = pill(label, background: selected ? UIColor(hex: 0x005BC5) : .white,
                              foreground: selected ? .white : UIColor(hex: 0x202124))
        case "vela-next-road":
            view.image = pill(label, background: UIColor(hex: 0xB8DBFF), foreground: UIColor(hex: 0x092853))
        case "vela-puck":
            view.image = dark ? Self.images["puck"] : Self.lightPuck
            view.isUserInteractionEnabled = false
            rotate(view, bearing: puckBearing, heading: direction, scale: arrowScale)
        default:
            view.image = Self.images[icon]
            if let image = view.image, !label.isEmpty {
                view.image = labeled(image, label: label)
            }
            if (attrs["anchor"] as? String) == "bottom" || pin.source == "vela-signals" {
                view.centerOffset.y = -(Self.images[icon]?.size.height ?? 0) / 2
            }
            if let bearing = attrs["bearing"] as? Double {
                rotate(view, bearing: bearing, heading: direction, scale: 0.65)
            }
            if (pin.source == "vela-waze-group" || pin.source == "vela-livecams"
                || (pin.source == "vela-cameras" && (attrs["big"] as? Int) != 1)) && zoomLevel < 14 {
                view.clusteringIdentifier = pin.source
                view.displayPriority = .defaultHigh
            }
        }
    }

    private func rotate(_ view: MKAnnotationView, bearing: Double, heading: Double, scale: Double) {
        view.transform = CGAffineTransform(rotationAngle: CGFloat((bearing - heading) * .pi / 180))
            .scaledBy(x: scale, y: scale)
    }

    private func updateBearingViews(heading: Double) {
        if let puck, let view = native.view(for: puck) { rotate(view, bearing: puckBearing, heading: heading, scale: arrowScale) }
        for pin in pins["vela-turn-arrow"] ?? [] {
            if let view = native.view(for: pin), let bearing = pin.feature.attributes["bearing"] as? Double {
                rotate(view, bearing: bearing, heading: heading, scale: 0.65)
            }
        }
    }

    private func pill(_ text: String, background: UIColor, foreground: UIColor) -> UIImage {
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: foreground]
        let label = text as NSString
        let measured = label.size(withAttributes: attrs)
        let size = CGSize(width: ceil(measured.width) + 20, height: ceil(measured.height) + 12)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 9)
            background.setFill()
            path.fill()
            UIColor(hex: 0xBDC1C6).setStroke()
            path.stroke()
            label.draw(at: CGPoint(x: 10, y: 6), withAttributes: attrs)
        }
    }

    private func labeled(_ image: UIImage, label: String) -> UIImage {
        let caption = pill(label, background: .white.withAlphaComponent(0.94), foreground: UIColor(hex: 0x202124))
        let size = CGSize(width: max(image.size.width, caption.size.width), height: image.size.height + caption.size.height)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(at: CGPoint(x: (size.width - image.size.width) / 2, y: 0))
            caption.draw(at: CGPoint(x: (size.width - caption.size.width) / 2, y: image.size.height))
        }
    }

    func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
        if let point = annotation as? MKPointAnnotation, measurementPoints.contains(where: { $0 === point }) { return }
        mapView.deselectAnnotation(annotation, animated: false)
        guard !choosingMeasurementEndpoint, let coordinator, coordinator.canTapPlace else { return }
        if let pin = annotation as? FeaturePin {
            coordinator.selectOverlay(pin.feature, source: pin.source)
        } else if let cluster = annotation as? MKClusterAnnotation {
            setCenter(cluster.coordinate, zoomLevel: min(zoomLevel + 2, 16), animated: true)
        } else if let feature = annotation as? MKMapFeatureAnnotation,
                  coordinator.model.directions == nil || coordinator.model.hasActiveJourney {
            let point = LatLng(feature.coordinate.latitude, feature.coordinate.longitude)
            if let name = feature.title { coordinator.model.resolveTapped(name: name, at: point) }
            else { coordinator.model.dropPin(at: point, focus: !coordinator.model.hasActiveJourney) }
        }
    }

    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed else { return }
        coordinator?.userMovedCamera(panOrRotate: false)
    }

    func beginDistanceMeasurement() {
        clearDistanceMeasurement()
        choosingMeasurementEndpoint = true
        setMeasurementPoints([native.centerCoordinate])
    }

    func clearDistanceMeasurement() {
        choosingMeasurementEndpoint = false
        native.removeAnnotations(measurementPoints)
        measurementPoints = []
        updateMeasurementLine()
    }

    private func setMeasurementPoints(_ coordinates: [CLLocationCoordinate2D]) {
        for (index, coordinate) in coordinates.enumerated() {
            if measurementPoints.indices.contains(index) {
                measurementPoints[index].coordinate = coordinate
            } else {
                let point = MKPointAnnotation()
                point.coordinate = coordinate
                point.title = index == 0 ? "A" : "B"
                measurementPoints.append(point)
                native.addAnnotation(point)
            }
        }
        updateMeasurementLine()
    }

    private func updateMeasurementLine() {
        if let measurementLine { native.removeOverlay(measurementLine) }
        if let measurementLabel { native.removeAnnotation(measurementLabel) }
        measurementLine = nil
        measurementLabel = nil
        guard measurementPoints.count == 2 else { return }
        let a = measurementPoints[0].coordinate
        let b = measurementPoints[1].coordinate
        let from = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let to = CLLocation(latitude: b.latitude, longitude: b.longitude)
        let meters = from.distance(from: to)
        let coordinates = [a, b]
        let line = MKGeodesicPolyline(coordinates: coordinates, count: coordinates.count)
        measurementLine = line
        native.addOverlay(line, level: .aboveLabels)

        let label = MKPointAnnotation()
        let midpoint = line.coordinate
        label.coordinate = midpoint
        let locale = AppSettings.shared.language.locale
        label.title = meters < 1_000 ? String(format: "%.0f m", locale: locale, meters)
            : String(format: "%.2f km", locale: locale, meters / 1_000)
        measurementLabel = label
        native.addAnnotation(label)
    }

    @objc private func measureTapped(_ recognizer: MapMeasurementTap) {
        guard coordinator?.model.hasActiveJourney == false else { return }
        let points = recognizer.points.map { native.convert($0, toCoordinateFrom: native) }
        guard points.count == 2, points.allSatisfy(CLLocationCoordinate2DIsValid) else { return }
        choosingMeasurementEndpoint = false
        setMeasurementPoints(points)
    }

    @objc private func measureHeld(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed,
              recognizer.numberOfTouches == 2,
              coordinator?.model.hasActiveJourney == false else { return }
        choosingMeasurementEndpoint = false
        let points = (0..<2).map { native.convert(recognizer.location(ofTouch: $0, in: native), toCoordinateFrom: native) }
        guard points.allSatisfy(CLLocationCoordinate2DIsValid) else { return }
        setMeasurementPoints(points)
    }

    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                 didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
        if newState == .ending || newState == .canceling {
            view.dragState = .none
            updateMeasurementLine()
        }
    }

    @objc private func pressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        coordinator?.dropAt(native.convert(recognizer.location(in: native), toCoordinateFrom: native))
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let coordinator, coordinator.canTapPlace else { return }
        let model = coordinator.model
        let screen = recognizer.location(in: native)
        if choosingMeasurementEndpoint, let start = measurementPoints.first {
            let endpoint = native.convert(screen, toCoordinateFrom: native)
            guard CLLocationCoordinate2DIsValid(endpoint) else { return }
            choosingMeasurementEndpoint = false
            setMeasurementPoints([start.coordinate, endpoint])
            return
        }
        guard let directions = model.directions, let chosen = directions.route, !model.hasActiveJourney else { return }
        let coordinate = native.convert(screen, toCoordinateFrom: native)
        let tap = LatLng(coordinate.latitude, coordinate.longitude)
        let nearest = directions.current.enumerated().compactMap { index, route -> (Int, CGFloat)? in
            guard route.polyline.count >= 2 else { return nil }
            let projection = Geo.project(tap, on: route.polyline, cumulative: Geo.cumulative(route.polyline))
            let point = Geo.point(along: route.polyline, meters: projection.along)
            let projected = native.convert(CLLocationCoordinate2D(latitude: point.lat, longitude: point.lng),
                                           toPointTo: native)
            return (index, hypot(projected.x - screen.x, projected.y - screen.y))
        }.min { $0.1 < $1.1 }
        if let (index, distance) = nearest, distance <= 20, directions.current[index].id != chosen.id {
            model.selectRoute(index)
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is MapMeasurementTap {
            return coordinator?.model.hasActiveJourney == false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer !== measureGesture && otherGestureRecognizer !== measureGesture
    }

    private func allGestures(in view: UIView) -> [UIGestureRecognizer] {
        (view.gestureRecognizers ?? []) + view.subviews.flatMap { allGestures(in: $0) }
    }

    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        let changing = allGestures(in: mapView).filter { $0.state == .began || $0.state == .changed }
        let moved = changing.contains { $0 is UIPanGestureRecognizer || $0 is UIRotationGestureRecognizer }
        if moved || changing.contains(where: { $0 is UIPinchGestureRecognizer }) {
            Task { @MainActor [weak coordinator = self.coordinator] in coordinator?.userMovedCamera(panOrRotate: moved) }
        }
    }

    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        updateBearingViews(heading: mapView.camera.heading)
        queueRegionUpdate()
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { queueRegionUpdate() }

    private func queueRegionUpdate() {
        guard regionUpdate == nil else { return }
        regionUpdate = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard let self else { return }
            self.regionUpdate = nil
            self.coordinator?.cameraChanged(self)
        }
    }

    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        guard let location = userLocation.location else { return }
        Task { @MainActor [weak self] in
            if let self { self.coordinator?.firstUserLocation(location, on: self) }
        }
    }
}

private final class AppleHeatTiles: MKTileOverlay {
    @MainActor init() {
        super.init(urlTemplate: nil)
        minimumZ = HighwayHeat.minZoom
        maximumZ = HighwayHeat.maxZoom
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping @Sendable (Data?, (any Error)?) -> Void) {
        let tile = HighwayHeat.Tile(z: path.z, x: path.x, y: path.y)
        URLSession.shared.dataTask(with: HighwayHeat.url(tile)) { data, _, error in
            result(data.flatMap { HighwayHeat.colour($0, zoom: tile.z)?.pngData() }, error)
        }.resume()
    }
}

// UIKit may discard touch locations before a tap action runs. Keep both coordinates until reset.
private final class MapMeasurementTap: UIGestureRecognizer {
    private var initialLocations: [UITouch: CGPoint] = [:]
    private var activeTouches: Set<UITouch> = []
    private var startedAt: TimeInterval?
    private(set) var points: [CGPoint] = []

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let first = touches.map(\.timestamp).min() else { return }
        let start = startedAt ?? first
        startedAt = start
        guard initialLocations.count + touches.count <= 2, first - start <= 0.15,
              activeTouches.count == initialLocations.count else {
            state = .failed
            return
        }
        for touch in touches { initialLocations[touch] = touch.location(in: view) }
        activeTouches.formUnion(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if !stayedStill(touches) { state = .failed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard initialLocations.count == 2, stayedStill(touches),
              let start = startedAt, touches.allSatisfy({ $0.timestamp - start < 0.35 }) else {
            state = .failed
            return
        }
        points.append(contentsOf: touches.map { $0.location(in: view) })
        activeTouches.subtract(touches)
        guard activeTouches.isEmpty else { return }
        state = hypot(points[0].x - points[1].x, points[0].y - points[1].y) >= 22 ? .recognized : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func reset() {
        super.reset()
        initialLocations.removeAll()
        activeTouches.removeAll()
        startedAt = nil
        points.removeAll()
    }

    private func stayedStill(_ touches: Set<UITouch>) -> Bool {
        touches.allSatisfy { touch in
            guard let start = initialLocations[touch] else { return false }
            let point = touch.location(in: view)
            return hypot(point.x - start.x, point.y - start.y) <= 10
        }
    }
}
