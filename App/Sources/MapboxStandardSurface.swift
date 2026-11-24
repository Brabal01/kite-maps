#if canImport(MapboxMaps)
import CoreLocation
@_spi(Experimental) import MapboxMaps
import MapLibre
import os
import UIKit
import VelaCore

/// Keeps MapLibre alive for gestures, camera state, and offline fallback while Standard renders the online map.
@MainActor
final class MapboxStandardSurface: MapboxMaps.MapView {
    private static let log = Logger(subsystem: "app.vela.ios", category: "MapboxStandard")

    struct Appearance: Equatable {
        let dark: Bool
        let satellite: Bool
        let driving: Bool
        let terrain: Bool
        let palette: MapPalette
        let wazeScale: Double

        var style: MapStyle {
            let light: StandardLightPreset = dark ? .night : .day
            func color(_ field: MapPaletteField) -> StyleColor { StyleColor(UIColor(hex: palette[field])) }
            if satellite {
                return .standardSatellite(lightPreset: light, showTransitLabels: !driving,
                                          colorMotorways: color(.highways), colorRoads: color(.streets))
            }
            return .standard(lightPreset: light, showPointOfInterestLabels: !driving,
                             showTransitLabels: !driving, showPedestrianRoads: true, colorBuildings: color(.buildings),
                             colorGreenspace: color(.parks), colorLand: color(.land), colorMotorways: color(.highways),
                             colorRoads: color(.streets), colorWater: color(.water), show3dBuildings: true,
                             show3dLandmarks: true, show3dTrees: true)
        }
    }

    private struct Camera: Equatable {
        let latitude: Double
        let longitude: Double
        let zoom: CGFloat
        let bearing: Double
        let pitch: CGFloat
        let padding: UIEdgeInsets

        init(_ map: MLNMapView) {
            let center = map.centerCoordinate
            latitude = center.latitude
            longitude = center.longitude
            zoom = CGFloat(map.zoomLevel)
            bearing = map.direction
            pitch = map.camera.pitch

            // MapLibre centers the target within the padded viewport. Preserve the screen anchor.
            let screen = map.convert(center, toPointTo: map)
            let x = 2 * (screen.x - map.bounds.midX)
            let y = 2 * (screen.y - map.bounds.midY)
            padding = UIEdgeInsets(top: max(0, y), left: max(0, x),
                                   bottom: max(0, -y), right: max(0, -x))
        }

        var options: CameraOptions {
            CameraOptions(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                          padding: padding, zoom: zoom, bearing: bearing, pitch: pitch)
        }
    }

    private let token: String
    private var appearance: Appearance
    private weak var classic: MLNMapView?
    private var subscriptions = Set<AnyCancelable>()
    private var lastCamera: Camera?
    private var overlaysReady = false
    private var lastShapes: [String: MLNShape] = [:]
    private var styleImageNames: Set<String> = []
    private var marker = "puck"
    private var availableModels: Set<String> = []
    private var vehicleModel: String?
    private var vehicleRotation: Double?
    private var layerVisibility: [String: Bool] = [:]
    private var darkImages = false
    private var lastLocation: CLLocationCoordinate2D?

    init(classic: MLNMapView, token: String, appearance: Appearance) {
        self.classic = classic
        self.token = token
        self.appearance = appearance
        MapboxOptions.accessToken = token
        super.init(frame: classic.bounds,
                   mapInitOptions: MapInitOptions(mapStyle: appearance.style, cameraOptions: Camera(classic).options))

        isHidden = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        ornaments.options.scaleBar.visibility = .hidden
        ornaments.options.compass.visibility = .hidden
        ornaments.options.logo.position = .bottomLeading
        ornaments.options.logo.margins = CGPoint(x: 10, y: 126)
        ornaments.options.attributionButton.position = .bottomTrailing
        ornaments.options.attributionButton.margins = CGPoint(x: 10, y: 126)
        mapboxMap.onStyleLoaded.observe { [weak self] _ in
            self?.installOverlays()
        }.store(in: &subscriptions)
        mapboxMap.onMapLoaded.observe { [weak self] _ in
            guard let self, overlaysReady else { return }
            syncCamera()
            syncOverlays()
            isHidden = false
        }.store(in: &subscriptions)
        mapboxMap.onMapLoadingError.observe { [weak self] error in
            guard error.type == .style else { return }
            self?.isHidden = true
            Self.log.warning("Standard style could not load. Showing the fallback map.")
        }.store(in: &subscriptions)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(classic:token:appearance:)") }

    func usesToken(_ value: String) -> Bool { token == value }

    func update(_ appearance: Appearance) {
        if self.appearance != appearance {
            if self.appearance.satellite != appearance.satellite {
                overlaysReady = false
                isHidden = true
            }
            let styleChanged = self.appearance.dark != appearance.dark || self.appearance.satellite != appearance.satellite
                || self.appearance.driving != appearance.driving || self.appearance.palette != appearance.palette
            self.appearance = appearance
            if styleChanged { mapboxMap.mapStyle = appearance.style }
            if overlaysReady {
                updateTerrain()
                updateWazeSize()
                try? mapboxMap.setLayerProperty(for: "vela-route", property: "line-color", value: routeColor)
            }
        }
        syncCamera()
        syncOverlays()
    }

    // Kite's existing gestures continue to operate on the same camera and source features.
    // Native SDK attribution remains interactive.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, let hit = super.hitTest(point, with: event) else { return nil }
        let button = ornaments.attributionButton
        return hit === button || hit.isDescendant(of: button) ? hit : nil
    }

    func place(at point: CGPoint) async -> (String, CLLocationCoordinate2D)? {
        guard !isHidden else { return nil }
        let box = CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)
        return await withCheckedContinuation { continuation in
            mapboxMap.queryRenderedFeatures(with: box, featureset: .standardPoi) { result in
                let place = try? result.get().first(where: { $0.name != nil })
                guard let place, let name = place.name, case let .point(geometry) = place.geometry else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (name, geometry.coordinates))
            }
        }
    }

    func syncCamera() {
        guard let classic, classic.bounds.width > 0, classic.bounds.height > 0 else { return }
        let next = Camera(classic)
        guard next != lastCamera else { return }
        lastCamera = next
        mapboxMap.setCamera(to: next.options)
    }

    func syncOverlays() {
        guard overlaysReady, let style = classic?.style else { return }
        for id in Self.images where !styleImageNames.contains(id) {
            guard let image = style.image(forName: id) else { continue }
            do {
                try mapboxMap.addImage(image, id: id)
                styleImageNames.insert(id)
            } catch {
                Self.log.debug("A Kite map icon could not be registered.")
            }
        }
        for id in Self.controlledLayers {
            guard let visible = style.layer(withIdentifier: id)?.isVisible, layerVisibility[id] != visible else { continue }
            try? mapboxMap.setLayerProperty(for: id, property: "visibility", value: visible ? "visible" : "none")
            layerVisibility[id] = visible
        }
        for id in Self.sources {
            let shape = (style.source(withIdentifier: id) as? MLNShapeSource)?.shape
            guard shape !== lastShapes[id] else { continue }
            if let shape {
                do {
                    let data = shape.geoJSONData(usingEncoding: String.Encoding.utf8.rawValue)
                    let geoJSON = try JSONSerialization.jsonObject(with: data)
                    try mapboxMap.setSourceProperty(for: id, property: "data", value: geoJSON)
                    lastShapes[id] = shape
                } catch {
                    Self.log.debug("A Kite overlay could not be synchronized.")
                }
            } else {
                try? mapboxMap.setSourceProperty(for: id, property: "data", value: Self.empty)
                lastShapes[id] = nil
            }
        }
        if darkImages != appearance.dark {
            darkImages = appearance.dark
            if let image = style.image(forName: "puck") { try? mapboxMap.addImage(image, id: "puck") }
        }
        if let layer = style.layer(withIdentifier: "vela-puck") as? MLNSymbolStyleLayer,
           let name = layer.iconImageName?.constantValue as? String, name != marker {
            if let image = style.image(forName: name), !styleImageNames.contains(name) {
                try? mapboxMap.addImage(image, id: name)
                styleImageNames.insert(name)
            }
            try? mapboxMap.setLayerProperty(for: "vela-puck", property: "icon-image", value: name)
            marker = name
        }
        syncVehicleModel(style: style)
        let coordinate = classic?.showsUserLocation == true ? classic?.userLocation?.location?.coordinate : nil
        if let coordinate, CLLocationCoordinate2DIsValid(coordinate) {
            guard coordinate.latitude != lastLocation?.latitude || coordinate.longitude != lastLocation?.longitude else { return }
            let point: [String: Any] = ["type": "Point", "coordinates": [coordinate.longitude, coordinate.latitude]]
            try? mapboxMap.setSourceProperty(for: "kite-location", property: "data", value: point)
            lastLocation = coordinate
        } else if lastLocation != nil {
            lastLocation = nil
            try? mapboxMap.setSourceProperty(for: "kite-location", property: "data", value: Self.empty)
        }
    }

    private func syncVehicleModel(style: MLNStyle) {
        guard mapboxMap.layerExists(withId: "kite-vehicle-model") else { return }
        let selected = switch marker {
        case "DriveAlfaTilt": "drive_alfa_147"
        case "DriveVanTilt": "drive_van"
        default: ""
        }
        let next = availableModels.contains(selected) && (classic?.camera.pitch ?? 0) > 1 ? selected : nil
        if next != vehicleModel {
            if let next { try? mapboxMap.setLayerProperty(for: "kite-vehicle-model", property: "model-id", value: next) }
            try? mapboxMap.setLayerProperty(for: "kite-vehicle-model", property: "visibility", value: next == nil ? "none" : "visible")
            try? mapboxMap.setLayerProperty(for: "vela-puck", property: "visibility", value: next == nil ? "visible" : "none")
            vehicleModel = next
        }
        guard next != nil, let source = style.source(withIdentifier: "vela-puck") as? MLNShapeSource,
              let feature = source.shape as? MLNPointFeature,
              let bearing = feature.attribute(forKey: "bearing") as? Double, bearing != vehicleRotation else { return }
        try? mapboxMap.setLayerProperty(for: "kite-vehicle-model", property: "model-rotation", value: [0, 0, bearing])
        vehicleRotation = bearing
    }

    private func installOverlays() {
        if mapboxMap.layerExists(withId: "vela-puck") { return }
        do {
            lastShapes.removeAll()
            styleImageNames.removeAll()
            layerVisibility.removeAll()
            vehicleModel = nil
            vehicleRotation = nil
            marker = "puck"
            lastLocation = nil
            darkImages = appearance.dark
            for id in Self.sources + ["kite-location"] {
                try mapboxMap.addSource(withId: id, properties: ["type": "geojson", "data": Self.empty])
            }
            try addLayers()
            installVehicleModels()
            updateTerrain()
            updateWazeSize()
            overlaysReady = true
            syncOverlays()
        } catch {
            overlaysReady = false
            isHidden = true
            Self.log.warning("Kite overlays could not be installed. Showing the fallback map.")
        }
    }

    private var routeColor: String { String(format: "#%06X", appearance.palette[.route]) }

    private func addLayers() throws {
        guard let map = mapboxMap else { return }
        func line(_ id: String, source: String? = nil, color: Any, width: Int, filter: [Any]? = nil) throws {
            let paint: [String: Any] = ["line-color": color, "line-width": width]
            var layer: [String: Any] = ["id": id, "source": source ?? id, "type": "line", "slot": "middle",
                                        "layout": ["line-cap": "round", "line-join": "round"], "paint": paint]
            if let filter { layer["filter"] = filter }
            try map.addLayer(with: layer, layerPosition: nil)
        }
        func point(_ id: String, layout: [String: Any]) throws {
            try map.addLayer(with: ["id": id, "source": id, "type": "symbol", "slot": "top", "layout": layout,
                                    "paint": ["text-halo-color": "#FFFFFF", "text-halo-width": 1.2,
                                              "text-color": "#182436"]], layerPosition: nil)
        }
        try line("vela-route-done", color: "#718096", width: 8)
        try line("vela-route-alt", color: "#80AEE8", width: 7)
        try line("kite-route-edge", source: "vela-route", color: "#0F766E", width: 14)
        try line("vela-route", color: routeColor, width: 10)
        try line("vela-route-traffic", color: ["match", ["get", "level"], 1, "#F59E0B", 2, "#EF4444", 3, "#B91C1C", "#2563EB"], width: 10)
        try line("vela-transit", color: ["to-color", ["get", "color"]], width: 7, filter: ["==", ["get", "walk"], 0])
        try line("kite-transit-walk", source: "vela-transit", color: "#777777", width: 5, filter: ["==", ["get", "walk"], 1])
        try point("vela-road-name", layout: ["text-field": ["get", "label"], "text-size": 15, "symbol-placement": "line-center"])
        for id in ["vela-signals", "vela-cameras", "vela-livecams", "vela-waze", "vela-waze-group"] {
            try point(id, layout: ["icon-image": ["get", "icon"], "icon-allow-overlap": true])
        }
        for id in ["vela-mine", "vela-results", "vela-selected"] {
            try point(id, layout: ["icon-image": ["get", "icon"], "text-field": ["get", "label"],
                                   "icon-allow-overlap": true, "text-optional": true,
                                   "text-size": 12, "text-anchor": "top", "text-offset": [0, 1.4]])
        }
        try point("vela-route-bubbles", layout: [
            "icon-image": ["case", ["==", ["get", "sel"], 1], "bubble-sel", "bubble-alt"],
            "icon-text-fit": "both", "icon-text-fit-padding": [6, 12, 6, 12],
            "text-field": ["get", "label"], "text-size": 14,
            "text-allow-overlap": true, "icon-allow-overlap": true
        ])
        try point("vela-puck", layout: ["icon-image": "puck", "icon-rotate": ["get", "bearing"],
                                       "icon-rotation-alignment": "map", "icon-pitch-alignment": "map",
                                       "icon-allow-overlap": true])
        for (id, color) in [("kite-location", "#2563EB"), ("kite-transit-vehicle", "#0F766E")] {
            try map.addLayer(with: ["id": id, "type": "circle", "source": id, "slot": "top",
                                    "paint": ["circle-color": color, "circle-radius": 7,
                                              "circle-stroke-color": "#FFFFFF", "circle-stroke-width": 2]], layerPosition: nil)
        }
    }

    private func updateWazeSize() {
        for id in ["vela-waze", "vela-waze-group"] {
            try? mapboxMap.setLayerProperty(for: id, property: "icon-size", value: appearance.wazeScale)
        }
        let scale: [Any] = ["case", ["==", ["get", "waze"], 1], appearance.wazeScale, 1]
        try? mapboxMap.setLayerProperty(for: "vela-cameras", property: "icon-size", value: scale)
    }

    private func updateTerrain() {
        let id = "kite-standard-dem"
        guard appearance.terrain, !appearance.satellite else {
            if mapboxMap.sourceExists(withId: id) { mapboxMap.removeTerrain() }
            return
        }
        do {
            if !mapboxMap.sourceExists(withId: id) {
                var elevation = RasterDemSource(id: id)
                elevation.url = "mapbox://mapbox.mapbox-terrain-dem-v1"
                elevation.tileSize = 512
                try mapboxMap.addSource(elevation)
            }
            try mapboxMap.setTerrain(Terrain(sourceId: id))
        } catch {
            Self.log.debug("The elevation source could not be added to Standard.")
        }
    }

    private func installVehicleModels() {
        availableModels.removeAll()
        for id in ["drive_alfa_147", "drive_van"] {
            guard let uri = Bundle.main.url(forResource: id, withExtension: "glb") else { continue }
            do {
                try mapboxMap.addStyleModel(modelId: id, modelUri: uri.absoluteString)
                availableModels.insert(id)
            } catch {
                Self.log.debug("A navigation model could not be installed.")
            }
        }
        guard let first = availableModels.sorted().first else { return }
        try? mapboxMap.addLayer(with: [
            "id": "kite-vehicle-model", "source": "vela-puck", "type": "model", "slot": "top",
            "layout": ["visibility": "none", "model-id": first],
            "paint": ["model-type": "location-indicator", "model-scale": [2.5, 2.5, 2.5]]
        ], layerPosition: nil)
    }

    private static let controlledLayers = ["vela-signals", "vela-cameras", "vela-livecams", "vela-waze", "vela-waze-group"]

    private static let sources = [
        "vela-route-done", "vela-route-alt", "vela-route", "vela-route-traffic", "vela-route-bubbles",
        "vela-transit", "kite-transit-vehicle", "vela-road-name", "vela-signals", "vela-cameras",
        "vela-livecams", "vela-waze", "vela-waze-group", "vela-mine", "vela-results", "vela-selected", "vela-puck"
    ]

    private static let images = MapIcons.kinds.map(\.name) + WazeAlert.Kind.allCases.map { "waze-\($0.rawValue)" } + [
        "cat-default", "pin-selected", "pin-origin", "puck", "bubble-sel", "bubble-alt",
        "cam-speed", "cam-plate", "cam-surveillance", "traffic-light", "route-stop",
        "route-railway", "route-pedestrian", "livecam-road", "livecam-web", "pin-stop",
        "mine-home", "mine-work", "mine-parking", "mine-saved"
    ]

    private static let empty: [String: Any] = ["type": "FeatureCollection", "features": [[String: Any]]()]
}
#endif
