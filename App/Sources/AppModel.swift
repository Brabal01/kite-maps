import Combine
import CoreLocation
import Foundation
import MapLibre
import SwiftUI
import UIKit
import VelaCore

/** The dock's pages. */
enum AppTab: Equatable {
    case map, saved, settings
}

/** Which of your places the "pick a place" sheet is choosing. */
enum PickKind: String, Identifiable {
    case home, work
    var id: String { rawValue }
}

enum SheetDetent: Equatable {
    case collapsed, peek, half, full
}

enum SortMode: String, CaseIterable, Identifiable {
    case relevance = "Relevance", distance = "Distance", rating = "Rating"
    var id: String { rawValue }
}

struct Category: Identifiable, Hashable {
    let label: String
    let icon: String
    let query: String
    var id: String { label }

    /** British words where units are British: petrol, supermarkets, chemists, cash machines. */
    static var all: [Category] { Fmt.yards ? british : american }

    static let british = [
        Category(label: "Restaurants", icon: "fork.knife", query: "restaurants"),
        Category(label: "Coffee", icon: "cup.and.saucer.fill", query: "coffee"),
        Category(label: "Petrol", icon: "fuelpump.fill", query: "petrol station"),
        Category(label: "Supermarkets", icon: "cart.fill", query: "supermarket"),
        Category(label: "Pubs", icon: "mug.fill", query: "pub"),
        Category(label: "Hotels", icon: "bed.double.fill", query: "hotels"),
        Category(label: "Parking", icon: "parkingsign", query: "car park"),
        Category(label: "EV charging", icon: "bolt.car.fill", query: "ev charging station"),
        Category(label: "Chemists", icon: "cross.case.fill", query: "pharmacy"),
        Category(label: "Cash machines", icon: "banknote.fill", query: "atm"),
    ]

    static let american = [
        Category(label: "Restaurants", icon: "fork.knife", query: "restaurants"),
        Category(label: "Coffee", icon: "cup.and.saucer.fill", query: "coffee"),
        Category(label: "Gas", icon: "fuelpump.fill", query: "gas stations"),
        Category(label: "Groceries", icon: "cart.fill", query: "grocery stores"),
        Category(label: "Hotels", icon: "bed.double.fill", query: "hotels"),
        Category(label: "Parking", icon: "parkingsign", query: "parking"),
        Category(label: "Pharmacies", icon: "cross.case.fill", query: "pharmacy"),
        Category(label: "ATMs", icon: "banknote.fill", query: "atm"),
    ]
}

/** Directions to one place: routes for every mode, the one picked, and where from. */
enum RouteEndpoint: String, Identifiable {
    case from = "From", to = "To"
    var id: String { rawValue }
}

struct TransitJourney {
    let trip: TransitTrip
    let destination: Place
    var stops: [Place] = []
    var stopLegs: [Int] = []
    var index = 0
    var loadingWalk = false
    var boarded = false
    var boardingProgress: Double?
    var leg: TransitLeg { trip.legs[index] }
}

struct DirectionsState {
    var destination: Place
    /** True when the trip goes from the place back to you. */
    var reversed = false
    var origin: Place?
    var exclusion: RouteExclusion?
    var fromPlace: Place? { reversed ? destination : origin }
    var toPlace: Place? { reversed ? origin : destination }
    var startsFromLocation: Bool { fromPlace == nil }
    var mode: TravelMode
    var routes: [TravelMode: [Route]] = [:]
    var loading: Set<TravelMode> = []
    var errors: [TravelMode: String] = [:]
    var selected = 0
    /** The Transit tab is showing (its trips come from Transitous, not the road routers). */
    /** Places to stop at on the way, in order. */
    var stops: [Place] = []
    var transit = false
    var trips: [TransitTrip]?
    var tripsError: String?
    /** Nil for "leave now". */
    var transitTime: Date?
    var arriveBy = false
    var trip = 0

    var current: [Route] { transit ? [] : routes[mode] ?? [] }
    var route: Route? { current.indices.contains(selected) ? current[selected] : current.first }
    var pickedTrip: TransitTrip? { transit ? trips.flatMap { $0.indices.contains(trip) ? $0[trip] : $0.first } : nil }
}

/** The whole app's state; the map and every sheet read it. */
@MainActor
final class AppModel: ObservableObject {
    let settings = AppSettings.shared
    let location: LocationService

    @Published var query = ""
    /** Autocomplete while typing: Google's, or OpenStreetMap's without Google. */
    @Published var suggestions = SuggestParser.Result()
    private var suggestTask: Task<Void, Never>?
    @Published var results: [Place] = []
    @Published var resultsTitle = ""
    @Published var selected: Place?
    @Published var searching = false
    @Published var notice: String?
    @Published var detent: SheetDetent = .half
    @Published var openNowOnly = false
    @Published var rating4Only = false
    @Published var sort: SortMode = .relevance
    private(set) var previewCoverage: RouteEventCoverage?
    @Published var directions: DirectionsState? {
        didSet {
            let route = directions?.route
            guard previewCoverage?.routeID != route?.id else { return }
            previewCoverage = route.map { RouteEventCoverage($0) }
            previewCoverage?.changed = { [weak self] in self?.objectWillChange.send() }
        }
    }
    @Published var nav: Navigator?
    @Published var showLayers = false
    /** Which page of the dock is open. */
    @Published var tab: AppTab = .map
    /** Live Waze reports in view, for the "Live from Waze" chip; nil until Waze answers. */
    @Published var wazeLiveCount: Int?
    /** The police risk around you (0 to 100), for the chip on the map. */
    @Published var areaRisk: Int?
    @Published var showSettings = false
    /** A Waze report tapped on the map, shown in a small card. */
    @Published var wazeInfo: WazeAlert?
    @Published var surveillanceInfo: SurveillanceCamera?
    /** The live camera whose photo is open (tapped on the map or in a route's camera row). */
    @Published var liveCam: LiveCam?
    /** The route's cameras in order, when the open one was picked from the route's row (for next/previous). */
    @Published var liveCamRoute: [LiveCam] = []
    /** The "Add stop" search sheet. */
    @Published var addingStop = false
    @Published var editingEndpoint: RouteEndpoint?
    @Published var endpointOnMap: RouteEndpoint?
    @Published var askingRouteExclusion = false
    @Published var routeExclusionNotice: String?
    private var chosenExclusion: RouteExclusion?
    var hasRouteExclusion: Bool { nav?.exclusion != nil || directions?.exclusion != nil }
    @Published var transitStartNotice: String?
    @Published private(set) var transitJourney: TransitJourney?
    @Published private(set) var justDrive = false
    var hasActiveJourney: Bool { nav != nil || transitJourney != nil || justDrive }
    @Published private(set) var addingJourneyStop = false
    @Published var journeyStopError = false
    private var journeyStopTask: Task<Void, Never>?
    @Published private(set) var driveRoad: String?
    @Published private(set) var driveLimit: Double?
    @Published private(set) var nearbyControlsStatus = "Waiting for GPS to find road events"
    @Published private(set) var nearbyControls: [RouteControl] = []
    private var nearbyControlsTask: Task<Void, Never>?
    private var nearbyControlsCenter: LatLng?
    private var nearbyControlsAt = Date.distantPast

    private func refreshNearbyControls(_ fix: CLLocation) {
        guard nav == nil, justDrive || transitJourney != nil, nearbyControlsTask == nil,
              (0...150).contains(fix.horizontalAccuracy) else { return }
        let point = LatLng(fix.coordinate.latitude, fix.coordinate.longitude)
        guard Date().timeIntervalSince(nearbyControlsAt) >= 20,
              nearbyControlsCenter.map({ $0.distance(to: point) > 280 }) ?? true else { return }
        nearbyControlsAt = Date()
        if nearbyControlsCenter == nil { nearbyControlsStatus = "Checking the route…" }
        let leg = transitJourney?.leg.path
        nearbyControlsTask = Task {
            let controls: [RouteControl]?
            if let leg, leg.count >= 2 {
                let at = Geo.project(point, on: leg).along
                controls = await RouteControls.lookup(on: Geo.slice(leg, from: max(0, at - 80), to: at + 1200))
            } else { controls = await RouteControls.nearby(point) }
            guard !Task.isCancelled else { return }
            nearbyControlsTask = nil
            nearbyControlsStatus = controls == nil ? "Road data temporarily unavailable" : "No mapped road events ahead"
            if let controls { nearbyControlsCenter = point; nearbyControls = controls }
        }
    }

    private func clearNearbyControls() {
        nearbyControlsTask?.cancel()
        nearbyControlsTask = nil
        nearbyControlsCenter = nil
        nearbyControlsAt = .distantPast
        nearbyControls = []
        nearbyControlsStatus = "Waiting for GPS to find road events"
    }

    private(set) var driveCoordinate: CLLocationCoordinate2D?
    private(set) var driveBearing = 0.0
    @Published private(set) var driveSpeed = 0.0
    private var driveSample: LatLng?
    private var driveRoadTask: Task<Void, Never>?
    @Published var showSaved = false
    /** The sheet for choosing home or work by searching for it. */
    @Published var picking: PickKind?
    @Published var showSteps = false
    /** "Start" on a place: begin the drive as soon as its route arrives. */
    @Published var autoStart = false
    /** A trip that was cut short when Kite closed (swiped away, a crash, the phone restarting): "Carry on to…?" */
    @Published var resumeOffer: SavedTrip?
    private var tripSavedAt = Date.distantPast
    /** Bumped when the map should redraw overlays that don't come from a published value. */
    @Published var mapTick = 0
    /** Which way the map faces, for the compass button. */
    @Published var mapHeading: Double = 0
    /** The arrow's bearing, smoothed so compass noise cannot make it twitch. */
    private var smoothedHeading: Double?
    private var smoothedHeadingAt = Date.distantPast
    /**
     The browse map's 3D, 2D or north-up button. North up is the map as it always was; 3D and 2D
     follow you round like the driving map, without a route.
     */
    @Published var browseLook: MapLook = .tilted
    /** Whether the browse map is following you in 3D or 2D; dragging the map stops it. */
    @Published var browseFollowing = false

    private var lastMapCamera: MLNMapCamera?
    private(set) weak var map: (any KiteMapSurface)? { didSet { glide.map = map } }

    @discardableResult
    func attachMap(_ surface: any KiteMapSurface) -> Bool {
        let previous = map?.camera ?? lastMapCamera
        lastMapCamera = nil
        map = surface
        if let previous { surface.camera = previous }
        return previous != nil
    }

    func detachMap(_ surface: any KiteMapSurface) {
        guard map === surface else { return }
        lastMapCamera = surface.camera
        map = nil
    }
    /** How wide the side panel is on a big screen (the open iPhone Duo), so the map centres
     *  things in the part you can see; 0 on a phone. */
    var sideInset: CGFloat = 0 { didSet { glide.leftInset = sideInset } }
    /** Moves the nav arrow and camera every frame between GPS fixes. */
    let glide = NavGlide()
    /** Bumped on every new route or transit request, so answers to an older one (before a
     *  reverse, a new stop or another time) are dropped instead of replacing the new ones. */
    private var routesRequest = 0
    private var routeLoadTasks: [TravelMode: Task<Void, Never>] = [:]

    private func cancelRouteLoads() {
        routesRequest += 1
        for task in routeLoadTasks.values { task.cancel() }
        routeLoadTasks.removeAll()
        walkingSettingsTask?.cancel()
    }
    private var transitRequest = 0
    private var transitTask: Task<Void, Never>?
    private var transitLoadedAt = Date.distantPast
    private var searchTask: Task<Void, Never>?
    private var navSub: AnyCancellable?

    init() {
        LaunchTrace.mark("AppModel init")
        location = LocationService()
        location.onUpdate = { [weak self] loc in
            if self?.userLatLng == nil { LaunchTrace.mark("first location") }
            self?.locationChanged(loc)
        }
        // A trip still saved means Kite closed in the middle of it. Within two hours it's offered again.
        if let t = settings.trip, !DemoScript.active {
            if Date().timeIntervalSince(t.at) < 2 * 3600 { resumeOffer = t } else { settings.trip = nil }
        }
    }

    /** "Carry on": the same place, stops and way of travelling, started as soon as the route arrives. */
    func resumeTrip() {
        guard let t = resumeOffer else { return }
        resumeOffer = nil
        settings.trip = nil
        selected = nil
        results = []
        directions = DirectionsState(destination: t.destination, mode: TravelMode(rawValue: t.mode) ?? .drive)
        directions?.stops = t.stops
        detent = .half
        autoStart = true
        loadAllModes()
    }

    func dismissResume() {
        resumeOffer = nil
        settings.trip = nil
    }

    private func rememberTrip(_ n: Navigator) {
        tripSavedAt = Date()
        settings.trip = SavedTrip(destination: n.destination, stops: n.stops, mode: n.route.mode.rawValue, at: Date())
    }

    var userLatLng: LatLng? {
        location.last.map { LatLng($0.coordinate.latitude, $0.coordinate.longitude) }
    }

    // MARK: Search

    var visibleResults: [Place] {
        var r = results
        if openNowOnly { r = r.filter { $0.openNow == true } }
        if rating4Only { r = r.filter { ($0.rating ?? 0) >= 4 } }
        switch sort {
        case .relevance: break
        case .distance: r.sort { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
        case .rating: r.sort { ($0.rating ?? 0) > ($1.rating ?? 0) }
        }
        return r
    }

    var viewport: (center: LatLng, span: Double?) {
        guard let map, map.bounds.width > 0 else { return (userLatLng ?? LatLng(51.5074, -0.1278), nil) }
        let c = map.centerCoordinate
        let b = map.visibleCoordinateBounds
        let span = LatLng(b.sw.latitude, b.sw.longitude).distance(to: LatLng(b.ne.latitude, b.ne.longitude)) / 1.4
        return (LatLng(c.latitude, c.longitude), span.isFinite && span > 0 ? span : nil)
    }

    func search(_ text: String? = nil, title: String? = nil) {
        let q = (text ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if title == nil, MapLinks.looksLikeLink(q) {
            openLink(q)
            return
        }
        query = title ?? q
        settings.addRecent(title ?? q)
        searchTask?.cancel()
        selected = nil
        directions = nil
        searching = true
        notice = nil
        openNowOnly = false
        rating4Only = false
        sort = .relevance
        let vp = viewport
        let useGoogle = settings.googleSearchEnabled
        let user = userLatLng
        searchTask = Task {
            var r = await PlaceSearch.search(q, center: vp.center, spanMeters: vp.span, useGoogle: useGoogle, language: L10n.isCzech ? "cs" : "en")
            guard !Task.isCancelled else { return }
            // Distances read from you, not from the middle of the map.
            if let user {
                r.places = r.places.map { var p = $0; p.distanceMeters = user.distance(to: p.location); return p }
            }
            searching = false
            resultsTitle = title ?? q
            results = r.places
            if r.places.isEmpty {
                notice = Connectivity.explain("No results for \"\(q)\" here. Try another word, or move the map.")
            } else if r.googleError != nil && useGoogle {
                notice = "Google didn't answer, so these results are from OpenStreetMap."
            }
            if r.places.count == 1 {
                select(r.places[0])
            } else {
                detent = .half
                frame(PlaceSearch.mapFocus(query: q, places: r.places, category: title != nil))
            }
        }
    }

    func typed(_ text: String) {
        suggestTask?.cancel()
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, !MapLinks.looksLikeLink(q) else { suggestions = SuggestParser.Result(); return }
        let vp = viewport
        let useGoogle = settings.googleSearchEnabled
        let user = userLatLng
        suggestTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            var r = SuggestParser.Result()
            if useGoogle {
                r = (try? await GoogleClient.shared.suggest(q, near: vp.center, spanMeters: vp.span ?? 20_000, language: L10n.isCzech ? "cs" : "en")) ?? r
            }
            if r.places.isEmpty && r.queries.isEmpty, let pc = await Postcodes.lookup(q) {
                // A UK postcode, like the Set home box finds: the open geocoder often misses them.
                r.places = [pc]
            }
            if r.places.isEmpty && r.queries.isEmpty {
                r.places = (try? await Photon.search(q, near: vp.center, limit: 8)) ?? []
            }
            guard !Task.isCancelled else { return }
            r.places = PlaceSearch.nearFirst(r.places, center: vp.center)
            if let user {
                r.places = r.places.map { var p = $0; p.distanceMeters = user.distance(to: p.location); return p }
            }
            let was = suggestions
            r.places = SuggestParser.steady(r.places, after: was.places, key: \.id)
            r.queries = SuggestParser.steady(r.queries, after: was.queries, key: { $0 })
            suggestions = r
        }
    }

    /** A pasted Google Maps, Waze or Apple Maps link (or coordinates): show the spot it points at. */
    func openLink(_ text: String) {
        searchTask?.cancel()
        suggestTask?.cancel()
        suggestions = SuggestParser.Result()
        selected = nil
        directions = nil
        results = []
        notice = nil
        searching = true
        query = L10n.text("Opening link…")
        searchTask = Task {
            let target = await MapLinks.resolve(text)
            guard !Task.isCancelled else { return }
            searching = false
            switch target {
            case let .spot(point, name?)?:
                query = name
                resolve(Place(id: "link:\(point.lat),\(point.lng)", name: name, location: point, source: "osm"))
            case let .spot(point, nil)?:
                // Keep where it is in the box, not an empty "Where to?" as if nothing was found.
                query = String(format: "%.5f, %.5f", point.lat, point.lng)
                dropPin(at: point, name: "Shared location")
            case let .search(q, near)?:
                if let near, let map {
                    map.setCenter(CLLocationCoordinate2D(latitude: near.lat, longitude: near.lng), zoomLevel: 14, animated: false)
                }
                search(q)
            case nil:
                query = ""
                notice = Connectivity.explain("Couldn't find a location in that link.")
            }
        }
    }

    /** A place picked from the suggestions: show it now, then fill in its details from Google. */
    func openSuggestion(_ place: Place) {
        suggestTask?.cancel()
        // A search still loading would otherwise land afterwards and replace this place.
        searchTask?.cancel()
        searching = false
        notice = nil
        settings.addRecent(place.name)
        query = place.name
        results = []
        directions = nil
        resolve(place)
    }

    func clearSearch() {
        searchTask?.cancel()
        query = ""
        results = []
        resultsTitle = ""
        selected = nil
        searching = false
        notice = nil
    }

    func select(_ place: Place, focus: Bool = true) {
        var p = place
        if !DemoScript.active { settings.addRecentPlace(place) }
        if p.distanceMeters == nil, let u = userLatLng { p.distanceMeters = u.distance(to: p.location) }
        selected = p
        detent = .half
        guard focus, !hasActiveJourney, let map else { return }
        browseFollowing = false
        let target = CLLocationCoordinate2D(latitude: p.location.lat, longitude: p.location.lng)
        let pad = sideInset > 0 ? UIEdgeInsets(top: 0, left: sideInset, bottom: 0, right: 0)
                                : UIEdgeInsets(top: 120, left: 0, bottom: map.bounds.height * 0.45, right: 0)
        let cam = MLNMapCamera(lookingAtCenter: target, acrossDistance: 900, pitch: browsePitch, heading: 0)
        if map.zoomLevel > 16 { cam.altitude = map.camera.altitude }
        map.setCamera(cam, withDuration: 0.6, animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut),
                      edgePadding: pad, completionHandler: nil)
    }

    func closePlace() {
        selected = nil
        if !results.isEmpty { detent = .half }
    }

    /** A tap on a place the basemap draws: look it up on Google by name at that spot. */
    func resolveTapped(name: String, at point: LatLng) {
        resolve(Place(id: "tap:\(point.lat),\(point.lng)", name: name, location: point, source: "osm"))
    }

    /** Show [placeholder] right away, then swap in Google's full place found at the same spot. */
    private func resolve(_ placeholder: Place) {
        var placeholder = placeholder
        let name = placeholder.name, point = placeholder.location
        placeholder.distanceMeters = userLatLng?.distance(to: point)
        select(placeholder, focus: !placeholder.id.hasPrefix("tap:"))
        guard !settings.noGoogle else { return }
        let q = [name, placeholder.address].compactMap { $0 }.joined(separator: " ")
        let pid = placeholder.id
        Task {
            let found = (try? await GoogleClient.shared.search(q, center: point, spanMeters: 1_000, pages: 1, language: L10n.isCzech ? "cs" : "en")) ?? []
            guard selected?.id == pid else { return }
            // The same place by name too, not just the nearest: a café next door mustn't take its place.
            if let best = found.filter({ $0.location.distance(to: point) < 150 && Self.similarNames($0.name, name) })
                .min(by: { $0.location.distance(to: point) < $1.location.distance(to: point) }) {
                var b = best
                // Enrich a tapped map feature without moving its pin to a nearby search result.
                if pid.hasPrefix("tap:") { b.location = point }
                b.distanceMeters = userLatLng?.distance(to: b.location)
                selected = b
                if !DemoScript.active { settings.addRecentPlace(b) }
            }
        }
    }

    /**
     * A saved place: its "Open · Closes 10 pm" was true the day it was saved, not now. Show it
     * without that, then fill in today's from Google (left out with no internet).
     */
    func openSaved(_ saved: Place) {
        var p = saved
        p.statusText = nil
        p.openNow = nil
        select(p)
        guard !settings.noGoogle else { return }
        let q = [p.name, p.address].compactMap { $0 }.joined(separator: " ")
        Task {
            let found = (try? await GoogleClient.shared.search(q, center: p.location, spanMeters: 1_000, pages: 1, language: L10n.isCzech ? "cs" : "en")) ?? []
            guard selected?.id == p.id, let fresh = found.first(where: {
                $0.location.distance(to: p.location) < 150 && Self.similarNames($0.name, p.name)
            }) else { return }
            selected?.statusText = fresh.statusText
            selected?.openNow = fresh.openNow
            selected?.hours = fresh.hours
            selected?.permanentlyClosed = fresh.permanentlyClosed
        }
    }

    /** "Costa" and "Costa Coffee", "St Mary's Church" and "St. Mary's": every word of one name is in the other. */
    static func similarNames(_ a: String, _ b: String) -> Bool {
        func words(_ s: String) -> [String] {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        }
        let x = words(a), y = words(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        // Whole words, so "Costa" isn't "Costas" and "Royal Hotel" isn't "Royal Cafe".
        return Set(x).isSubset(of: y) || Set(y).isSubset(of: x)
    }

    static let locationOffText = "Location is off for Kite. Turn it on in Settings to get directions from where you are."

    // MARK: My places

    /** A Siri or Shortcuts request: directions home or to work, or back to the car. */
    func perform(_ kind: LaunchAction.Kind) async {
        // At a cold start, give location a few seconds to come in first.
        for _ in 0..<20 where userLatLng == nil { try? await Task.sleep(nanoseconds: 250_000_000) }
        let target: Place?
        switch kind {
        case .home: target = settings.home
        case .work: target = settings.work
        case .car: target = settings.parking
        }
        guard let target else {
            if kind == .car {
                if let nav { nav.say("No parking spot saved yet.") } else { notice = "No parking spot saved yet. Tap P on the map when you park." }
            }
            // Mid-drive, keep the trip going: a picker on top of it, cancelled, would lose it.
            else if let nav { nav.say("No \(kind == .home ? "home" : "work") address saved yet. Set it in Saved after this drive.") }
            else { picking = kind == .home ? .home : .work }
            return
        }
        // Only now that there's somewhere to go does the current drive end.
        if nav != nil { endNavigation() }
        openDirections(to: target)
        if kind == .car { directions?.mode = .walk }
    }

    /** Home, work, the parked car or a saved place, by id, for a tap on its map icon. */
    func myPlace(_ id: String) -> Place? {
        [settings.home, settings.work, settings.parking].compactMap { $0 }.first { $0.id == id }
            ?? settings.saved.first { $0.id == id }
    }

    func setHome(_ p: Place?) {
        settings.home = p.map { var h = $0; h.distanceMeters = nil; return h }
        if p != nil { notice = "Saved as your home." }
    }

    func setWork(_ p: Place?) {
        settings.work = p.map { var w = $0; w.distanceMeters = nil; return w }
        if p != nil { notice = "Saved as your work." }
    }

    /** Remember where the car is: here, now, with the street name when one is found. */
    func saveParking() {
        guard let me = userLatLng else {
            notice = location.denied ? "Location is off for Kite. Turn it on in Settings to save where you parked." : "Still finding your location. Try again in a moment."
            return
        }
        var p = Place(id: "parking:\(Int(Date().timeIntervalSince1970))", name: "Parked car", location: me, source: "osm")
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        p.category = L10n.format("Parked at %@", f.string(from: Date()))
        settings.parking = p
        notice = "Parking spot saved. Tap the P button to find your car."
        let pid = p.id
        Task {
            guard let found = await Photon.reverse(me), settings.parking?.id == pid else { return }
            settings.parking?.address = [found.name, found.address].compactMap { $0 }.joined(separator: ", ")
        }
    }

    func clearParking() {
        if selected?.id == settings.parking?.id { selected = nil }
        settings.parking = nil
    }

    /** Long press: a dropped pin with the address there. */
    func dropPin(at point: LatLng, name: String = "Dropped pin", focus: Bool = true) {
        var pin = Place(id: "pin:\(point.lat),\(point.lng)", name: L10n.text(name), location: point, source: "osm")
        pin.category = String(format: "%.5f, %.5f", point.lat, point.lng)
        select(pin, focus: focus)
        Task {
            guard let found = await Photon.reverse(point), selected?.id == pin.id else { return }
            var p = pin
            p.address = [found.name, found.address].compactMap { $0 }.joined(separator: ", ")
            selected = p
        }
    }

    // MARK: Directions

    func openDirections(to place: Place) {
        // Going somewhere else: the old trip isn't wanted back.
        if resumeOffer != nil { dismissResume() }
        autoStart = false
        directions = DirectionsState(destination: place, mode: settings.defaultMode)
        detent = .half
        loadAllModes()
    }

    func closeDirections() {
        cancelRouteLoads()
        transitRequest += 1
        autoStart = false
        directions = nil
        showSteps = false
        if let p = selected { select(p) }
    }

    func selectEndpoint(_ endpoint: RouteEndpoint, place: Place?) {
        guard var state = directions else { return }
        if (endpoint == .from) == state.reversed {
            if let place { state.destination = place }
            else if let here = userLatLng {
                state.destination = Place(id: "route-here", name: "My location", location: here, source: "osm")
            } else { return }
        } else { state.origin = place }
        state.routes = [:]
        state.exclusion = nil
        state.trips = nil
        directions = state
        reloadRoutes()
    }

    func confirmEndpointOnMap() {
        guard let endpoint = endpointOnMap else { return }
        let point = viewport.center
        endpointOnMap = nil
        let pin = Place(id: "route-pin-\(point.lat)-\(point.lng)", name: "Dropped pin", location: point, source: "osm")
        selectEndpoint(endpoint, place: pin)
    }

    private func endpoints(_ d: DirectionsState) -> (LatLng, LatLng)? {
        guard let from = d.fromPlace?.location ?? userLatLng, let to = d.toPlace?.location ?? userLatLng else { return nil }
        return (from, to)
    }

    func reverseDirections() {
        directions?.reversed.toggle()
        directions?.exclusion = nil
        directions?.routes = [:]
        directions?.selected = 0
        directions?.trips = nil
        directions?.trip = 0
        loadAllModes()
    }

    func setMode(_ m: TravelMode) {
        directions?.transit = false
        directions?.mode = m
        directions?.selected = 0
        settings.defaultMode = m
        frameRoute()
    }

    func addStop(_ p: Place) {
        guard directions != nil, (directions?.stops.count ?? 0) < 8 else { return }
        if directions?.reversed == true { directions?.stops.insert(p, at: 0) }
        else { directions?.stops.append(p) }
        reloadRoutes()
    }

    func removeStop(_ i: Int) {
        guard let d = directions, d.stops.indices.contains(i) else { return }
        directions?.stops.remove(at: i)
        reloadRoutes()
    }

    func moveStop(_ index: Int, by offset: Int) {
        guard let stops = directions?.stops, stops.indices.contains(index),
              stops.indices.contains(index + offset) else { return }
        directions?.stops.swapAt(index, index + offset)
        reloadRoutes()
    }

    /** 0 leave now, 1 depart at, 2 arrive by. */
    func setTransitTime(kind: Int, at date: Date) {
        directions?.transitTime = kind == 0 ? nil : date
        directions?.arriveBy = kind == 2
        loadTransit()
    }

    func showTransit() {
        directions?.transit = true
        // "Leave now" times found a while ago may have left already: look again.
        if directions?.transitTime == nil, Date().timeIntervalSince(transitLoadedAt) > 120 { loadTransit() }
        frameRoute()
    }

    func selectTrip(_ i: Int) {
        directions?.trip = i
        frameRoute()
    }

    func selectRoute(_ i: Int) {
        guard directions?.current.indices.contains(i) == true else { return }
        directions?.selected = i
        mapTick += 1
    }

    func reloadRoutes() {
        guard directions != nil else { return }
        directions?.routes = [:]
        directions?.errors = [:]
        directions?.selected = 0
        loadAllModes()
    }

    private var walkingSettingsTask: Task<Void, Never>?

    func refreshWalkingRoutes() {
        walkingSettingsTask?.cancel()
        guard let d = directions, let (from, to) = endpoints(d) else { return }
        let generation = routesRequest
        let via = (d.reversed ? d.stops.reversed() : d.stops).map(\.location)
        walkingSettingsTask = Task {
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            let answer = await Directions.routes(from: from, to: to, mode: .walk, via: via, alternatives: true)
            guard !Task.isCancelled, generation == routesRequest, directions?.destination.id == d.destination.id,
                  !answer.routes.isEmpty else { return }
            directions?.routes[.walk] = answer.routes.sorted { $0.durationSeconds < $1.durationSeconds }
            if directions?.mode == .walk { directions?.selected = 0; frameRoute() }
        }
    }

    private func loadAllModes() {
        guard let d = directions else { return }
        cancelRouteLoads()
        directions?.loading = []
        let req = routesRequest
        guard let (from, to) = endpoints(d) else {
            // Say so on the trip card itself, not just in passing.
            let why = location.denied ? Self.locationOffText : "Waiting for your location…"
            for m in TravelMode.allCases { directions?.errors[m] = why }
            directions?.tripsError = why
            directions?.trips = []
            if !location.denied {
                // GPS is on but hasn't answered yet: try again once it does.
                location.start()
                Task {
                    for _ in 0..<40 where userLatLng == nil && routesRequest == req {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                    }
                    if userLatLng != nil, routesRequest == req, directions?.destination.id == d.destination.id,
                       directions?.routes.isEmpty == true { reloadRoutes() }
                }
            }
            return
        }
        let via = (d.reversed ? d.stops.reversed() : d.stops).map(\.location)
        let hw = settings.avoidHighways, tolls = settings.avoidTolls, google = !settings.noGoogle
        // Already driving (asked at a red light, say): no route that starts with a U-turn.
        let moving = location.last.flatMap { l in l.speed >= 4 && l.course >= 0 && l.courseAccuracy >= 0 && l.courseAccuracy < 45 ? l.course : nil }
        let heading = d.startsFromLocation ? moving : nil
        for m in TravelMode.allCases {
            directions?.loading.insert(m)
            routeLoadTasks[m] = Task { [weak self] in
                let r = await Directions.routes(from: from, to: to, mode: m, avoidHighways: hw, avoidTolls: tolls, useGoogle: google, via: via,
                                                heading: m == .drive ? heading : nil, alternatives: true)
                guard let self, !Task.isCancelled, directions?.destination.id == d.destination.id,
                      routesRequest == req else { return }
                routeLoadTasks[m] = nil
                directions?.loading.remove(m)
                // The fastest first, so it's the one picked (Matteo, 2026-11-13: a bike route marked
                // "Slower route" was picked while one 5 min faster sat below it).
                let allowed = m == .drive ? r.routes.filter { d.exclusion?.allows($0) ?? true } : r.routes
                directions?.routes[m] = allowed.sorted { $0.durationSeconds < $1.durationSeconds }
                if allowed.isEmpty, m == .drive, d.exclusion != nil {
                    directions?.errors[m] = "No alternative avoids this segment. Undo the avoidance to see all routes."
                } else if r.routes.isEmpty {
                    let message: String
                    switch r.error {
                    case "No route found.": message = "No route found."
                    case "Couldn't check a route for tolls.": message = "Couldn't check a route for tolls."
                    case "No verified toll-free route found.": message = "No verified toll-free route found."
                    default: message = "Couldn't get a route just now. Try again in a moment."
                    }
                    directions?.errors[m] = Connectivity.explain(message)
                }
                if m == directions?.mode {
                    frameRoute()
                    if autoStart, !allowed.isEmpty {
                        autoStart = false
                        startNavigation()
                    }
                }
            }
        }
        loadTransit()
    }

    /** Transit trips for the current trip, leaving now or at the picked time. */
    func loadTransit() {
        guard let d = directions, let (from, to) = endpoints(d) else { return }
        transitLoadedAt = Date()
        // A new request either way, so one still loading can't put back trips without the stops.
        transitRequest += 1
        // The planner can't go via stops: rather say so than show trains for a different trip.
        if !d.stops.isEmpty {
            directions?.trips = []
            directions?.tripsError = "Public transport can't go via stops. Remove the stops to see trains and buses."
            return
        }
        let destId = d.destination.id
        let time = d.transitTime, arriveBy = d.arriveBy
        let liveURL = settings.gtfsRealtimeURL
        let discover = settings.autoTransitFeeds
        let req = transitRequest
        directions?.trips = nil
        directions?.tripsError = nil
        directions?.trip = 0
        // A newer trip replaces the request still loading; its answer must never land afterwards.
        transitTask?.cancel()
        transitTask = Task {
            do {
                async let planned = Transitous.plan(from: from, to: to, time: time, arriveBy: arriveBy)
                async let live = Self.liveFeed(from: from, to: to, manual: liveURL, discover: discover)
                let trips = try await planned
                guard directions?.destination.id == destId, transitRequest == req else { return }
                // Show the timetable immediately; a slow live feed is applied when it arrives.
                directions?.trips = trips.sorted { $0.durationSeconds < $1.durationSeconds }
                if trips.isEmpty { directions?.tripsError = "No transit trips found here." }
                // Transitous already carries live times from its own GTFS-Realtime sources. An
                // optional extra feed can add another region's delays, alerts and vehicle positions.
                if let feed = await live, !trips.isEmpty {
                    guard directions?.destination.id == destId, transitRequest == req else { return }
                    directions?.trips = TransitRealtime.apply(feed, to: trips)
                        .sorted { $0.durationSeconds < $1.durationSeconds }
                    if directions?.transit == true { frameRoute() }
                }
            } catch {
                guard directions?.destination.id == destId, transitRequest == req else { return }
                directions?.trips = []
                directions?.tripsError = Connectivity.explain("Couldn't reach the transit planner.")
            }
            if directions?.transit == true { frameRoute() }
        }
    }

    /**
     * A manual feed always wins. Otherwise, when discovery is on, the keyless Mobility Database
     * catalog is asked for a public feed covering the journey. Only one feed is tried; a failure
     * leaves the scheduled timetable untouched.
     */
    private static func liveFeed(from origin: LatLng, to destination: LatLng,
                                 manual: String, discover: Bool) async -> TransitRealtime.Feed? {
        if !manual.isEmpty { return await TransitRealtime.fetch(manual, timeout: 15) }
        guard discover else { return nil }
        // A regional feed must cover the journey, not only the street where it starts.
        async let atOrigin = TransitCatalog.shared.candidates(near: origin, radiusMeters: 40_000, limit: 3)
        async let atDestination = TransitCatalog.shared.candidates(near: destination, radiusMeters: 40_000, limit: 3)
        let originFeeds = await atOrigin
        let destinationFeeds = await atDestination
        var seen = Set<String>()
        let candidates = (originFeeds + destinationFeeds).filter { seen.insert($0.id).inserted }
        for candidate in candidates.prefix(3) {
            if Task.isCancelled { return nil }
            if let feed = await TransitRealtime.fetch(candidate.url, timeout: 15) { return feed }
        }
        return nil
    }

    func frameRoute() {
        if let t = directions?.pickedTrip {
            if t.path.count >= 2 { frame(t.path, bottomFraction: detent == .collapsed ? 0.12 : 0.42) }
            mapTick += 1
            return
        }
        guard let r = directions?.route else { mapTick += 1; return }
        let collapsed = detent == .collapsed
        let top: CGFloat = collapsed ? 32 : directions?.stops.isEmpty == false ? 250 : 205
        frame(r.polyline, bottomFraction: collapsed ? 0.12 : 0.42, top: top)
    }

    /** Police risk within about a kilometre of you, from remembered and live Waze police reports. */
    func updateAreaRisk(live: [WazeAlert], liveAvailable: Bool = true) {
        guard settings.wazeOn, settings.policeRisk, settings.wazePolice,
              !location.reducedAccuracy, let fix = location.last,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 200,
              abs(fix.timestamp.timeIntervalSinceNow) < 120 else { areaRisk = nil; return }
        let here = LatLng(fix.coordinate.latitude, fix.coordinate.longitude)
        let d = 0.0096 / max(cos(here.lat * .pi / 180), 0.2) * 0.62
        let line = [LatLng(here.lat, here.lng - d), LatLng(here.lat, here.lng + d)]
        let near = live.filter { $0.kind == .police && $0.location.distance(to: here) < 1_500 }.count
        areaRisk = PoliceRisk.score(ahead: line, past: WazeHistory.shared.reports, live: near,
                                    radius: 900, liveAvailable: liveAvailable)
    }

    // MARK: Navigation

    func startNavigation() {
        guard let d = directions, let route = d.route, d.startsFromLocation, let destination = d.toPlace else { return }
        beginNavigation(route, to: destination, stops: d.reversed ? Array(d.stops.reversed()) : d.stops, exclusion: d.exclusion)
    }

    private func beginNavigation(_ route: Route, to destination: Place, stops: [Place] = [],
                                 exclusion: RouteExclusion? = nil, resumeFreeDrive: Bool = false) {
        selected = nil
        let n = Navigator(route: route, destination: destination, stops: stops, settings: settings, coverage: previewCoverage)
        n.compassHeading = location.deviceHeading
        n.exclusion = exclusion
        nav = n
        defer { refreshActivity() }
        navSub = n.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        let transit = transitJourney.map { ($0.trip.id, $0.index) }
        n.onFinished = { [weak self, weak n] in
            guard let self, let n, self.nav === n else { return }
            if let (id, leg) = transit { self.completeTransitLeg(tripID: id, index: leg) }
            else { self.endNavigation() }
        }
        if let (id, leg) = transit {
            n.onArrival = { [weak self, weak n] in
                guard let self, let n, self.nav === n else { return }
                self.completeTransitLeg(tripID: id, index: leg)
            }
        } else if resumeFreeDrive {
            n.onArrival = { [weak self, weak n] in
                guard let self, let n, self.nav === n else { return }
                self.endNavigation()
                self.startJustDrive()
            }
        }
        // In a tunnel GPS stops: the navigator works out where the car should be, and it's shown like a fix.
        n.onEstimate = { [weak self, weak n] loc in
            guard let self, let n, self.nav === n else { return }
            n.handle(loc, estimated: true)
            if self.nav === n { self.followCamera(n, loc, animated: true) }
            self.mapTick += 1
        }
        resumeOffer = nil
        if transitJourney == nil { rememberTrip(n) }
        location.setNavigating(true, mode: route.mode.rawValue)
        map?.showsUserLocation = false
        if let loc = location.last, loc.horizontalAccuracy <= navigationAccuracy(for: route.mode) {
            n.handle(loc)
            if nav === n { followCamera(n, loc, animated: false) }
        }
    }

    @discardableResult func offerRouteExclusion(at point: LatLng) -> Bool {
        if let nav, !nav.showingOverview { return false }
        guard endpointOnMap == nil, let route = nav?.route ?? directions?.route, route.mode == .drive,
              let exclusion = RouteExclusion(near: point, on: route.polyline) else { return false }
        chosenExclusion = exclusion
        askingRouteExclusion = true
        return true
    }

    func applyRouteExclusion() {
        guard let exclusion = chosenExclusion else { return }
        chosenExclusion = nil
        if let nav {
            nav.avoidSegment(exclusion) { [weak self] success in
                if !success { self?.routeExclusionNotice = "No available route avoids this segment." }
            }
        } else if let state = directions {
            let allowed = state.current.filter { exclusion.allows($0) }
            guard !allowed.isEmpty else {
                routeExclusionNotice = "No current alternative avoids this segment."
                return
            }
            routesRequest += 1
            directions?.loading = []
            directions?.exclusion = exclusion
            directions?.routes[.drive] = allowed
            directions?.selected = 0
            frameRoute()
        }
    }

    func undoRouteExclusion() {
        if let nav { nav.undoAvoidance() }
        else { directions?.exclusion = nil; reloadRoutes() }
    }

    func startTransit(_ itinerary: TransitTrip? = nil) {
        guard let state = directions, var trip = itinerary ?? state.pickedTrip, !trip.legs.isEmpty else { return }
        let destination = state.toPlace ?? userLatLng.map {
            Place(id: "transit-current-location", name: L10n.text("My location"), location: $0, source: "osm")
        }
        guard let destination else {
            transitStartNotice = "Your location is needed to start this trip."
            location.start()
            return
        }
        if let origin = state.fromPlace?.location ?? trip.legs.first?.path.first,
           let here = userLatLng, here.distance(to: origin) > 100,
           state.fromPlace != nil || trip.legs.first?.isWalk == false {
            trip.legs.insert(TransitLeg(isWalk: true, mode: "WALK", toName: state.fromPlace?.name ?? trip.legs.first?.fromName ?? "",
                                       path: [here, origin]), at: 0)
        }
        location.start()
        showSteps = false
        selected = nil
        results = []
        transitJourney = TransitJourney(trip: trip, destination: destination)
        directions = nil
        startTransitLeg()
    }

    func boardTransit() {
        transitJourney?.boarded = true
        refreshActivity()
    }

    func advanceTransit() {
        guard let journey = transitJourney else { return }
        completeTransitLeg(tripID: journey.trip.id, index: journey.index)
    }

    private func completeTransitLeg(tripID: UUID, index: Int) {
        guard var journey = transitJourney, journey.trip.id == tripID, journey.index == index else { return }
        nav?.stop()
        nav = nil
        navSub = nil
        glide.stop()
        if journey.stopLegs.first == index {
            journey.stopLegs.removeFirst()
            journey.stops.removeFirst()
        }
        if journey.index + 1 == journey.trip.legs.count {
            endNavigation()
            return
        }
        journey.index += 1
        journey.boarded = false
        journey.boardingProgress = nil
        journey.loadingWalk = false
        transitJourney = journey
        startTransitLeg()
    }

    private func startTransitLeg() {
        defer { refreshActivity() }
        clearNearbyControls()
        guard let journey = transitJourney else { return }
        let leg = journey.leg
        UIApplication.shared.isIdleTimerDisabled = true
        location.setNavigating(true, mode: leg.isWalk ? TravelMode.walk.rawValue : TravelMode.drive.rawValue,
                               transit: true)
        map?.showsUserLocation = true
        if leg.path.count >= 2 { frame(leg.path, bottomFraction: 0.25, top: 200) }
        mapTick += 1
        guard leg.isWalk, let target = leg.arrivalPoint, let from = userLatLng ?? leg.path.first else { return }
        if from.distance(to: target) < 25 { advanceTransit(); return }
        transitJourney?.loadingWalk = true
        Task {
            let result = await Directions.routes(from: from, to: target, mode: .walk, useGoogle: !settings.noGoogle)
            guard transitJourney?.trip.id == journey.trip.id, transitJourney?.index == journey.index else { return }
            transitJourney?.loadingWalk = false
            if let route = result.routes.first {
                let destination = Place(id: "transit-\(journey.index)", name: leg.toName.isEmpty ? journey.destination.name : leg.toName,
                                        location: target, source: "osm")
                beginNavigation(route, to: destination)
            }
        }
    }

    func startJustDrive() {
        selected = nil
        directions = nil
        justDrive = true
        defer { refreshActivity() }
        browseLook = .tilted
        browseFollowing = true
        UIApplication.shared.isIdleTimerDisabled = true
        location.setNavigating(true, mode: TravelMode.drive.rawValue, justDrive: true)
        if let loc = location.last {
            if !location.reducedAccuracy, abs(loc.timestamp.timeIntervalSinceNow) < 45 {
                refreshNearbyControls(loc)
            }
            followBrowse(loc, entering: true)
            updateDriveRoad(loc)
        } else {
            resetCamera()
        }
    }

    func addJourneyStop(_ place: Place) {
        guard hasActiveJourney, !addingJourneyStop else { return }
        if let journey = transitJourney {
            addTransitStop(place, to: journey)
        } else if let nav {
            guard !nav.arrived, !nav.rerouting, nav.lastFix != nil else { journeyStopError = true; return }
            selected = nil
            nav.addStop(place)
        } else if justDrive {
            guard let here = userLatLng else { journeyStopError = true; return }
            addingJourneyStop = true
            selected = nil
            let heading = location.last.flatMap { fix in
                fix.speed > 4 && fix.course >= 0 && (0...35).contains(fix.courseAccuracy) ? fix.course : nil
            }
            journeyStopTask = Task {
                let result = await Directions.routes(from: here, to: place.location, mode: .drive,
                                                     avoidHighways: settings.avoidHighways, avoidTolls: settings.avoidTolls,
                                                     useGoogle: !settings.noGoogle, heading: heading)
                guard !Task.isCancelled, justDrive else { return }
                addingJourneyStop = false
                guard let route = result.routes.first else { journeyStopError = true; return }
                clearJustDrive()
                beginNavigation(route, to: place, resumeFreeDrive: true)
            }
        }
    }

    private func addTransitStop(_ place: Place, to journey: TransitJourney) {
        // Finish the ride already in progress before making the detour.
        let retained = journey.boarded && !journey.leg.isWalk ? journey.leg : nil
        guard let from = retained?.arrivalPoint ?? userLatLng else { journeyStopError = true; return }
        selected = nil
        addingJourneyStop = true
        let stops = [place] + journey.stops.filter { $0.id != place.id }
        journeyStopTask = Task {
            var legs = retained.map { [$0] } ?? []
            var stopLegs: [Int] = []
            do {
                var start = from
                var departure = max(Date(), retained?.arrive ?? Date())
                for target in stops + [journey.destination] {
                    let trips = try await Transitous.plan(from: start, to: target.location, time: departure)
                    guard let trip = trips.first(where: { !$0.legs.isEmpty }) else { break }
                    legs.append(contentsOf: trip.legs)
                    stopLegs.append(legs.count - 1)
                    departure = (trip.arrive ?? departure.addingTimeInterval(trip.durationSeconds)).addingTimeInterval(120)
                    start = target.location
                }
            } catch { }
            guard !Task.isCancelled else { return }
            addingJourneyStop = false
            guard transitJourney?.trip.id == journey.trip.id,
                  transitJourney?.index == journey.index, stopLegs.count == stops.count + 1 else {
                if transitJourney?.trip.id == journey.trip.id { journeyStopError = true }
                return
            }
            let frequency = legs.filter { !$0.isWalk }.count
            let trip = TransitTrip(depart: legs.first?.depart, arrive: legs.last?.arrive,
                                   durationSeconds: legs.reduce(0) { $0 + $1.durationSeconds },
                                   transfers: max(0, frequency - 1), legs: legs)
            nav?.stop()
            nav = nil
            navSub = nil
            glide.stop()
            transitJourney = TransitJourney(trip: trip, destination: journey.destination, stops: stops,
                                            stopLegs: Array(stopLegs.dropLast()), boarded: retained != nil)
            startTransitLeg()
        }
    }

    func endJustDrive() {
        endNavigation()
    }

    private func clearJustDrive() {
        justDrive = false
        driveRoadTask?.cancel()
        driveRoadTask = nil
        driveSample = nil
        driveRoad = nil
        driveLimit = nil
        driveSpeed = 0
        driveCoordinate = nil
        driveBearing = 0
    }

    private func updateDriveRoad(_ loc: CLLocation) {
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 60 else { return }
        if loc.course >= 0 && loc.speed > 0.8 { driveBearing = loc.course }
        else if let heading = location.deviceHeading { driveBearing = heading }
        driveCoordinate = loc.coordinate
        driveSpeed = max(0, loc.speed)
        mapTick += 1
        let point = LatLng(loc.coordinate.latitude, loc.coordinate.longitude)
        guard driveSample.map({ point.distance(to: $0) > 120 }) ?? true else { return }
        driveSample = point
        driveRoad = nil
        driveLimit = nil
        driveRoadTask?.cancel()
        driveRoadTask = Task {
            let result = await DriveRoad.lookup(point, course: loc.course)
            guard justDrive, !Task.isCancelled else { return }
            driveRoad = result?.name
            driveLimit = result?.limit
        }
    }

    func endNavigation() {
        clearNearbyControls()
        if #available(iOS 16.2, *) { JourneyActivity.shared.finish() }
        journeyStopTask?.cancel()
        journeyStopTask = nil
        addingJourneyStop = false
        selected = nil
        if justDrive { clearJustDrive() }
        UIApplication.shared.isIdleTimerDisabled = false
        transitJourney = nil
        nav?.stop()
        glide.stop()
        nav = nil
        navSub = nil
        settings.trip = nil
        location.setNavigating(false)
        map?.showsUserLocation = true
        directions = nil
        showSteps = false
        browseFollowing = false
        resetCamera()
    }

    /**
     The map button off a route. North up with the map turned by hand: face north first, like the
     compass it replaces. Otherwise on to the next of 3D, 2D and north up.
     */
    func cycleBrowseLook() {
        if browseLook == .north, mapHeading != 0 {
            map?.setDirection(0, animated: true)
            return
        }
        browseLook = browseLook.next
        if browseLook == .north {
            browseFollowing = false
            resetCamera()
            return
        }
        guard let loc = location.last else {
            resetCamera()
            if location.denied { LocationService.openSettings() } else { location.start() }
            return
        }
        browseFollowing = true
        followBrowse(loc, entering: true)
    }

    /**
     In 3D or 2D off a route, keeps you in the middle with the map facing the way you're going, as you
     move. Pinching to zoom is kept; dragging the map, or opening a place, stops it until Centre on me.
     */
    private func followBrowse(_ loc: CLLocation, entering: Bool) {
        guard browseFollowing, browseLook != .north, nav == nil, let map else { return }
        guard entering || (selected == nil && results.isEmpty && directions == nil) else { return }
        // Course while moving, compass while stopped, both smoothed; the map keeps its own heading
        // only when neither is trustworthy.
        let course = mapBearing(for: loc)
        let cam: MLNMapCamera
        if entering {
            cam = MLNMapCamera(lookingAtCenter: loc.coordinate, acrossDistance: browseLook == .tilted ? 700 : 900,
                               pitch: browseLook == .tilted ? 50 : 0, heading: course)
        } else {
            cam = map.camera
            cam.centerCoordinate = loc.coordinate
            cam.heading = course
            cam.pitch = browseLook == .tilted ? max(cam.pitch, 30) : 0
        }
        map.setCamera(cam, withDuration: entering ? 0.6 : 0.9, animationTimingFunction: CAMediaTimingFunction(name: entering ? .easeInEaseOut : .linear),
                      edgePadding: UIEdgeInsets(top: 0, left: sideInset, bottom: 0, right: 0), completionHandler: nil)
    }

    func adjustNavZoom(wider: Bool) {
        guard let n = nav, let map else { return }
        let factor = wider ? 1.5 : 1 / 1.5
        if n.following, location.last != nil {
            glide.adjustZoom(by: factor)
        } else {
            let cam = map.camera
            cam.altitude = min(20_000_000, max(20, cam.altitude * factor))
            map.setCamera(cam, withDuration: 0.25, animationTimingFunction: nil)
        }
    }

    func recenterNav() {
        guard let n = nav else { return }
        glide.resetZoom()
        n.showingOverview = false
        n.following = true
        if let loc = location.last { followCamera(n, loc, animated: true) }
    }

    /** Show the whole remaining trip; the camera stops following until re-centered. */
    func overviewNav() {
        guard let n = nav else { return }
        if n.showingOverview { recenterNav(); return }
        n.showingOverview = true
        n.following = false
        let line = n.progress.map { Geo.slice(n.route.polyline, from: $0.alongMeters, to: Geo.length(n.route.polyline)) } ?? n.route.polyline
        frame(line, bottomFraction: 0.25, top: 200)
    }

    private func refreshActivity() {
        guard #available(iOS 16.2, *), hasActiveJourney else { return }
        let title: String, detail: String, symbol: String
        var summary: String?
        var cue: String?
        if let n = nav {
            let step = n.nextManeuver
            let progress = n.progress
            let time = progress?.remainingSeconds ?? n.route.durationSeconds
            let distance = progress?.remainingMeters ?? n.route.distanceMeters
            summary = "\(Fmt.duration(time)) · \(Fmt.distance(distance)) · \(Fmt.arrival(time))"
            if n.arrived {
                title = L10n.isCzech ? "Jste v cíli" : "You have arrived"
                detail = n.destination.name
                symbol = "flag.checkered"
                cue = "\(n.route.id)-arrival"
            } else if n.rerouting || progress?.offRoute == true || n.gpsLost {
                title = n.gpsLost ? L10n.text("GPS signal lost") : L10n.text("Rerouting")
                detail = n.destination.name
                symbol = "location.slash"
            } else {
                title = step.map { L10n.isCzech ? CzechNavigation.prompt($0) : $0.instruction } ?? n.destination.name
                detail = progress.map { Fmt.distance($0.distanceToNext) } ?? n.destination.name
                symbol = step.map { maneuverSymbol($0.type) } ?? "location.north.fill"
                let lead = n.route.mode == .drive ? min(450, max(90, n.speedMps * 14)) : n.route.mode == .bike ? 75.0 : 35.0
                if let progress, let index = progress.nextIndex, let step,
                   step.type != .depart, progress.distanceToNext >= 0, progress.distanceToNext <= lead {
                    cue = "\(n.route.id)-\(index)"
                }
            }
        } else if let journey = transitJourney {
            let leg = journey.leg
            if leg.isWalk {
                title = leg.toName
                detail = L10n.text("Walk")
            } else {
                let action = journey.boarded ? (L10n.isCzech ? "Vystupte" : "Get off") : (L10n.isCzech ? "Nastupte" : "Board")
                title = action + " · " + (journey.boarded ? leg.toName : leg.fromName)
                detail = leg.line.isEmpty ? L10n.text("Transit") : leg.line
                summary = leg.headsign
                if !journey.boarded { cue = "\(journey.trip.id)-board-\(journey.index)" }
            }
            symbol = leg.isWalk ? "figure.walk" : "tram.fill"
        } else {
            title = L10n.text("Just drive")
            detail = driveRoad ?? "Kite"
            symbol = "car.fill"
        }
        JourneyActivity.shared.show(.init(instruction: title, detail: detail, symbol: symbol, summary: summary), cue: cue)
    }

    func suspendNavigationDisplay() {
        if nav != nil { glide.suspend() }
        location.setForeground(false)
    }

    /**
     * The way the arrow points: GPS course while moving (that is the direction the car is really
     * travelling), the phone's compass when standing still or when course is unavailable. The
     * shortest-angle filter removes compass jitter without making a real turn feel delayed.
     */
    func mapBearing(for loc: CLLocation) -> Double {
        let courseUsable = loc.course >= 0 && loc.courseAccuracy >= 0 && loc.courseAccuracy < 60
        let moving = loc.speed >= 1.5 && loc.courseAccuracy < 45
        let raw: Double?
        if moving, courseUsable {
            raw = loc.course
        } else if let heading = location.deviceHeading {
            raw = heading
        } else if courseUsable {
            raw = loc.course
        } else {
            raw = nil
        }
        guard let raw else { return smoothedHeading ?? map?.direction ?? 0 }
        let now = Date()
        let dt = now.timeIntervalSince(smoothedHeadingAt)
        smoothedHeadingAt = now
        let next = HeadingFilter.smooth(previous: smoothedHeading, raw: raw, dt: dt)
        smoothedHeading = next
        return next
    }

    func resumeNavigationDisplay() {
        defer { refreshActivity() }
        location.setForeground(true)
        guard let n = nav, !n.arrived else { return }
        if let fix = location.navigationFix(maximumError: navigationAccuracy(for: n.route.mode)) {
            followCamera(n, fix, animated: false)
        } else {
            glide.suspend()
            n.waitForFreshLocation()
            location.start()
        }
        mapTick += 1
    }

    private func locationChanged(_ loc: CLLocation) {
        defer { refreshActivity() }
        if !location.reducedAccuracy { refreshNearbyControls(loc) }
        if location.reducedAccuracy || loc.horizontalAccuracy > 200 { areaRisk = nil }
        if let journey = transitJourney, !location.reducedAccuracy, updateTransitPosition(loc, journey: journey) { return }
        guard let n = nav else {
            if transitJourney != nil { return }
            if justDrive {
                guard !location.reducedAccuracy, loc.horizontalAccuracy <= navigationAccuracy(for: .drive) else { return }
                updateDriveRoad(loc)
            }
            followBrowse(loc, entering: false)
            // Redraw the browse arrow even when the map isn't following: its bearing changes with
            // the compass while the phone is stationary.
            mapTick += 1
            return
        }
        guard !location.reducedAccuracy, loc.horizontalAccuracy <= navigationAccuracy(for: n.route.mode) else { return }
        n.compassHeading = location.deviceHeading
        n.handle(loc)
        if nav === n, UIApplication.shared.applicationState == .active {
            followCamera(n, loc, animated: true)
            mapTick += 1
        }
        if transitJourney == nil, nav === n { tripCheck(n) }
    }

    private func navigationAccuracy(for mode: TravelMode) -> Double { mode == .drive ? 60 : 40 }

    private func updateTransitPosition(_ loc: CLLocation, journey: TransitJourney) -> Bool {
        let leg = journey.leg
        let here = LatLng(loc.coordinate.latitude, loc.coordinate.longitude)
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 55,
              let end = leg.arrivalPoint else { return false }
        if leg.isWalk {
            let distance = here.distance(to: end)
            let approachingOnRoute = (nav?.progress?.remainingMeters ?? .infinity) <= 80
            guard distance <= 32 || (distance <= 65 && approachingOnRoute) else { return false }
        } else {
            let match = Geo.project(here, on: leg.path)
            if !journey.boarded {
                let departed = leg.depart.map { $0 <= loc.timestamp.addingTimeInterval(60) } ?? true
                if leg.path.count >= 2, departed, loc.speed >= 3, match.offset <= 60, match.along >= 65 {
                    if let earlier = journey.boardingProgress, match.along - earlier >= 30 {
                        boardTransit()
                    } else if journey.boardingProgress == nil {
                        transitJourney?.boardingProgress = match.along
                    }
                } else {
                    transitJourney?.boardingProgress = nil
                }
                return true
            }
            guard here.distance(to: end) <= 55,
                  leg.path.count < 2 || Geo.length(leg.path) - match.along < 130 else { return true }
        }
        completeTransitLeg(tripID: journey.trip.id, index: journey.index)
        return true
    }

    /** Keeps the saved trip fresh while driving, and on arriving forgets it. */
    private func tripCheck(_ n: Navigator) {
        if n.arrived {
            if settings.trip != nil { settings.trip = nil }
        } else if Date().timeIntervalSince(tripSavedAt) > 60 || settings.trip?.stops.count != n.stops.count {
            rememberTrip(n)
        }
    }

    private func followCamera(_ n: Navigator, _ loc: CLLocation, animated: Bool) {
        let p = n.progress
        // Further out on long stretches, closer in and flatter just before a turn (see NavZoom).
        // Then the zoom setting (Closer, Normal, Wider) and the 3D, 2D or north-up button.
        let view = NavZoom.view(speed: loc.speed, toNext: p?.distanceToNext, next: n.nextManeuver?.type, driving: n.route.mode == .drive)
            .applying(settings.mapZoom, settings.driveLook)
        glide.look = settings.driveLook
        glide.fix(n, loc, across: view.across, pitch: view.pitch, jump: !animated)
    }

    /** The map button while driving: 3D, then 2D, then north up. Kept for the next drive. */
    func cycleDriveLook() {
        settings.driveLook = settings.driveLook.next
        guard let n = nav else { return }
        n.showingOverview = false
        n.following = true
        if let loc = location.last { followCamera(n, loc, animated: true) }
    }

    // MARK: Map

    func centerOnUser() {
        location.requestPreciseLocation()
        guard let map, let loc = location.last else {
            if location.denied { LocationService.openSettings() } else { location.start() }
            return
        }
        // In 3D or 2D, Centre on me picks up following again.
        if browseLook != .north, nav == nil {
            browseFollowing = true
            followBrowse(loc, entering: true)
            return
        }
        let cam = MLNMapCamera(lookingAtCenter: loc.coordinate, acrossDistance: 1200, pitch: 0, heading: 0)
        map.setCamera(cam, withDuration: 0.5, animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut),
                      edgePadding: UIEdgeInsets(top: 0, left: sideInset, bottom: 0, right: 0), completionHandler: nil)
    }

    private func resetCamera() {
        guard let map else { return }
        let cam = map.camera
        cam.pitch = browsePitch
        cam.heading = 0
        map.setCamera(cam, withDuration: 0.5, animationTimingFunction: nil, edgePadding: .zero, completionHandler: nil)
    }

    func frame(_ points: [LatLng], bottomFraction: CGFloat = 0.45, top: CGFloat = 130) {
        guard let map, !points.isEmpty else { return }
        // Showing a place or a route: stop following, or the next fix would pull the map away.
        browseFollowing = false
        let pitch = nav == nil ? browsePitch : 0
        if points.count == 1 {
            let c = CLLocationCoordinate2D(latitude: points[0].lat, longitude: points[0].lng)
            map.setCamera(MLNMapCamera(lookingAtCenter: c, acrossDistance: 1200, pitch: pitch, heading: 0), withDuration: 0.3,
                          animationTimingFunction: nil, edgePadding: UIEdgeInsets(top: 0, left: sideInset, bottom: 0, right: 0),
                          completionHandler: nil)
            return
        }
        let lats = points.map(\.lat), lngs = points.map(\.lng)
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: lats.min()!, longitude: lngs.min()!),
            ne: CLLocationCoordinate2D(latitude: lats.max()!, longitude: lngs.max()!))
        // With a side panel the cards are on the left, not at the bottom.
        let pad = sideInset > 0 ? UIEdgeInsets(top: 60, left: sideInset + 40, bottom: 60, right: 40)
                                : UIEdgeInsets(top: top, left: 40, bottom: map.bounds.height * bottomFraction + 20, right: 40)
        let cam = map.cameraThatFitsCoordinateBounds(bounds, edgePadding: pad)
        cam.pitch = pitch
        cam.heading = 0
        if cam.altitude < 500 { cam.altitude = 500 }
        map.setCamera(cam, withDuration: 0.6, animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
    }

    var browsePitch: CGFloat { browseLook == .tilted ? 44 : 0 }
}
