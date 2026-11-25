import MapLibre
import os
import SwiftUI
import UIKit
import VelaCore

/** The full-screen map: OpenFreeMap Liberty painted in Vela's colors, plus Vela's own layers
 *  (result pins, routes with traffic, the navigation puck, live traffic, satellite). */
struct VelaMapView: UIViewRepresentable {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let dark: Bool

    static let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> MLNMapView {
        LaunchTrace.mark("MapLibre makeUIView")
        let map = MLNMapView(frame: .zero, styleURL: Self.styleURL)
        let c = context.coordinator
        map.delegate = c
        map.showsUserLocation = true
        // Your blue dot in Kite's teal, to match the route and the driving arrow.
        map.tintColor = UIColor(hex: 0x14B8A6)
        map.compassView.isHidden = true
        map.logoView.isHidden = true
        map.attributionButtonPosition = .bottomLeft
        map.attributionButtonMargins = CGPoint(x: 8, y: 8)
        // Never open on a hard-coded city: restore the user's last area, or their
        // current fix, or a neutral world view until the first fix arrives.
        let start = model.mapStart
        map.setCenter(start.center, zoomLevel: start.zoom, animated: false)
        let camera = map.camera
        camera.pitch = model.browsePitch
        map.camera = camera

        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tapped(_:)))
        for r in map.gestureRecognizers ?? [] {
            if let t = r as? UITapGestureRecognizer, t.numberOfTapsRequired == 2 { tap.require(toFail: t) }
        }
        let press = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.pressed(_:)))
        press.delegate = c
        map.addGestureRecognizer(press)
        // A long press must never also count as a tap, or the tap closes the pin it just dropped.
        tap.require(toFail: press)
        tap.delegate = c
        map.addGestureRecognizer(tap)

        c.dark = dark
        c.movedToUser = model.attachMap(map)
        c.surface = map
        // Reports found by the background sweep show on the heat map straight away.
        WazeHistory.shared.onChange = { [weak c, weak map] in if let c, let map { c.render(map) } }
        // The camera list arrives in the background: draw it as soon as it's here.
        LiveCamStore.shared.onChange = { [weak c, weak map] in if let c, let map { c.render(map) } }
        // On a first launch, location is asked for after the welcome, not on top of it.
        if (settings.welcomed && !settings.needsWazeChoice) || DemoScript.active { model.location.start() }
        return map
    }

    static func dismantleUIView(_ map: MLNMapView, coordinator: Coordinator) {
        coordinator.model.detachMap(map)
        map.delegate = nil
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let c = context.coordinator
        if c.dark != dark {
            c.dark = dark
            c.repaint(map)
        }
        c.render(map)
        c.loadCameras(map)
        c.loadWazeCameras(map)
        c.loadSurveillance(map)
        c.loadWaze(map)
        c.loadLiveCams(map)
    }

    @MainActor
    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        /** What the browse map asked Waze and got, for checking a test run afterwards. */
        static let trace = Logger(subsystem: "app.vela.ios", category: "trace")

        /** Reports that always keep their own icon, never joining a numbered bubble. */
        static let neverGrouped: Set<WazeAlert.Kind> = [.police, .accident]

        /** Icons close together join into one bubble up to zoom 13 (a whole town in view); closer in, every icon shows. */
        static let groupOptions: [MLNShapeSourceOption: Any] = [
            .clustered: true, .clusterRadius: 44, .maximumZoomLevelForClustering: 13,
        ]

        /** The numbered bubble for a group: a dark circle with a colored ring, bigger for more. */
        static func addGroupBubbles(_ style: MLNStyle, source: MLNShapeSource, id: String, ring: UIColor, minZoom: Float) {
            let bubble = MLNCircleStyleLayer(identifier: "\(id)-bubble", source: source)
            bubble.predicate = NSPredicate(format: "cluster == YES")
            bubble.circleColor = NSExpression(forConstantValue: UIColor(hex: 0x0F172A))
            bubble.circleOpacity = NSExpression(forConstantValue: 0.92)
            bubble.circleStrokeColor = NSExpression(forConstantValue: ring)
            bubble.circleStrokeWidth = NSExpression(forConstantValue: 3)
            bubble.circleRadius = NSExpression(mglJSONObject: ["step", ["get", "point_count"], 14, 10, 17, 50, 21])
            bubble.minimumZoomLevel = minZoom
            style.addLayer(bubble)
            let count = MLNSymbolStyleLayer(identifier: "\(id)-count", source: source)
            count.predicate = NSPredicate(format: "cluster == YES")
            count.text = NSExpression(mglJSONObject: ["to-string", ["get", "point_count"]])
            count.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
            count.textFontSize = NSExpression(forConstantValue: 13)
            count.textColor = NSExpression(forConstantValue: UIColor.white)
            count.textAllowsOverlap = NSExpression(forConstantValue: true)
            count.minimumZoomLevel = minZoom
            style.addLayer(count)
        }
        let model: AppModel
        var dark = false
        private var styleReady = false
        var movedToUser = false
        weak var surface: (any KiteMapSurface)?
        private var pinDroppedAt = Date.distantPast
        private var originalLabels: [String: (NSExpression?, NSExpression?, NSExpression?)] = [:]
        private var lastResultsKey = ""
        private var lastRouteKey = ""
        private var lastMineKey = ""
        private var appliedMapboxKey = ""
        private var lastPuckKey = ""
        private var lastTransitVehicleKey = ""
        /** Whether the map is currently stripped down for driving; nil after a style load. */
        private var styledDriving: Bool?
        /** The map preset currently applied to the style, nil after a style load. */
        private var styledPreset: MapPreset?
        private var lastCameraKey = ""
        private var drawnControls: [RouteControl]?
        private var drawnSignals: [LatLng] = []
        private var lastLiveKey = ""
        /** The box the drawn live camera dots cover, so panning inside it redraws nothing. */
        private var liveBox: (s: Double, w: Double, n: Double, e: Double)?
        /** Cameras fetched so far, and the 0.1° cells already asked for (cameras don't move). */
        private var cameras: [Int64: RoadCamera] = [:]
        private var cameraCells: Set<String> = []
        private var cameraFetch: Task<Void, Never>?
        private var driveCameraFetch: Task<Void, Never>?
        private var driveCameraCenter: LatLng?
        private var driveCameraAttempt = Date.distantPast
        private var nearbyDriveCameras: [RoadCamera] = []
        private var driveCameraRevision = 0
        private var wazeCameraFetch: Task<Void, Never>?
        private var surveillanceFetch: Task<Void, Never>?
        private var surveillanceCells: Set<String> = []
        private var surveillance: [Int64: SurveillanceCamera] = [:]
        private var railFetch: Task<Void, Never>?
        /** Live Waze reports for the box last asked about, and when. */
        private var wazeAlerts: [WazeAlert] = []
        private var wazeBox: (s: Double, w: Double, n: Double, e: Double)?
        private var wazeAt = Date.distantPast
        private var wazeFetch: Task<Void, Never>?
        /** When Waze last didn't answer: wait a minute before asking again, rather than on every pan. */
        private var wazeFailedAt = Date.distantPast
        private var wazeAskedAt = Date.distantPast
        /** The police heat map, from Highway Radar's tiles. */
        let heatTiles = HighwayHeat()
        private var wazeRetryQueued = false
        private var lastWazeKey = ""
        /** The box the drawn rail lines cover, so panning inside it asks nothing. */
        private var railBox: (s: Double, w: Double, n: Double, e: Double, z: Int)?
        private var railLines: [Transitous.Line] = []
        private var publishedRailFilter: Set<String>?

        init(model: AppModel) { self.model = model }

        // MARK: Style

        nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            MainActor.assumeIsolated { styleLoaded(mapView, style) }
        }

        private func styleLoaded(_ mapView: MLNMapView, _ style: MLNStyle) {
            for case let s as MLNSymbolStyleLayer in style.layers {
                originalLabels[s.identifier] = (s.textColor, s.textHaloColor, s.textHaloWidth)
            }
            appliedMapboxKey = ""
            MapIcons.register(in: style)
            addVelaLayers(style)
            styleReady = true
            heatTiles.styleReloaded()
            styledDriving = nil
            styledPreset = nil
            repaint(mapView)
            publishedRailFilter = nil
            lastResultsKey = ""; lastRouteKey = ""; lastMineKey = ""; lastPuckKey = ""; lastTransitVehicleKey = ""; lastCameraKey = ""; drawnControls = nil; drawnSignals = []; lastWazeKey = ""; lastLiveKey = ""
            render(mapView)
        }

        func repaint(_ map: MLNMapView) {
            guard let style = map.style, styleReady else { return }
            if !dark {
                for case let s as MLNSymbolStyleLayer in style.layers {
                    if let o = originalLabels[s.identifier] {
                        s.textColor = o.0 ?? s.textColor
                        s.textHaloColor = o.1 ?? s.textHaloColor
                        s.textHaloWidth = o.2 ?? s.textHaloWidth
                    }
                }
            }
            MapStyler.apply(style, dark: dark)
            (style.layer(withIdentifier: "vela-route-line") as? MLNLineStyleLayer)?.lineColor =
                NSExpression(forConstantValue: UIColor(hex: dark ? 0x409CFF : 0x007AFF))
            (style.layer(withIdentifier: "vela-route-halo") as? MLNLineStyleLayer)?.lineOpacity =
                NSExpression(forConstantValue: dark ? 0.55 : 0.85)
            // The car's disc: navy at night, white by day.
            style.setImage(MapIcons.puck(dark: dark), forName: "puck")
            (style.layer(withIdentifier: "vela-rail-case") as? MLNLineStyleLayer)?.lineColor =
                NSExpression(forConstantValue: UIColor(white: dark ? 0 : 1, alpha: 0.9))
            // Names next to our pins: dark text on a white halo by day, light text on navy at night.
            let text = dark ? UIColor(hex: 0xE8EAED) : UIColor(hex: 0x202124)
            let halo = dark ? UIColor(hex: 0x0B1526) : UIColor.white
            for id in ["vela-mine", "vela-results", "vela-selected"] {
                guard let l = style.layer(withIdentifier: id) as? MLNSymbolStyleLayer else { continue }
                l.textColor = NSExpression(forConstantValue: text)
                l.textHaloColor = NSExpression(forConstantValue: halo)
                l.textHaloWidth = NSExpression(forConstantValue: 1.5)
            }
            lastResultsKey = ""
            lastRouteKey = ""
        }

        private func firstSymbolLayer(_ style: MLNStyle) -> MLNStyleLayer? {
            style.layers.first { $0 is MLNSymbolStyleLayer }
        }

        private func addVelaLayers(_ style: MLNStyle) {
            // Satellite (Esri World Imagery) under the roads, off unless picked in Layers.
            let sat = MLNRasterTileSource(identifier: "vela-sat", tileURLTemplates: [
                "https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
            ], options: [.tileSize: 256, .maximumZoomLevel: 19,
                         .attributionHTMLString: "Imagery © Esri"])
            style.addSource(sat)
            let satLayer = MLNRasterStyleLayer(identifier: "vela-sat", source: sat)
            satLayer.isVisible = false
            if let below = style.layers.first(where: { $0.identifier.hasPrefix("tunnel_") }) {
                style.insertLayer(satLayer, below: below)
            } else {
                style.addLayer(satLayer)
            }

            // Terrain shading (Esri World Hillshade), blended over the land, off unless picked.
            let hill = MLNRasterTileSource(identifier: "vela-terrain", tileURLTemplates: [
                "https://services.arcgisonline.com/ArcGIS/rest/services/Elevation/World_Hillshade/MapServer/tile/{z}/{y}/{x}",
            ], options: [.tileSize: 256, .maximumZoomLevel: 16, .attributionHTMLString: "Hillshade © Esri"])
            style.addSource(hill)
            let hillLayer = MLNRasterStyleLayer(identifier: "vela-terrain", source: hill)
            hillLayer.rasterOpacity = NSExpression(forConstantValue: dark ? 0.22 : 0.32)
            hillLayer.isVisible = false
            if let below = style.layers.first(where: { $0.identifier.hasPrefix("tunnel_") || $0.identifier.hasPrefix("road_") }) {
                style.insertLayer(hillLayer, below: below)
            } else {
                style.addLayer(hillLayer)
            }

            // Google's live traffic tiles, the same keyless overlay Vela draws.
            let trafficURL = "https://www.google.com/maps/vt/pb=!1m4!1m3!1i{z}!2i{x}!3i{y}!2m9!1e2!2straffic!3i999999" +
                "!4m2!1sincidents!2s1!4m2!1sincidents_text!2s1!3m8!2sen!3sus!5e1105!12m4!1e68!2m2!1sset!2sRoadmap!4e0!5m1!1e0"
            let traffic = MLNRasterTileSource(identifier: "vela-traffic", tileURLTemplates: [trafficURL],
                                              options: [.tileSize: 256, .maximumZoomLevel: 16])
            style.addSource(traffic)
            let trafficLayer = MLNRasterStyleLayer(identifier: "vela-traffic", source: traffic)
            trafficLayer.rasterOpacity = NSExpression(forConstantValue: 0.6)
            trafficLayer.rasterFadeDuration = NSExpression(forConstantValue: 0.9)
            trafficLayer.isVisible = false
            if let above = style.layer(withIdentifier: "building-3d") ?? style.layer(withIdentifier: "building") {
                style.insertLayer(trafficLayer, above: above)
            } else {
                style.addLayer(trafficLayer)
            }

            // Routes: alternates, then the picked route, then its traffic, all under the labels.
            let labels = firstSymbolLayer(style)
            func insert(_ l: MLNStyleLayer) {
                if let labels { style.insertLayer(l, below: labels) } else { style.addLayer(l) }
            }
            let altSrc = MLNShapeSource(identifier: "vela-route-alt", shape: nil, options: nil)
            let routeSrc = MLNShapeSource(identifier: "vela-route", shape: nil, options: nil)
            let spanSrc = MLNShapeSource(identifier: "vela-route-traffic", shape: nil, options: nil)
            [altSrc, routeSrc, spanSrc].forEach(style.addSource)

            // Keep the chosen route distinct from traffic, vegetation and alternative routes.
            let doneSrc = MLNShapeSource(identifier: "vela-route-done", shape: nil, options: nil)
            style.addSource(doneSrc)
            let done = line("vela-route-done", doneSrc, UIColor(hex: 0x64748B), width: 10)
            done.lineOpacity = NSExpression(forConstantValue: 0.5)
            let altEdge = line("vela-route-alt-edge", altSrc, UIColor(hex: 0x475569), width: 9)
            altEdge.lineOpacity = NSExpression(forConstantValue: 0.78)
            let altFill = line("vela-route-alt", altSrc, UIColor(hex: 0xC0CBDA), width: 5)
            let halo = line("vela-route-halo", routeSrc, UIColor.white, width: 20)
            halo.lineOpacity = NSExpression(forConstantValue: 0.85)
            let edge = line("vela-route-edge", routeSrc, UIColor(hex: 0x092853), width: 16)
            let fill = line("vela-route-line", routeSrc, UIColor(hex: dark ? 0x409CFF : 0x007AFF), width: 12)
            let chevrons = MLNSymbolStyleLayer(identifier: "vela-route-chevrons", source: routeSrc)
            chevrons.symbolPlacement = NSExpression(forConstantValue: "line")
            chevrons.symbolSpacing = NSExpression(forConstantValue: 70)
            chevrons.iconImageName = NSExpression(forConstantValue: "route-chevron")
            chevrons.iconRotationAlignment = NSExpression(forConstantValue: "map")
            chevrons.iconAllowsOverlap = NSExpression(forConstantValue: true)
            chevrons.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            chevrons.keepsIconUpright = NSExpression(forConstantValue: false)
            chevrons.iconOpacity = NSExpression(forConstantValue: 0.55)
            chevrons.minimumZoomLevel = 13
            chevrons.isVisible = false
            [done, altEdge, altFill, halo, edge, fill, chevrons].forEach(insert)
            // A transit trip: each ride in its line's color, walks dotted.
            let transitSrc = MLNShapeSource(identifier: "vela-transit", shape: nil, options: nil)
            style.addSource(transitSrc)
            let walk = line("vela-transit-walk", transitSrc, UIColor(hex: 0x5F6368), width: 5)
            walk.predicate = NSPredicate(format: "walk == 1")
            walk.lineDashPattern = NSExpression(forConstantValue: [0.1, 1.8])
            let rideEdge = line("vela-transit-edge", transitSrc, UIColor(white: 0.1, alpha: 0.55), width: 10)
            rideEdge.predicate = NSPredicate(format: "walk == 0")
            let ride = line("vela-transit-ride", transitSrc, UIColor(hex: 0x1F6FEB), width: 7)
            ride.predicate = NSPredicate(format: "walk == 0")
            ride.lineColor = NSExpression(mglJSONObject: ["to-color", ["get", "color"]])
            // A metro, a tram and a bus stay visibly different even when two operators pick
            // similar colors: the line's own width carries the mode.
            let transitOpacity = NSExpression(mglJSONObject: ["match", ["get", "phase"], "done", 0.28, "upcoming", 0.6, 1.0])
            for layer in [walk, rideEdge, ride] { layer.lineOpacity = transitOpacity }
            ride.lineWidth = NSExpression(mglJSONObject: ["match", ["get", "phase"], "active", Self.transitWidth(extra: 3),
                                                            "done", Self.transitWidth(extra: 0), Self.transitWidth(extra: 1.5)])
            [walk, rideEdge, ride].forEach(insert)
            // Live vehicle positions from an optional GTFS-Realtime feed.
            let vehicleSrc = MLNShapeSource(identifier: "vela-transit-vehicle", shape: nil, options: nil)
            style.addSource(vehicleSrc)
            let vehicle = MLNSymbolStyleLayer(identifier: "vela-transit-vehicle", source: vehicleSrc)
            vehicle.iconImageName = NSExpression(forKeyPath: "icon")
            vehicle.iconAllowsOverlap = NSExpression(forConstantValue: true)
            vehicle.text = NSExpression(forKeyPath: "label")
            vehicle.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
            vehicle.textFontSize = NSExpression(forConstantValue: 12)
            vehicle.textColor = NSExpression(forConstantValue: UIColor(hex: 0x4C1D95))
            vehicle.textHaloColor = NSExpression(forConstantValue: UIColor.white)
            vehicle.textHaloWidth = NSExpression(forConstantValue: 1.5)
            vehicle.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.4)))
            vehicle.textAllowsOverlap = NSExpression(forConstantValue: true)
            insert(vehicle)
            for (level, color) in [(1, 0xF59E0B), (2, 0xEF4444), (3, 0xB91C1C)] {
                let l = line("vela-route-traffic-\(level)", spanSrc, UIColor(hex: UInt32(color)), width: 5)
                l.predicate = NSPredicate(format: "level == %d", level)
                insert(l)
            }

            // Metro, tram and rail lines in their own colors, from zoom 10 in (Transitous).
            let railSrc = MLNShapeSource(identifier: "vela-rail", shape: nil, options: nil)
            style.addSource(railSrc)
            let railCase = line("vela-rail-case", railSrc, UIColor(white: dark ? 0 : 1, alpha: 0.9), width: 5.5)
            let rail = line("vela-rail", railSrc, .gray, width: 3.2)
            rail.lineColor = NSExpression(format: "CAST(color, 'UIColor')")
            // Lines sharing one track are drawn side by side instead of the last one winning.
            rail.lineOffset = NSExpression(forKeyPath: "offset")
            railCase.lineOffset = NSExpression(forKeyPath: "offset")
            rail.lineWidth = NSExpression(mglJSONObject: Self.transitWidth(extra: 0))
            railCase.lineWidth = NSExpression(mglJSONObject: Self.transitWidth(extra: 2.2))
            for l in [railCase, rail] {
                l.minimumZoomLevel = 10
                l.isVisible = false
                insert(l)
            }

            // Traffic lights on the route while driving, small and under the cameras, like Waze.
            let sigSrc = MLNShapeSource(identifier: "vela-signals", shape: nil, options: nil)
            style.addSource(sigSrc)
            let sigs = MLNSymbolStyleLayer(identifier: "vela-signals", source: sigSrc)
            sigs.iconImageName = NSExpression(forKeyPath: "icon")
            sigs.iconAllowsOverlap = NSExpression(forConstantValue: true)
            sigs.iconAnchor = NSExpression(forConstantValue: "bottom")
            sigs.iconScale = NSExpression(mglJSONObject: ["interpolate", ["linear"], ["zoom"], 14, 0.75, 17, 1.0])
            sigs.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            sigs.minimumZoomLevel = 0
            style.addLayer(sigs)

            // Live camera photos, under the speed cameras: Windy webcams from zoom 6 (a region), road
            // cameras from zoom 9 (a city). Zoomed out over a busy city (central London) they join into
            // numbered blue bubbles, like the speed cameras (Matteo, 2026-11-13).
            let liveSrc = MLNShapeSource(identifier: "vela-livecams", shape: nil, options: Self.groupOptions)
            style.addSource(liveSrc)
            let live = MLNSymbolStyleLayer(identifier: "vela-livecams", source: liveSrc)
            live.predicate = NSPredicate(format: "cluster != YES")
            live.iconImageName = NSExpression(forKeyPath: "icon")
            live.iconAllowsOverlap = NSExpression(forConstantValue: false)
            live.iconPadding = NSExpression(forConstantValue: 2)
            live.iconScale = NSExpression(mglJSONObject: ["interpolate", ["linear"], ["zoom"], 6, 0.6, 9, 0.7, 13, 0.9, 16, 1.05])
            live.minimumZoomLevel = Float(LiveCams.webcamMinZoom)
            style.addLayer(live)
            Self.addGroupBubbles(style, source: liveSrc, id: "vela-livecams", ring: UIColor(hex: 0x3B82F6), minZoom: Float(LiveCams.webcamMinZoom))

            // Speed cameras and plate readers, from zoom 12 in.
            // Zoomed out over a busy city, cameras close together join into one bubble with a number.
            let camSrc = MLNShapeSource(identifier: "vela-cameras", shape: nil, options: Self.groupOptions)
            style.addSource(camSrc)
            let cams = MLNSymbolStyleLayer(identifier: "vela-cameras", source: camSrc)
            cams.predicate = NSPredicate(format: "cluster != YES")
            cams.iconImageName = NSExpression(forKeyPath: "icon")
            cams.iconAllowsOverlap = NSExpression(forConstantValue: true)
            // Big enough to notice at a glance, and bigger again for the ones on your route.
            // (Zoom has to be the outermost part of the expression, so the "on route" size goes inside each stop.)
            let big: [Any] = ["==", ["get", "big"], 1]
            cams.iconScale = NSExpression(mglJSONObject: ["interpolate", ["linear"], ["zoom"],
                                                          11, ["case", big, 1.0, 0.7],
                                                          14, ["case", big, 1.33, 0.92],
                                                          17, ["case", big, 1.65, 1.15]])
            // While driving, cameras off your route fade back (see renderCameras).
            cams.iconOpacity = NSExpression(mglJSONObject: ["coalesce", ["get", "op"], 1])
            cams.minimumZoomLevel = 11
            style.addLayer(cams)
            Self.addGroupBubbles(style, source: camSrc, id: "vela-cameras", ring: UIColor(hex: 0xFF8A00), minZoom: 11)

            // Waze: a glow where police get reported (under), and live reports as badges (over).
            let heatSrc = MLNShapeSource(identifier: "vela-waze-heat", shape: nil, options: nil)
            style.addSource(heatSrc)
            let heat = MLNHeatmapStyleLayer(identifier: "vela-waze-heat", source: heatSrc)
            heat.heatmapRadius = NSExpression(mglJSONObject: ["interpolate", ["linear"], ["zoom"], 6, 14, 10, 26, 14, 48, 17, 70])
            heat.heatmapIntensity = NSExpression(mglJSONObject: ["interpolate", ["linear"], ["zoom"], 6, 0.8, 14, 2.2])
            heat.heatmapOpacity = NSExpression(forConstantValue: 0.85)
            heat.heatmapColor = NSExpression(mglJSONObject: ["interpolate", ["linear"], ["heatmap-density"],
                                                             0, "rgba(0,0,0,0)", 0.15, "rgba(66,133,244,0.45)",
                                                             0.4, "rgba(124,77,255,0.65)", 0.7, "rgba(233,30,99,0.8)",
                                                             1, "rgba(213,0,0,0.9)"])
            heat.isVisible = false
            // Under the routes, cameras and road names, so the glow never hides them.
            if let under = style.layer(withIdentifier: "vela-route-alt-edge") { style.insertLayer(heat, below: under) } else { insert(heat) }
            let wazeSrc = MLNShapeSource(identifier: "vela-waze", shape: nil, options: nil)
            style.addSource(wazeSrc)
            let waze = MLNSymbolStyleLayer(identifier: "vela-waze", source: wazeSrc)
            waze.iconImageName = NSExpression(forKeyPath: "icon")
            waze.iconAllowsOverlap = NSExpression(forConstantValue: true)
            // Smaller when zoomed out, so a busy city doesn't drown in badges.
            waze.iconScale = NSExpression(mglJSONObject: ["interpolate", ["linear"], ["zoom"], 11, 0.62, 15, 0.95])
            waze.iconOpacity = NSExpression(forKeyPath: "op")
            waze.minimumZoomLevel = 11
            style.addLayer(waze)
            // Every other report (closures, hazards, jams) joins into numbered bubbles when zoomed
            // out, so a busy city stays readable. Police and crashes above always stay on their own.
            let groupSrc = MLNShapeSource(identifier: "vela-waze-group", shape: nil, options: Self.groupOptions)
            style.addSource(groupSrc)
            let group = MLNSymbolStyleLayer(identifier: "vela-waze-group", source: groupSrc)
            group.predicate = NSPredicate(format: "cluster != YES")
            group.iconImageName = NSExpression(forKeyPath: "icon")
            group.iconAllowsOverlap = NSExpression(forConstantValue: true)
            group.iconScale = waze.iconScale
            group.iconOpacity = NSExpression(forKeyPath: "op")
            group.minimumZoomLevel = 11
            style.insertLayer(group, below: waze)
            Self.addGroupBubbles(style, source: groupSrc, id: "vela-waze-group", ring: UIColor(hex: 0xEF4444), minZoom: 11)

            // My places: home, work, the parked car and saved places, under the result pins.
            let mineSrc = MLNShapeSource(identifier: "vela-mine", shape: nil, options: nil)
            style.addSource(mineSrc)
            let mine = MLNSymbolStyleLayer(identifier: "vela-mine", source: mineSrc)
            mine.iconImageName = NSExpression(forKeyPath: "icon")
            mine.iconAllowsOverlap = NSExpression(forConstantValue: true)
            mine.text = NSExpression(forKeyPath: "label")
            mine.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
            mine.textFontSize = NSExpression(forConstantValue: 11)
            mine.textAnchor = NSExpression(forConstantValue: "top")
            mine.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.1)))
            mine.textOptional = NSExpression(forConstantValue: true)
            mine.maximumTextWidth = NSExpression(forConstantValue: 8)
            mine.minimumZoomLevel = 9
            style.addLayer(mine)

            // Result pins with names, the picked place's red pin, the time bubbles and the puck.
            let results = MLNShapeSource(identifier: "vela-results", shape: nil, options: nil)
            style.addSource(results)
            let pins = MLNSymbolStyleLayer(identifier: "vela-results", source: results)
            pins.iconImageName = NSExpression(forKeyPath: "icon")
            pins.iconAllowsOverlap = NSExpression(forConstantValue: true)
            pins.text = NSExpression(forKeyPath: "label")
            pins.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
            pins.textFontSize = NSExpression(forConstantValue: 12)
            pins.textAnchor = NSExpression(forConstantValue: "left")
            pins.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 1.4, dy: 0)))
            pins.textOptional = NSExpression(forConstantValue: true)
            pins.maximumTextWidth = NSExpression(forConstantValue: 8)
            pins.textJustification = NSExpression(forConstantValue: "left")
            pins.symbolSortKey = NSExpression(forKeyPath: "rank")
            style.addLayer(pins)

            let selSrc = MLNShapeSource(identifier: "vela-selected", shape: nil, options: nil)
            style.addSource(selSrc)
            let sel = MLNSymbolStyleLayer(identifier: "vela-selected", source: selSrc)
            sel.iconImageName = NSExpression(forKeyPath: "icon")
            sel.iconAnchor = NSExpression(forKeyPath: "anchor")
            sel.iconAllowsOverlap = NSExpression(forConstantValue: true)
            sel.textAllowsOverlap = NSExpression(forConstantValue: false)
            sel.text = NSExpression(forKeyPath: "label")
            sel.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
            sel.textFontSize = NSExpression(forConstantValue: 13)
            sel.textAnchor = NSExpression(forConstantValue: "top")
            sel.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 0.4)))
            sel.textOptional = NSExpression(forConstantValue: true)
            style.addLayer(sel)

            let bubbleSrc = MLNShapeSource(identifier: "vela-route-bubbles", shape: nil, options: nil)
            style.addSource(bubbleSrc)
            for selected in [false, true] {
                let b = MLNSymbolStyleLayer(identifier: "vela-route-bubble-\(selected ? 1 : 0)", source: bubbleSrc)
                b.predicate = NSPredicate(format: "sel == %d", selected ? 1 : 0)
                b.iconImageName = NSExpression(forConstantValue: selected ? "bubble-sel" : "bubble-alt")
                b.iconTextFit = NSExpression(forConstantValue: "both")
                b.iconTextFitPadding = NSExpression(forConstantValue: NSValue(uiEdgeInsets: UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)))
                b.text = NSExpression(forKeyPath: "label")
                b.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
                b.textFontSize = NSExpression(forConstantValue: 15)
                b.textColor = NSExpression(forConstantValue: selected ? UIColor.white : UIColor(hex: 0x202124))
                b.iconAllowsOverlap = NSExpression(forConstantValue: true)
                b.textAllowsOverlap = NSExpression(forConstantValue: true)
                style.addLayer(b)
            }

            // The next turn drawn on the road while navigating, like Vela's turn arrows.
            let arrowSrc = MLNShapeSource(identifier: "vela-turn-arrow", shape: nil, options: nil)
            style.addSource(arrowSrc)
            // A big white arrow with a teal edge and a soft shadow, like Waze's, so it's clear at a glance.
            let arrowShadow = line("vela-turn-arrow-shadow", arrowSrc, .black, width: 22)
            arrowShadow.predicate = NSPredicate(format: "part == 'shaft'")
            arrowShadow.lineOpacity = NSExpression(forConstantValue: 0.35)
            arrowShadow.lineBlur = NSExpression(forConstantValue: 4)
            arrowShadow.lineTranslation = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 2)))
            let arrowEdge = line("vela-turn-arrow-edge", arrowSrc, UIColor(hex: 0x092853), width: 23)
            arrowEdge.predicate = NSPredicate(format: "part == 'shaft'")
            let arrowLine = line("vela-turn-arrow", arrowSrc, .white, width: 15)
            arrowLine.predicate = NSPredicate(format: "part == 'shaft'")
            let head = MLNSymbolStyleLayer(identifier: "vela-turn-arrow-head", source: arrowSrc)
            head.predicate = NSPredicate(format: "part == 'head'")
            head.iconImageName = NSExpression(forConstantValue: "turn-head")
            head.iconRotation = NSExpression(forKeyPath: "bearing")
            head.iconRotationAlignment = NSExpression(forConstantValue: "map")
            head.iconAllowsOverlap = NSExpression(forConstantValue: true)
            head.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            for l in [arrowShadow, arrowEdge, arrowLine] as [MLNStyleLayer] { style.addLayer(l) }
            style.addLayer(head)

            // The name of the road you're about to turn onto, lit up in a teal pill on the road itself.
            let nextRoadSrc = MLNShapeSource(identifier: "vela-next-road", shape: nil, options: nil)
            style.addSource(nextRoadSrc)
            let nextRoad = MLNSymbolStyleLayer(identifier: "vela-next-road", source: nextRoadSrc)
            nextRoad.iconImageName = NSExpression(forConstantValue: "road-pill")
            nextRoad.iconTextFit = NSExpression(forConstantValue: "both")
            nextRoad.iconTextFitPadding = NSExpression(forConstantValue: NSValue(uiEdgeInsets: UIEdgeInsets(top: 5, left: 11, bottom: 5, right: 11)))
            nextRoad.text = NSExpression(forKeyPath: "label")
            nextRoad.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
            nextRoad.textFontSize = NSExpression(forConstantValue: 16)
            nextRoad.textColor = NSExpression(forConstantValue: UIColor(hex: 0x06201C))
            nextRoad.iconAllowsOverlap = NSExpression(forConstantValue: true)
            nextRoad.textAllowsOverlap = NSExpression(forConstantValue: true)
            nextRoad.textPitchAlignment = NSExpression(forConstantValue: "viewport")
            style.addLayer(nextRoad)

            let puckSrc = MLNShapeSource(identifier: "vela-puck", shape: nil, options: nil)
            style.addSource(puckSrc)
            let puck = MLNSymbolStyleLayer(identifier: "vela-puck", source: puckSrc)
            puck.iconImageName = NSExpression(forConstantValue: "puck")
            puck.iconRotation = NSExpression(forKeyPath: "bearing")
            puck.iconRotationAlignment = NSExpression(forConstantValue: "map")
            puck.iconPitchAlignment = NSExpression(forConstantValue: "map")
            puck.iconAllowsOverlap = NSExpression(forConstantValue: true)
            // Always drawn, and it keeps the space it covers clear: no road number or name under the car.
            puck.iconIgnoresPlacement = NSExpression(forConstantValue: false)
            style.addLayer(puck)
        }

        /** How see-through cameras and reports off your route are while driving. */
        static let offRouteOpacity = 0.3

        /** The road a turn goes onto, for the pill on the map: "Stoneham Way" from "Turn left onto Stoneham Way". */
        static func nextRoadName(_ m: Maneuver) -> String? {
            // The sign's own destination is more useful than the street name on the tarmac.
            if let signed = m.exitSign?.destinations.first, !signed.isEmpty { return signed }
            if let reference = m.exitSign?.references.first, !reference.isEmpty { return reference }
            let text = SpokenText.forScreen(m.instruction)
            var name: String?
            if let r = text.range(of: " onto ", options: .backwards) {
                name = String(text[r.upperBound...])
            } else if let road = m.road, !road.isEmpty, text.contains(road) {
                name = SpokenText.forScreen(road)
            }
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
            guard let trimmed, !trimmed.isEmpty, trimmed.count <= 40 else { return nil }
            return trimmed
        }

        /** Line width by vehicle kind: a metro reads heavier than a tram, a bus lighter still. */
        private static func transitWidth(extra: Double) -> [Any] {
            func w(_ metro: Double, _ tram: Double, _ rail: Double, _ bus: Double, _ other: Double) -> [Any] {
                ["match", ["get", "mode"],
                 "metro", metro + extra, "subway", metro + extra,
                 "tram", tram + extra, "lightRail", tram + extra, "monorail", tram + extra,
                 "suburbanRail", rail + extra, "regionalTrain", rail + extra,
                 "longDistanceTrain", rail + extra, "highSpeedRail", rail + extra,
                 "bus", bus + extra, "trolleybus", bus + extra, "coach", bus + extra,
                 other + extra]
            }
            return w(5.2, 4.6, 4.2, 3.6, 3.2)
        }

        private func line(_ id: String, _ src: MLNSource, _ color: UIColor, width: Double) -> MLNLineStyleLayer {
            let l = MLNLineStyleLayer(identifier: id, source: src)
            l.lineColor = NSExpression(forConstantValue: color)
            l.lineWidth = NSExpression(forConstantValue: width)
            l.lineCap = NSExpression(forConstantValue: "round")
            l.lineJoin = NSExpression(forConstantValue: "round")
            return l
        }

        // MARK: Render

        private var showsTransitNetwork: Bool {
            TransitMapFilter.showsNetwork(enabled: model.settings.transitLines,
                                          hasActiveJourney: model.hasActiveJourney,
                                          hasRoutePreview: model.directions != nil)
        }

        func render(_ map: any KiteMapSurface) {
            guard model.map === map else { return }
            let s = model.settings
            let navigating = model.nav != nil
            // The native blue dot is hidden in the delegate; the teal arrow is drawn for browsing,
            // Just drive and navigation alike. User-location updates stay on for the first fix.
            if !map.showsUserLocation { map.showsUserLocation = true }
            if let libre = map as? MLNMapView {
                guard styleReady, let style = libre.style else { return }
                renderBase(style, navigating: navigating)
                updateHeat(libre)
            } else if let apple = map as? AppleMapSurface {
                apple.apply(settings: s, dark: dark, navigating: navigating,
                            showsRail: showsTransitNetwork)
            }
            renderResults()
            renderRoutes()
            renderTransitVehicles()
            renderPuck(map)
            loadJustDriveCameras(map)
            renderCameras()
            renderLiveCams(map)
            renderSignals()
            renderWaze()
            renderMine()
            if showsTransitNetwork {
                loadRail(map)
                if !railLines.isEmpty, publishedRailFilter != s.hiddenTransitCategories { publishRail() }
            } else if publishedRailFilter != nil {
                publish(nil, to: "vela-rail")
                publishedRailFilter = nil
            }
        }

        private func renderBase(_ style: MLNStyle, navigating: Bool) {
            let s = model.settings
            updateMapbox(style)
            let driving = model.nav?.route.mode == .drive || model.justDrive
            let effectivePreset: MapPreset = driving && s.mapPreset != .minimal ? .navigation : s.mapPreset
            if styledPreset != effectivePreset {
                MapStyler.preset(style, preset: effectivePreset)
                styledPreset = effectivePreset
            }
            let profile = MapPresetCatalog.profile(for: effectivePreset)
            (style.layer(withIdentifier: "vela-puck") as? MLNSymbolStyleLayer)?.iconScale =
                NSExpression(forConstantValue: s.navArrowScale)
            // Not before the welcome screen's choice: "Open data only" means nothing ever went to Google.
            style.layer(withIdentifier: "vela-traffic")?.isVisible = s.traffic && !s.noGoogle && s.welcomed
            style.layer(withIdentifier: "vela-sat")?.isVisible = s.satellite
            style.layer(withIdentifier: "vela-terrain")?.isVisible = s.terrain && !s.satellite
            for id in ["vela-rail", "vela-rail-case"] { style.layer(withIdentifier: id)?.isVisible = showsTransitNetwork }
            if styledDriving != driving {
                MapStyler.drive(style, on: driving)
                styledDriving = driving
                (style.layer(withIdentifier: "vela-route-line") as? MLNLineStyleLayer)?.lineWidth = NSExpression(forConstantValue: navigating ? 14 : 12)
                (style.layer(withIdentifier: "vela-route-edge") as? MLNLineStyleLayer)?.lineWidth = NSExpression(forConstantValue: navigating ? 18 : 16)
                (style.layer(withIdentifier: "vela-route-halo") as? MLNLineStyleLayer)?.lineWidth = NSExpression(forConstantValue: navigating ? 22 : 20)
            }
            // The map-style driving simplification must not silently remove buildings.
            // Keep the user's setting independent of the camera's 2D/3D pitch.
            let showBuildings = !s.satellite && profile.showBuildings && (!navigating || s.navBuildings)
            for id in ["building", "building-3d"] { style.layer(withIdentifier: id)?.isVisible = showBuildings }
            style.layer(withIdentifier: "building-3d")?.minimumZoomLevel =
                profile.show3DBuildings ? 14.5 : 22
            style.layer(withIdentifier: "vela-traffic")?.isVisible =
                s.traffic && !s.noGoogle && s.welcomed && profile.showTraffic
        }

        private func publish(_ shape: MLNShape?, to id: String) {
            if let libre = surface as? MLNMapView {
                (libre.style?.source(withIdentifier: id) as? MLNShapeSource)?.shape = shape
            } else if let apple = surface as? AppleMapSurface {
                apple.replaceFeatures(shape, source: id)
            }
        }

        private func renderMine() {
            let s = model.settings
            let hidden = model.directions != nil && !model.hasActiveJourney
            var items: [(Place, String, String)] = []
            if !hidden {
                if let h = s.home { items.append((h, "mine-home", "Home")) }
                if let w = s.work { items.append((w, "mine-work", "Work")) }
                if let p = s.parking { items.append((p, "mine-parking", "Parked car")) }
                for p in s.saved.prefix(200) where !items.contains(where: { $0.0.id == p.id }) { items.append((p, "mine-saved", p.name)) }
            }
            let selected = model.selected
            let sel = selected?.id
            // The label too, so a renamed place shows its new name.
            let key = items.map { $0.0.id + $0.1 + $0.2 }.joined(separator: ",") + "|" + (sel ?? "")
            guard key != lastMineKey else { return }
            lastMineKey = key
            let features: [MLNPointFeature] = items.compactMap { p, icon, label in
                guard !(selected.map { p.matchesNearby($0) } ?? false) else { return nil }
                let f = MLNPointFeature()
                f.coordinate = CLLocationCoordinate2D(latitude: p.location.lat, longitude: p.location.lng)
                f.attributes = ["id": p.id, "icon": icon, "label": label]
                return f
            }
            publish(MLNShapeCollectionFeature(shapes: features), to: "vela-mine")
        }

        private func renderCameras() {
            let s = model.settings
            let line = model.nav?.route.polyline ?? model.directions?.route?.polyline ?? []
            let waze = s.speedCameras && s.wazeOn
            // While driving, only what's on your way stands out: everything off the route fades back.
            let driving = model.nav?.route.mode == .drive
            let key = "\(s.speedCameras)\(s.plateCameras)\(s.surveillanceCameras)\(surveillance.count)\(cameras.count)\(line.count)\(line.first?.lat ?? 0)\(waze)\(WazeCameras.shared.version)\(driving)|\(model.justDrive)|\(driveCameraRevision)"
            guard key != lastCameraKey else { return }
            lastCameraKey = key
            var available = cameras
            if model.justDrive {
                for camera in nearbyDriveCameras { available[camera.id] = camera }
            }
            var shown = available.values.filter { $0.kind == .speed ? s.speedCameras : s.plateCameras }
            // Waze's speed cameras join OpenStreetMap's; one both maps hold shows once.
            if waze { shown = WazeCameras.merge(shown, waze: WazeCameras.shared.known()) }
            let cum = line.count >= 2 ? Geo.cumulative(line) : []
            var features: [MLNPointFeature] = shown.map { c in
                let f = MLNPointFeature()
                f.coordinate = CLLocationCoordinate2D(latitude: c.location.lat, longitude: c.location.lng)
                let onRoute = !cum.isEmpty && Geo.project(c.location, on: line, cumulative: cum).offset < 40
                f.attributes = ["icon": c.kind == .speed ? "cam-speed" : "cam-plate", "big": (onRoute || model.justDrive) ? 1 : 0, "op": driving && !onRoute ? Self.offRouteOpacity : 1,
                                "surveillanceId": c.kind == .plate ? String(c.id) : ""]
                return f
            }
            if s.surveillanceCameras {
                for camera in surveillance.values where !(camera.isALPR && s.plateCameras && cameras[camera.id] != nil) {
                    let f = MLNPointFeature()
                    f.coordinate = CLLocationCoordinate2D(latitude: camera.location.lat, longitude: camera.location.lng)
                    f.attributes = ["icon": camera.isALPR ? "cam-plate" : "cam-surveillance", "big": 0, "op": driving ? Self.offRouteOpacity : 1,
                                    "surveillanceId": String(camera.id)]
                    features.append(f)
                }
            }
            publish(MLNShapeCollectionFeature(shapes: features), to: "vela-cameras")
        }

        /** Live camera dots for what's on screen (plus a margin), never while driving. */
        private func renderLiveCams(_ map: any KiteMapSurface) {
            let s = model.settings
            let store = LiveCamStore.shared
            // Road cameras only from a city's zoom (there are thousands); webcams from a region's.
            let roadNow = s.showsRoadCams && map.zoomLevel >= LiveCams.roadMinZoom
            let webNow = s.showsWebcams && map.zoomLevel >= LiveCams.webcamMinZoom
            let on = model.nav == nil && (roadNow || webNow)
            let b = map.visibleCoordinateBounds
            let dLat = (b.ne.latitude - b.sw.latitude) * 0.25, dLng = (b.ne.longitude - b.sw.longitude) * 0.25
            // Redrawn when the list changes, or the map leaves the box drawn last time.
            let box = (s: b.sw.latitude - dLat, w: b.sw.longitude - dLng, n: b.ne.latitude + dLat, e: b.ne.longitude + dLng)
            let inside = liveBox.map { b.sw.latitude >= $0.s && b.ne.latitude <= $0.n && b.sw.longitude >= $0.w && b.ne.longitude <= $0.e } ?? false
            let key = "\(on)\(roadNow)\(webNow)\(store.version)"
            guard key != lastLiveKey || (on && !inside) else { return }
            lastLiveKey = key
            liveBox = on ? (box.s - dLat, box.w - dLng, box.n + dLat, box.e + dLng) : nil
            var features: [MLNPointFeature] = []
            if on, let lb = liveBox {
                for c in store.cams(south: lb.s, west: lb.w, north: lb.n, east: lb.e, road: roadNow, webcams: webNow) {
                    let f = MLNPointFeature()
                    f.coordinate = CLLocationCoordinate2D(latitude: c.location.lat, longitude: c.location.lng)
                    f.attributes = ["id": c.id, "icon": c.source.isRoad ? "livecam-road" : "livecam-web"]
                    features.append(f)
                }
            }
            publish(MLNShapeCollectionFeature(shapes: features), to: "vela-livecams")
        }

        /** The road camera list (once a day) and Windy's webcams around what's on screen. */
        func loadLiveCams(_ map: any KiteMapSurface) {
            let s = model.settings
            guard model.nav == nil, s.liveCams else { return }
            if s.showsRoadCams || s.liveCamsOnRoute { LiveCamStore.shared.ensureLoaded() }
            guard s.showsWebcams, map.zoomLevel >= LiveCams.webcamMinZoom else { return }
            let b = map.visibleCoordinateBounds
            let c = LatLng((b.sw.latitude + b.ne.latitude) / 2, (b.sw.longitude + b.ne.longitude) / 2)
            let span = LatLng(b.sw.latitude, b.sw.longitude).distance(to: LatLng(b.ne.latitude, b.ne.longitude)) / 1000
            LiveCamStore.shared.loadWindy(center: c, spanKm: span)
        }

        private func renderSignals() {
            let nav = model.nav
            let walking = nav?.route.mode == .walk ||
                (nav == nil && (model.directions?.route?.mode == .walk || model.transitJourney?.leg.isWalk == true))
            let cycling = nav?.route.mode == .bike
            let activity: MapActivity = nav != nil
                ? (walking ? .navigatingWalk : cycling ? .navigatingBike : .navigatingDrive)
                : (model.justDrive ? .freeDrive : .browsing)
            let here = nav?.progress?.snapped ?? model.userLatLng
            func shown(_ control: RouteControl, distance: Double?) -> Bool {
                ControlDisplayPolicy.shouldShow(control, activity: activity, distanceAhead: distance,
                                                directionCertain: control.directionCertain)
            }
            let controls: [RouteControl]?
            if let nav {
                // Route distance, not the crow's flight: a signal 40 m ahead along a bend is not
                // 8 m ahead, and one already passed must not come back.
                controls = nav.allUpcomingControls.compactMap { event in
                    shown(event.control, distance: event.meters) ? event.control : nil
                }
            } else {
                let source = nav == nil && model.hasActiveJourney
                    ? model.nearbyControls.filter { !model.justDrive || $0.kind.showsDuringDriving }
                    : (nav == nil ? model.previewCoverage?.events.map(\.control) : nil)
                controls = source?.filter { control in
                    shown(control, distance: here.map { $0.distance(to: control.location) })
                }
            }
            // Nearby OSM nodes do not identify the direction they control.
            let signals = nav?.route.mode != .drive && controls?.isEmpty != false
                ? (nav?.routeSignals ?? []).filter { signal in
                    guard let here else { return true }
                    return here.distance(to: signal) <= 350
                }
                : []
            guard controls != drawnControls || signals != drawnSignals else { return }
            drawnControls = controls
            drawnSignals = signals
            let landmarks = (controls ?? []).map { ($0.location, $0.kind.rawValue) } + signals.map { ($0, "traffic-light") }
            let features: [MLNPointFeature] = landmarks.map { point, icon in
                let feature = MLNPointFeature()
                feature.coordinate = CLLocationCoordinate2D(latitude: point.lat, longitude: point.lng)
                feature.attributes = ["icon": icon]
                return feature
            }
            publish(MLNShapeCollectionFeature(shapes: features), to: "vela-signals")
        }

        private func renderWaze() {
            let s = model.settings
            let history = WazeHistory.shared.sightings
            let kinds = s.wazeKinds.map(\.rawValue).sorted().joined()
            // While navigating, drivers' reports from Waze's app servers too (the live map has only closures).
            let live = model.nav?.liveAlerts ?? []
            // While driving, reports off your route fade back so the ones you'll meet stand out.
            let route = model.nav?.route.mode == .drive ? model.nav?.route.polyline ?? [] : []
            let key = "\(s.wazeOn)\(s.wazeOnMap)\(s.wazeHeatmap)\(s.wazeMaxAge)\(kinds)\(wazeAt.timeIntervalSince1970)\(history.count)\(live.map(\.id).joined())\(route.count)\(route.first?.lat ?? 0)"
            guard key != lastWazeKey else { return }
            lastWazeKey = key
            let ids = Set(wazeAlerts.map(\.id))
            let all = wazeAlerts + live.filter { !ids.contains($0.id) }
            let shown = s.wazeOn && s.wazeOnMap ? all.filter { s.shows($0) } : []
            let cum = route.count >= 2 ? Geo.cumulative(route) : []
            let feature: (WazeAlert) -> MLNPointFeature = { a in
                let f = MLNPointFeature()
                f.coordinate = CLLocationCoordinate2D(latitude: a.location.lat, longitude: a.location.lng)
                // Fresh reports solid, fading to half over two hours, like Highway Radar's.
                let age = Date().timeIntervalSince(a.reportedAt)
                var op = max(0.5, 1 - age / 14_400)
                if !cum.isEmpty, Geo.project(a.location, on: route, cumulative: cum).offset > 60 { op = Self.offRouteOpacity }
                f.attributes = ["id": a.id, "icon": "waze-\(a.kind.rawValue)", "op": op]
                return f
            }
            // Police and crashes matter most, so they never get grouped into a bubble.
            let alone = shown.filter { Self.neverGrouped.contains($0.kind) }
            let grouped = shown.filter { !Self.neverGrouped.contains($0.kind) }
            publish(MLNShapeCollectionFeature(shapes: alone.map(feature)), to: "vela-waze")
            publish(MLNShapeCollectionFeature(shapes: grouped.map(feature)), to: "vela-waze-group")
            // The heat map comes from Highway Radar's tiles now (see HighwayHeat), not from the
            // reports this phone has seen, which took a week of driving to fill.
            (surface as? MLNMapView)?.style?.layer(withIdentifier: "vela-waze-heat")?.isVisible = false
        }

        /** Highway Radar's police heat map for what's on screen, when it's switched on. */
        func updateHeat(_ map: MLNMapView) {
            let s = model.settings
            heatTiles.update(map, on: styleReady && s.wazeOn && s.wazeHeatmap && s.wazePolice, below: "vela-waze-heat")
        }

        /** Live Waze reports for the view and a margin, asked again after two minutes or when the map leaves the box. */
        func loadWaze(_ map: any KiteMapSurface) {
            let s = model.settings
            if s.wazeOn, s.wazeHeatmap || s.policeRisk, !DemoScript.active {
                var places: [LatLng] = []
                // Only around where you are: Waze is never asked about saved Home and Work.
                if let c = map.locationCoordinate, CLLocationCoordinate2DIsValid(c) { places.append(LatLng(c.latitude, c.longitude)) }
                WazeHistory.shared.sweepIfDue(places)
            }
            guard s.wazeOn, s.wazeOnMap || s.wazeHeatmap, map.zoomLevel >= 10, wazeFetch == nil, !DemoScript.fakeWaze,
                  Date().timeIntervalSince(wazeFailedAt) > 60 else { return }
            // Never more than every 5 s, and while navigating (the map moving all the time) every 90 s:
            // a London drive asked about 45 times in 6 minutes. Held back, it asks once the time is up.
            let wait = (model.nav != nil ? 90 : 5) - Date().timeIntervalSince(wazeAskedAt)
            if wait > 0 {
                if !wazeRetryQueued {
                    wazeRetryQueued = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + wait + 0.1) { [weak self, weak map] in
                        self?.wazeRetryQueued = false
                        if let self, let map { self.loadWaze(map) }
                    }
                }
                return
            }
            let b = map.visibleCoordinateBounds
            if let r = wazeBox, b.sw.latitude >= r.s, b.sw.longitude >= r.w, b.ne.latitude <= r.n, b.ne.longitude <= r.e,
               Date().timeIntervalSince(wazeAt) < 120 { return }
            let dLat = (b.ne.latitude - b.sw.latitude) * 0.3, dLng = (b.ne.longitude - b.sw.longitude) * 0.3
            let box = (s: b.sw.latitude - dLat, w: b.sw.longitude - dLng, n: b.ne.latitude + dLat, e: b.ne.longitude + dLng)
            guard box.n - box.s < 1.5, box.e - box.w < 2.5 else { return }
            // Drivers' reports (police, crashes, hazards) come from Waze's app servers, as on a drive:
            // the live map only has closures now. Not while navigating, which asks along the route
            // itself every 90 seconds, so Waze isn't asked twice. A box no bigger than the Waze app's
            // own view at a wide zoom, around the middle of the screen.
            let mid = LatLng((b.ne.latitude + b.sw.latitude) / 2, (b.ne.longitude + b.sw.longitude) / 2)
            let hLat = min((box.n - box.s) / 2, 0.15), hLng = min((box.e - box.w) / 2, 0.25)
            let liveBox = (s: mid.lat - hLat, w: mid.lng - hLng, n: mid.lat + hLat, e: mid.lng + hLng)
            let askLive = model.nav == nil && !DemoScript.active
            wazeAskedAt = Date()
            wazeFetch = Task { [weak self, weak map] in
                async let closures = Waze.alerts(south: box.s, west: box.w, north: box.n, east: box.e)
                let live = askLive ? await WazeLive.shared.alerts(boxes: [liveBox], near: mid) : nil
                let fromMap = await closures
                guard let self else { return }
                self.wazeFetch = nil
                guard fromMap != nil || live != nil else { self.wazeFailedAt = Date(); return }
                var merged: [String: WazeAlert] = [:]
                for a in (fromMap ?? []) + (live ?? []) { merged[a.id] = a }
                let found = Array(merged.values)
                Self.trace.info("waze browse: live map \(fromMap.map { String($0.count) } ?? "failed", privacy: .public), drivers' reports \(askLive ? (live.map { String($0.count) } ?? "failed") : "not asked", privacy: .public)")
                self.wazeAlerts = found
                // Asked again once the map leaves the part drivers' reports were asked for.
                self.wazeBox = live != nil ? liveBox : box
                self.wazeAt = Date()
                WazeHistory.shared.record(found)
                self.model.wazeLiveCount = found.filter { self.model.settings.shows($0) }.count
                self.model.updateAreaRisk(live: found, liveAvailable: live != nil)
                if let map { self.render(map) }
            }
        }

        /** For the build's screenshots: made-up reports, so the badges and glow show without Waze. */
        func showDemoWaze(_ list: [WazeAlert], map: MLNMapView) {
            wazeAlerts = list
            wazeAt = Date()
            model.wazeLiveCount = list.count
            model.updateAreaRisk(live: list)
            render(map)
        }

        /** Transit lines for the view and a margin around it, when the layer is on. */
        func loadRail(_ map: any KiteMapSurface) {
            guard model.map === map, showsTransitNetwork, map.zoomLevel >= 10, railFetch == nil else { return }
            let b = map.visibleCoordinateBounds
            let z = Int(map.zoomLevel)
            if let r = railBox, b.sw.latitude >= r.s, b.sw.longitude >= r.w, b.ne.latitude <= r.n, b.ne.longitude <= r.e,
               abs(z - r.z) <= 2 { return }
            let dLat = (b.ne.latitude - b.sw.latitude) * 0.5, dLng = (b.ne.longitude - b.sw.longitude) * 0.5
            let box = (s: b.sw.latitude - dLat, w: b.sw.longitude - dLng, n: b.ne.latitude + dLat, e: b.ne.longitude + dLng, z: z)
            railFetch = Task { [weak self, weak map] in
                let lines = await Transitous.lines(south: box.s, west: box.w, north: box.n, east: box.e, zoom: min(z, 14))
                guard let self else { return }
                self.railFetch = nil
                if let lines {
                    self.railBox = box
                    self.railLines = lines
                    self.publishRail()
                }
                // The map may have moved on while this was loading.
                if lines != nil, let map { self.loadRail(map) }
            }
        }

        /// The fetched lines minus the kinds the user hid (a line the active journey uses is never hidden).
        private func publishRail() {
            guard showsTransitNetwork, let surface, model.map === surface else { return }
            let hidden = model.settings.hiddenTransitCategories
            let shapes = railLines.filter { TransitMapFilter.shows($0.mode, hidden: hidden) }.map { l in
                polyline(l.points, ["color": String(format: "#%06X", l.color),
                                    "offset": l.offset, "mode": l.mode.rawValue])
            }
            publish(MLNShapeCollectionFeature(shapes: shapes), to: "vela-rail")
            publishedRailFilter = hidden
        }

        /** Separate OSM surveillance layer, opt-in; bounded to the same cells as camera lookups. */
        func loadSurveillance(_ map: any KiteMapSurface) {
            guard model.settings.surveillanceCameras, map.zoomLevel >= 12, surveillanceFetch == nil else { return }
            let b = map.visibleCoordinateBounds, cell = 0.1
            let y0 = Int(floor(b.sw.latitude / cell)), y1 = Int(floor(b.ne.latitude / cell))
            let x0 = Int(floor(b.sw.longitude / cell)), x1 = Int(floor(b.ne.longitude / cell))
            guard y1 >= y0, x1 >= x0, (y1 - y0 + 1) * (x1 - x0 + 1) <= 12 else { return }
            var missing: [(Int, Int)] = []
            for y in y0...y1 { for x in x0...x1 where !surveillanceCells.contains("\(y),\(x)") { missing.append((y, x)) } }
            guard !missing.isEmpty else { return }
            let ys = missing.map(\.0), xs = missing.map(\.1)
            surveillanceFetch = Task { [weak self, weak map] in
                let found = await SurveillanceCameras.inBox(south: Double(ys.min()!) * cell, west: Double(xs.min()!) * cell,
                    north: Double(ys.max()! + 1) * cell, east: Double(xs.max()! + 1) * cell)
                guard let self else { return }
                self.surveillanceFetch = nil
                guard let found else {
                    // A busy server: try again in 30 s, not only when the map is next moved.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self, weak map] in
                        if let self, let map { self.loadSurveillance(map) }
                    }
                    return
                }
                for (y, x) in missing { self.surveillanceCells.insert("\(y),\(x)") }
                for c in found { self.surveillance[c.id] = c }
                if let map { self.render(map); self.loadSurveillance(map) }
            }
        }

        private func loadJustDriveCameras(_ map: any KiteMapSurface) {
            guard model.justDrive else {
                if driveCameraFetch != nil || driveCameraCenter != nil {
                    driveCameraFetch?.cancel()
                    driveCameraFetch = nil
                    driveCameraCenter = nil
                    driveCameraAttempt = .distantPast
                    nearbyDriveCameras = []
                    driveCameraRevision += 1
                }
                return
            }
            let settings = model.settings
            guard settings.speedCameras || settings.plateCameras,
                  let point = model.userLatLng, abs(point.lat) < 85,
                  driveCameraFetch == nil, Date().timeIntervalSince(driveCameraAttempt) > 25,
                  driveCameraCenter.map({ point.distance(to: $0) > 1_400 }) ?? true else { return }
            driveCameraAttempt = Date()
            let dy = 0.035, dx = dy / cos(point.lat * .pi / 180)
            let south = point.lat - dy, north = point.lat + dy
            let west = max(-180, point.lng - dx), east = min(180, point.lng + dx)
            let useWaze = settings.speedCameras && settings.wazeOn
            driveCameraFetch = Task { [weak self, weak map] in
                async let cameras = Overpass.cameras(south: south, west: west, north: north, east: east, speed: true, plate: true)
                if useWaze { _ = await WazeCameras.load(south: south, west: west, north: north, east: east) }
                let fresh = await cameras
                guard let self, !Task.isCancelled else { return }
                self.driveCameraFetch = nil
                if let fresh {
                    self.driveCameraCenter = point
                    self.nearbyDriveCameras = fresh
                    self.driveCameraRevision += 1
                }
                if let map { self.render(map) }
            }
        }

        /** Ask Overpass for the cameras in view, a few 0.1° cells at a time, each cell once. */
        func loadCameras(_ map: any KiteMapSurface) {
            let s = model.settings
            guard s.speedCameras || s.plateCameras, map.zoomLevel >= 12, cameraFetch == nil else { return }
            let b = map.visibleCoordinateBounds
            let cell = 0.1
            let y0 = Int(floor(b.sw.latitude / cell)), y1 = Int(floor(b.ne.latitude / cell))
            let x0 = Int(floor(b.sw.longitude / cell)), x1 = Int(floor(b.ne.longitude / cell))
            guard y1 >= y0, x1 >= x0, (y1 - y0 + 1) * (x1 - x0 + 1) <= 12 else { return }
            var missing: [(Int, Int)] = []
            for y in y0...y1 { for x in x0...x1 where !cameraCells.contains("\(y),\(x)") { missing.append((y, x)) } }
            guard !missing.isEmpty else { return }
            let ys = missing.map(\.0), xs = missing.map(\.1)
            let south = Double(ys.min()!) * cell, north = Double(ys.max()! + 1) * cell
            let west = Double(xs.min()!) * cell, east = Double(xs.max()! + 1) * cell
            cameraFetch = Task { [weak self, weak map] in
                // Both kinds every time, so turning one on later needs no new fetch.
                let found = await Overpass.cameras(south: south, west: west, north: north, east: east, speed: true, plate: true)
                guard let self, let map else { return }
                self.cameraFetch = nil
                guard let found else {
                    // A busy server: try again in 30 s, not only when the map is next moved.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self, weak map] in
                        if let self, let map { self.loadCameras(map) }
                    }
                    return
                }
                for (y, x) in missing { self.cameraCells.insert("\(y),\(x)") }
                for c in found { self.cameras[c.id] = c }
                self.render(map)
                // The map may have moved on while this one was loading.
                self.loadCameras(map)
            }
        }

        /** Waze's speed cameras for what's on screen, once zoomed in to a town; each piece of its map once a week. */
        func loadWazeCameras(_ map: any KiteMapSurface) {
            let s = model.settings
            WazeCameras.enabled = s.wazeOn
            guard s.speedCameras, s.wazeOn, map.zoomLevel >= 13, wazeCameraFetch == nil else { return }
            let b = map.visibleCoordinateBounds
            wazeCameraFetch = Task { [weak self, weak map] in
                let fresh = await WazeCameras.load(south: b.sw.latitude, west: b.sw.longitude, north: b.ne.latitude, east: b.ne.longitude)
                guard let self else { return }
                self.wazeCameraFetch = nil
                if fresh, let map { self.render(map) }
            }
        }

        private func renderResults() {
            let showList = model.directions == nil && model.nav == nil && model.transitJourney == nil && !model.justDrive
            let list = showList ? model.visibleResults + model.transitMapStops : []
            let target = model.transitJourney?.destination ?? model.nav?.destination ?? model.directions?.toPlace ?? model.selected
            let stops: [Place] = model.transitJourney?.stops ?? model.nav?.stops ?? model.directions?.stops ?? []
            let ids: String = list.map { "\($0.id):\($0.placeId ?? "")" }.joined(separator: ",")
            let entrance = model.nav?.destinationEntrance
            let entranceKey = entrance.map { "\($0.lat),\($0.lng)" } ?? ""
            let stopIds: String = stops.map(\.id).joined(separator: ",")
            let origin = model.nav == nil ? model.directions.flatMap { $0.fromPlace?.location ?? model.userLatLng } : nil
            let key = "\(ids)|\(target?.id ?? "")|\(origin?.lat ?? 0)|\(origin?.lng ?? 0)|\(model.nav == nil)|\(stopIds)|\(entranceKey)"
            guard key != lastResultsKey else { return }
            lastResultsKey = key
            let features: [MLNPointFeature] = list.enumerated().compactMap { i, p in
                guard p.id != target?.id else { return nil }
                let f = MLNPointFeature()
                f.coordinate = CLLocationCoordinate2D(latitude: p.location.lat, longitude: p.location.lng)
                let rating = p.rating.map { String(format: "%.1f", $0) }
                f.attributes = [
                    "id": p.id,
                    "icon": MapIcons.iconName(for: p),
                    "label": [p.name, rating].compactMap { $0 }.joined(separator: "\n"),
                    "rank": i,
                    "transitStop": p.source == "transitous",
                ]
                return f
            }
            publish(MLNShapeCollectionFeature(shapes: features), to: "vela-results")

            var sel: [MLNPointFeature] = []
            if let t = target {
                let f = MLNPointFeature()
                f.coordinate = CLLocationCoordinate2D(latitude: t.location.lat, longitude: t.location.lng)
                f.attributes = ["id": t.id, "icon": "pin-selected", "anchor": "bottom", "label": t.name]
                sel.append(f)
                for (i, stop) in stops.enumerated() {
                    let f = MLNPointFeature()
                    f.coordinate = CLLocationCoordinate2D(latitude: stop.location.lat, longitude: stop.location.lng)
                    f.attributes = ["id": "stop\(i)", "icon": "pin-stop", "anchor": "center", "label": stop.name]
                    sel.append(f)
                }
                if let me = origin {
                    let o = MLNPointFeature()
                    o.coordinate = CLLocationCoordinate2D(latitude: me.lat, longitude: me.lng)
                    o.attributes = ["id": "origin", "icon": "pin-origin", "anchor": "center", "label": ""]
                    sel.append(o)
                }
            }
            if let entrance {
                let feature = MLNPointFeature()
                feature.coordinate = CLLocationCoordinate2D(latitude: entrance.lat, longitude: entrance.lng)
                feature.attributes = ["id": "destination-entrance", "icon": "pin-stop", "anchor": "center", "label": L10n.text("Main entrance")]
                sel.append(feature)
            }
            publish(MLNShapeCollectionFeature(shapes: sel), to: "vela-selected")
        }

        func polyline(_ pts: [LatLng], _ attrs: [String: Any] = [:]) -> MLNPolylineFeature {
            var coords = pts.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
            let f = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
            f.attributes = attrs
            return f
        }

        private func renderRoutes() {
            var alts: [Route] = []
            var main: Route?
            var from = 0.0
            if let n = model.nav {
                main = n.route
                from = n.progress?.alongMeters ?? 0
            } else if !model.justDrive, model.transitJourney == nil, let d = model.directions {
                main = d.route
                alts = d.current.filter { $0.id != main?.id }
            }
            let journey = model.transitJourney
            let trip = journey?.trip ?? (model.nav == nil && !model.justDrive ? model.directions?.pickedTrip : nil)
            let preset = model.settings.mapPreset
            let effectivePreset: MapPreset = model.nav?.route.mode == .drive && preset != .minimal ? .navigation : preset
            let showsRouteTraffic = main?.mode == .drive && model.settings.traffic
                && (surface is AppleMapSurface || MapPresetCatalog.profile(for: effectivePreset).showTraffic)
            let trafficKey = showsRouteTraffic ? main?.trafficSpans.hashValue : nil
            let firstLeg = journey?.index ?? 0
            let key = (model.nav == nil ? "" : "nav") + (trip?.id.uuidString ?? "") + (main?.id.uuidString ?? "") + alts.map(\.id.uuidString).joined() + "|\(firstLeg)|\(Int(from / 5))|\(trafficKey.map(String.init) ?? "-")"
            guard key != lastRouteKey else { return }
            lastRouteKey = key


            publish(MLNShapeCollectionFeature(shapes: alts.map { polyline($0.polyline) }), to: "vela-route-alt")
            publish(trip.map { t in
                let lines: [MLNPolylineFeature] = t.legs.enumerated().compactMap { index, leg in
                    guard leg.path.count >= 2 else { return nil }
                    if journey != nil, index == firstLeg, leg.isWalk, main?.mode == .walk { return nil }
                    let phase = journey == nil ? "preview" : index < firstLeg ? "done" : index == firstLeg ? "active" : "upcoming"
                    return polyline(leg.path, ["walk": leg.isWalk ? 1 : 0,
                                               "color": String(format: "#%06X", leg.identity.color),
                                               "mode": leg.identity.mode.rawValue, "phase": phase])
                }
                return MLNShapeCollectionFeature(shapes: lines)
            }, to: "vela-transit")
            guard let r = main else {
                publish(nil, to: "vela-route"); publish(nil, to: "vela-route-traffic"); publish(nil, to: "vela-route-bubbles")
                publish(nil, to: "vela-route-done")
                publish(nil, to: "vela-turn-arrow")
                publish(nil, to: "vela-next-road")
                return
            }
            let cum = Geo.cumulative(r.polyline)
            let total = cum.last ?? 0
            let ahead = from > 1 ? Geo.slice(r.polyline, from: from, to: total, cumulative: cum) : r.polyline
            publish(ahead.count >= 2 ? polyline(ahead) : nil, to: "vela-route")
            let driven = model.nav != nil && from > 1 ? Geo.slice(r.polyline, from: 0, to: from, cumulative: cum) : []
            publish(driven.count >= 2 ? polyline(driven) : nil, to: "vela-route-done")
            let spans: [MLNPolylineFeature] = (showsRouteTraffic ? r.trafficSpans : []).compactMap { s in
                let a = max(s.startMeters, from), b = min(s.startMeters + s.lengthMeters, total)
                guard b > a else { return nil }
                let piece = Geo.slice(r.polyline, from: a, to: b, cumulative: cum)
                return piece.count >= 2 ? polyline(piece, ["level": min(s.level, 3)]) : nil
            }
            publish(MLNShapeCollectionFeature(shapes: spans), to: "vela-route-traffic")

            // Turn arrow: 50 m of road before the next turn and 40 m into the new road, from 600 m away.
            if let n = model.nav, let m = n.nextManeuver, m.type != .arrive, m.type != .depart, m.type != .straight,
               let p = n.progress, m.alongMeters - p.alongMeters < 600 {
                // At a roundabout, all the way round to your exit and a little beyond, like Waze.
                var end = m.alongMeters + 40
                if m.type == .roundabout,
                   let out = n.route.maneuvers.first(where: { $0.leavesRoundabout && $0.alongMeters > m.alongMeters }),
                   out.alongMeters - m.alongMeters < 250 {
                    end = out.alongMeters + 40
                }
                let a = max(m.alongMeters - 50, from), b = min(end, total)
                let shaft = Geo.slice(r.polyline, from: a, to: b, cumulative: cum)
                if shaft.count >= 2 {
                    let tip = shaft[shaft.count - 1], prev = Geo.point(along: r.polyline, meters: max(a, b - 4), cumulative: cum)
                    let head = MLNPointFeature()
                    head.coordinate = CLLocationCoordinate2D(latitude: tip.lat, longitude: tip.lng)
                    head.attributes = ["part": "head", "bearing": Geo.bearing(prev, tip)]
                    publish(MLNShapeCollectionFeature(shapes: [polyline(shaft, ["part": "shaft"]), head]), to: "vela-turn-arrow")
                } else {
                    publish(nil, to: "vela-turn-arrow")
                }
                // The new road's name, a little way into it, clear of the arrow head.
                if let name = Self.nextRoadName(m) {
                    let at = Geo.point(along: r.polyline, meters: min(end + 55, total), cumulative: cum)
                    let f = MLNPointFeature()
                    f.coordinate = CLLocationCoordinate2D(latitude: at.lat, longitude: at.lng)
                    f.attributes = ["label": name]
                    publish(f, to: "vela-next-road")
                } else {
                    publish(nil, to: "vela-next-road")
                }
            } else {
                publish(nil, to: "vela-turn-arrow")
                publish(nil, to: "vela-next-road")
            }

            // Time bubbles: on each route, at a point the others don't share.
            guard model.nav == nil, let d = model.directions else { publish(nil, to: "vela-route-bubbles"); return }
            var bubbles: [MLNPointFeature] = []
            for (i, route) in d.current.enumerated() {
                let others = d.current.enumerated().filter { $0.offset != i }.map(\.element.polyline)
                let c = Geo.cumulative(route.polyline)
                let len = c.last ?? 0
                var spot = Geo.point(along: route.polyline, meters: len * 0.5, cumulative: c)
                for f in stride(from: 0.5, through: 0.9, by: 0.1) {
                    let p = Geo.point(along: route.polyline, meters: len * f, cumulative: c)
                    let shared = others.contains { o in o.contains { $0.distance(to: p) < 120 } }
                    if !shared { spot = p; break }
                }
                let f = MLNPointFeature()
                f.coordinate = CLLocationCoordinate2D(latitude: spot.lat, longitude: spot.lng)
                f.attributes = ["label": Fmt.duration(route.durationSeconds), "sel": route.id == r.id ? 1 : 0, "idx": i]
                bubbles.append(f)
            }
            publish(MLNShapeCollectionFeature(shapes: bubbles), to: "vela-route-bubbles")
        }

        /** While navigating, NavGlide draws the arrow every frame; this only clears it afterwards. */
        private func updateMapbox(_ style: MLNStyle) {
            let settings = model.settings
            let token = settings.useMapbox && !settings.satellite ? settings.mapboxToken : ""
            let theme = dark ? "navigation-night-v1" : "streets-v12"
            let key = token.isEmpty ? "" : theme + token
            guard appliedMapboxKey != key else { return }
            if let layer = style.layer(withIdentifier: "vela-mapbox") { style.removeLayer(layer) }
            if let source = style.source(withIdentifier: "vela-mapbox") { style.removeSource(source) }
            appliedMapboxKey = key
            guard !token.isEmpty else { return }
            let template = "https://api.mapbox.com/styles/v1/mapbox/\(theme)/tiles/256/{z}/{x}/{y}@2x?access_token=\(token)"
            let source = MLNRasterTileSource(identifier: "vela-mapbox", tileURLTemplates: [template],
                options: [.tileSize: 256, .maximumZoomLevel: 22,
                          .attributionHTMLString: "<a href='https://www.mapbox.com/about/maps/'>© Mapbox</a> · <a href='https://www.openstreetmap.org/copyright'>© OpenStreetMap</a> · <a href='https://apps.mapbox.com/feedback/'>Improve this map</a>"])
            style.addSource(source)
            let layer = MLNRasterStyleLayer(identifier: "vela-mapbox", source: source)
            if let under = style.layer(withIdentifier: "building-3d") ?? style.layer(withIdentifier: "vela-route-alt-edge") { style.insertLayer(layer, below: under) }
            else { style.addLayer(layer) }
        }

        /** Vehicles reported live by an optional GTFS-Realtime feed, on the active transit trip. */
        private func renderTransitVehicles() {
            let leg: TransitLeg?
            if model.nav == nil, !model.justDrive, let journey = model.transitJourney,
               journey.trip.legs.indices.contains(journey.index) {
                leg = journey.trip.legs[journey.index]
            } else {
                leg = nil
            }
            let features: [MLNPointFeature] = [leg].compactMap { leg in
                guard let leg, let vehicle = leg.liveVehicle, let stamp = vehicle.updated,
                      (-30...120).contains(Date().timeIntervalSince(stamp)) else { return nil }
                let f = MLNPointFeature()
                f.coordinate = CLLocationCoordinate2D(latitude: vehicle.location.lat, longitude: vehicle.location.lng)
                f.attributes = ["icon": "transit-\(leg.identity.mode.rawValue)", "label": leg.line]
                return f
            }
            let key = features.map {
                "\($0.coordinate.latitude),\($0.coordinate.longitude),\(($0.attributes["label"] as? String) ?? "")"
            }.joined()
            guard key != lastTransitVehicleKey else { return }
            lastTransitVehicleKey = key
            publish(features.isEmpty ? nil : MLNShapeCollectionFeature(shapes: features), to: "vela-transit-vehicle")
        }

        private func renderPuck(_ map: any KiteMapSurface) {
            // Navigation and Just drive move the arrow every frame from NavGlide/DriveRoad.
            if model.nav != nil { lastPuckKey = "nav"; return }
            if model.justDrive, let coordinate = model.driveCoordinate {
                let key = "\(coordinate.latitude),\(coordinate.longitude),\(model.driveBearing)"
                guard key != lastPuckKey else { return }
                map.drawPuck(at: coordinate, bearing: model.driveBearing)
                lastPuckKey = key
                return
            }
            // Browsing: the same arrow, pointing the way the phone/car is facing, replacing the dot.
            guard let loc = model.location.last else {
                guard lastPuckKey != "" else { return }
                map.drawPuck(at: nil, bearing: 0)
                lastPuckKey = ""
                return
            }
            let bearing = model.mapBearing(for: loc)
            let key = String(format: "%.5f,%.5f,%.0f", loc.coordinate.latitude, loc.coordinate.longitude, bearing)
            guard key != lastPuckKey else { return }
            map.drawPuck(at: loc.coordinate, bearing: bearing)
            lastPuckKey = key
        }

        // MARK: Gestures

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let map = g.view as? MLNMapView, model.endpointOnMap == nil,
                  Date().timeIntervalSince(pinDroppedAt) > 1 else { return }
            let pt = g.location(in: map)
            let box = CGRect(x: pt.x - 22, y: pt.y - 22, width: 44, height: 44)
            Task { @MainActor in
                if self.model.directions != nil && !self.model.hasActiveJourney {
                    let hits = map.visibleFeatures(in: box, styleLayerIdentifiers: ["vela-route-bubble-0", "vela-route-alt", "vela-route-alt-edge"])
                    if let idx = hits.first?.attribute(forKey: "idx") as? Int {
                        self.model.selectRoute(idx)
                        return
                    }
                    if let line = hits.first(where: { $0 is MLNPolylineFeature }) as? MLNPolylineFeature,
                       let d = self.model.directions {
                        let c = line.coordinate
                        let tapped = LatLng(c.latitude, c.longitude)
                        if let i = d.current.firstIndex(where: { r in r.id != d.route?.id && r.polyline.contains { $0.distance(to: tapped) < 300 } }) {
                            self.model.selectRoute(i)
                        }
                    }
                    return
                }
                // Police and crashes sit on top and never join a bubble: a tap that touches one opens it,
                // even with a bubble right next to it.
                let alone = map.visibleFeatures(in: box, styleLayerIdentifiers: ["vela-waze"])
                if let id = alone.first?.attribute(forKey: "id") as? String,
                   let a = self.wazeAlerts.first(where: { $0.id == id }) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    self.model.wazeInfo = a
                    return
                }
                // A numbered bubble: zoom in until it splits into its icons.
                let bubbles = map.visibleFeatures(in: box, styleLayerIdentifiers: ["vela-waze-group-bubble", "vela-cameras-bubble", "vela-livecams-bubble"])
                if let b = bubbles.first {
                    map.setCenter(b.coordinate, zoomLevel: min(map.zoomLevel + 2, 15), animated: true)
                    return
                }
                let reports = map.visibleFeatures(in: box, styleLayerIdentifiers: ["vela-waze-group"])
                if let id = reports.first?.attribute(forKey: "id") as? String,
                   let a = self.wazeAlerts.first(where: { $0.id == id }) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    self.model.wazeInfo = a
                    return
                }
                let live = map.visibleFeatures(in: box, styleLayerIdentifiers: ["vela-livecams"])
                if let id = live.first?.attribute(forKey: "id") as? String, let cam = LiveCamStore.shared.cam(id) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    self.model.liveCamRoute = []
                    self.model.liveCam = cam
                    return
                }
                let cameraHits = map.visibleFeatures(in: box, styleLayerIdentifiers: ["vela-cameras"])
                if let id = cameraHits.first?.attribute(forKey: "surveillanceId") as? String,
                   let numericID = Int64(id), let camera = self.surveillance[numericID] {
                    self.model.surveillanceInfo = camera
                    return
                }
                let mine = map.visibleFeatures(in: box, styleLayerIdentifiers: ["vela-mine"])
                if let id = mine.first?.attribute(forKey: "id") as? String, let place = self.model.myPlace(id) {
                    self.model.select(place)
                    return
                }
                let pins = map.visibleFeatures(in: box, styleLayerIdentifiers: ["vela-results"])
                if let id = pins.first?.attribute(forKey: "id") as? String, self.model.selectMapResult(id) {
                    return
                }
                let styleIDs = Set(map.style?.layers.compactMap { layer -> String? in
                    let id = layer.identifier
                    return id.hasPrefix("poi_") || id == "airport" || id.hasPrefix("housenumber") ? id : nil
                } ?? [])
                let pois = styleIDs.isEmpty ? [] : map.visibleFeatures(in: box, styleLayerIdentifiers: styleIDs)
                if let poi = pois.first(where: { $0.attribute(forKey: "name") is String || $0.attribute(forKey: "name:en") is String }),
                   let name = (poi.attribute(forKey: "name") ?? poi.attribute(forKey: "name:en")) as? String {
                    let c = poi.coordinate
                    self.model.resolveTapped(name: name, at: LatLng(c.latitude, c.longitude))
                    return
                }
                let buildings = map.visibleFeatures(in: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4),
                                                     styleLayerIdentifiers: ["building", "building-3d"])
                if let building = buildings.first {
                    let c = map.convert(pt, toCoordinateFrom: map)
                    let point = LatLng(c.latitude, c.longitude)
                    if let name = building.attribute(forKey: "name") as? String { self.model.resolveTapped(name: name, at: point) }
                    else { self.model.dropPin(at: point, name: "Building", focus: false) }
                    return
                }
                if self.model.selected != nil {
                    self.model.closePlace()
                } else if !self.model.results.isEmpty {
                    self.model.detent = .peek
                }
            }
        }

        func selectOverlay(_ point: MLNPointFeature, source: String) {
            let id = point.attributes["id"] as? String
            switch source {
            case "vela-route-bubbles":
                if let idx = point.attributes["idx"] as? Int { model.selectRoute(idx) }
            case "vela-waze", "vela-waze-group":
                if let alert = wazeAlerts.first(where: { $0.id == id }) ?? model.nav?.liveAlerts.first(where: { $0.id == id }) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    model.wazeInfo = alert
                }
            case "vela-livecams":
                if let id, let cam = LiveCamStore.shared.cam(id) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    model.liveCamRoute = []
                    model.liveCam = cam
                }
            case "vela-cameras":
                if let id = point.attributes["surveillanceId"] as? String, let numericID = Int64(id) {
                    model.surveillanceInfo = surveillance[numericID]
                }
            case "vela-mine":
                if let id, let place = model.myPlace(id) { model.select(place) }
            case "vela-results":
                if let id { model.selectMapResult(id) }
            default: break
            }
        }

        @objc func pressed(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map = g.view as? MLNMapView else { return }
            dropAt(map.convert(g.location(in: map), toCoordinateFrom: map))
        }

        func dropAt(_ coordinate: CLLocationCoordinate2D) {
            pinDroppedAt = Date()
            Task { @MainActor in
                let point = LatLng(coordinate.latitude, coordinate.longitude)
                if self.model.offerRouteExclusion(at: point) { return }
                guard self.model.directions == nil || self.model.hasActiveJourney else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                self.model.dropPin(at: point, focus: !self.model.hasActiveJourney)
            }
        }

        var canTapPlace: Bool { model.endpointOnMap == nil && Date().timeIntervalSince(pinDroppedAt) > 1 }

        func userMovedCamera(panOrRotate: Bool) {
            if let n = model.nav, n.following { n.following = false }
            if model.nav == nil, model.browseFollowing, panOrRotate { model.browseFollowing = false }
        }

        nonisolated func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            let gesture: MLNCameraChangeReason = [.gesturePan, .gesturePinch, .gestureRotate, .gestureZoomIn,
                                                  .gestureZoomOut, .gestureOneFingerZoom, .gestureTilt]
            guard !reason.intersection(gesture).isEmpty else { return }
            let moved: MLNCameraChangeReason = [.gesturePan, .gestureRotate]
            Task { @MainActor in
                self.userMovedCamera(panOrRotate: !reason.intersection(moved).isEmpty)
            }
        }

        nonisolated func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            MainActor.assumeIsolated { cameraChanged(mapView) }
        }

        func cameraChanged(_ map: any KiteMapSurface) {
            guard model.map === map else { return }
            loadCameras(map)
            loadWazeCameras(map)
            loadSurveillance(map)
            loadWaze(map)
            loadLiveCams(map)
            render(map)
            loadRail(map)
            noteHeading(map)
            model.rememberBrowseCamera(map)
            model.refreshTransitStops()
        }

        nonisolated func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            MainActor.assumeIsolated { noteHeading(mapView) }
        }

        /** The compass button shows while the map isn't facing north. */
        func noteHeading(_ map: any KiteMapSurface) {
            let h = map.direction
            if abs(h - model.mapHeading) > 2 || (h.truncatingRemainder(dividingBy: 360) == 0) != (model.mapHeading == 0) {
                model.mapHeading = h.truncatingRemainder(dividingBy: 360) == 0 ? 0 : h
            }
        }

        nonisolated func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            // Keep MapLibre's blue dot out of the way: Kite draws its own heading arrow.
            MainActor.assumeIsolated {
                guard annotation is MLNUserLocation else { return nil }
                let view = MLNUserLocationAnnotationView(annotation: annotation, reuseIdentifier: "kite-hidden-user")
                view.isHidden = true
                view.alpha = 0
                return view
            }
        }

        nonisolated func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
            guard let loc = userLocation?.location else { return }
            MainActor.assumeIsolated { firstUserLocation(loc, on: mapView) }
        }

        func firstUserLocation(_ loc: CLLocation, on map: any KiteMapSurface) {
            guard model.map === map, !movedToUser, (0...120).contains(loc.horizontalAccuracy),
                  abs(loc.timestamp.timeIntervalSinceNow) < 15 else { return }
            movedToUser = true
            guard model.results.isEmpty, model.selected == nil, model.directions == nil,
                  !model.hasActiveJourney else { return }
            // The user left the map over their own city: keep that view. Only a fix
            // far away from the restored area takes the camera.
            if model.mapStart.restored, model.keepsRestoredView(for: loc) { return }
            map.setCenter(loc.coordinate, zoomLevel: 15, animated: false)
            let camera = map.camera
            camera.pitch = model.browsePitch
            // Open facing the way the phone is held; north-up stays north.
            if model.browseLook != .north { camera.heading = model.mapBearing(for: loc) }
            map.camera = camera
        }
    }
}
