import Foundation
import SwiftUI
import VelaCore

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum MapLighting: String, CaseIterable, Identifiable {
    case interface, light, dark, time
    var id: String { rawValue }
    var title: String { self == .time ? "By time of day" : self == .interface ? "Match interface" : rawValue.capitalized }
}

enum UnitsMode: String, CaseIterable, Identifiable {
    case auto, metric, imperial, yards
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Automatic"
        case .metric: return "Kilometers"
        case .imperial: return "Miles and feet"
        case .yards: return "Miles and yards (UK)"
        }
    }
}

/** A trip in progress, kept so it can be picked back up if Kite closes mid-drive. */
struct SavedTrip: Codable, Equatable {
    var destination: Place
    var stops: [Place]
    /** The travel mode's raw value. */
    var mode: Int
    /** When the trip was last being driven. */
    var at: Date
}

/** Everything in Settings, kept between launches. */
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var theme: ThemeMode { didSet { d.set(theme.rawValue, forKey: "theme") } }
    @Published var mapLighting: MapLighting { didSet { d.set(mapLighting.rawValue, forKey: "kite.mapLighting") } }
    @Published var hikingTrails: Bool { didSet { d.set(hikingTrails, forKey: "kite.hikingTrails") } }
    @Published var cyclingTrails: Bool { didSet { d.set(cyclingTrails, forKey: "kite.cyclingTrails") } }
    @Published var units: UnitsMode { didSet { d.set(units.rawValue, forKey: "units") } }
    @Published var voice: Bool { didSet { d.set(voice, forKey: "voice") } }
    /** The speaker button was last left on "Alerts only" (cameras and police, no turns). */
    @Published var voiceAlertsOnly: Bool { didSet { d.set(voiceAlertsOnly, forKey: "voiceAlertsOnly") } }
    @Published var traffic: Bool { didSet { d.set(traffic, forKey: "traffic") } }
    @Published var satellite: Bool { didSet { d.set(satellite, forKey: "satellite") } }
    @Published var mapboxPublicToken: String { didSet { d.set(mapboxPublicToken, forKey: "kite.mapboxPublicToken") } }
    @Published var mapboxBasemap: Bool { didSet { d.set(mapboxBasemap, forKey: "kite.mapboxBasemap") } }
    @Published var offlineBasemap: Bool { didSet { d.set(offlineBasemap, forKey: "kite.offlineBasemap") } }
    @Published var driveEngine: RouteEngine { didSet { d.set(driveEngine.rawValue, forKey: "kite.driveEngine") } }
    @Published var walkEngine: RouteEngine { didSet { d.set(walkEngine.rawValue, forKey: "kite.walkEngine") } }
    @Published var bikeEngine: RouteEngine { didSet { d.set(bikeEngine.rawValue, forKey: "kite.bikeEngine") } }
    var activeMapboxToken: String? {
        let token = mapboxPublicToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return RouteEngine.isMapboxPublicToken(token) ? token : nil
    }

    func engine(for mode: TravelMode) -> RouteEngine {
        switch mode {
        case .drive: return driveEngine
        case .walk: return walkEngine
        case .bike: return bikeEngine
        }
    }
    /** Hill shading, and metro/rail lines in their colors. */
    @Published var terrain: Bool { didSet { d.set(terrain, forKey: "terrain") } }
    @Published var transitLines: Bool { didSet { d.set(transitLines, forKey: "transitLines") } }
    @Published var avoidTolls: Bool { didSet { d.set(avoidTolls, forKey: "avoidTolls") } }
    @Published var avoidHighways: Bool { didSet { d.set(avoidHighways, forKey: "avoidHighways") } }
    /** "Use Kite without Google": search and routes from open data only. */
    @Published var noGoogle: Bool { didSet { d.set(noGoogle, forKey: "noGoogle"); if noGoogle { Task { @MainActor in WazeWeb.shared.shutDown() } } } }
    /** Fixed speed cameras on the map, and plate readers (DeFlock), from OpenStreetMap. */
    @Published var speedCameras: Bool { didSet { d.set(speedCameras, forKey: "speedCameras") } }
    @Published var surveillanceCameras: Bool { didSet { d.set(surveillanceCameras, forKey: "surveillanceCameras") } }
    @Published var plateCameras: Bool { didSet { d.set(plateCameras, forKey: "plateCameras") } }
    /** Say "Speed camera ahead" while navigating. Off by default: some countries restrict it. */
    @Published var cameraWarnings: Bool { didSet { d.set(cameraWarnings, forKey: "cameraWarnings") } }
    /** Say so when driving over the posted limit. Off by default, like Vela. */
    @Published var speedingAlert: Bool { didSet { d.set(speedingAlert, forKey: "speedingAlert") } }
    /** How close the driving map sits: Closer, Normal (as Kite always was) or Wider. */
    @Published var mapZoom: MapZoom { didSet { d.set(mapZoom.rawValue, forKey: "mapZoom") } }
    /** The driving map's 3D, 2D or north-up choice from the map button, kept for the next drive. */
    @Published var driveLook: MapLook { didSet { d.set(driveLook.rawValue, forKey: "driveLook") } }
    /** Live reports from Waze drivers (police, crashes, hazards…): on the map, and warned about while driving. */
    @Published var waze: Bool { didSet { d.set(waze, forKey: "waze"); if !waze { Task { @MainActor in WazeWeb.shared.shutDown() } } } }
    /** The "Waze alerts (beta)" question has been answered, on first launch or after updating. */
    @Published var wazeAsked: Bool { didSet { d.set(wazeAsked, forKey: "wazeAsked") } }
    /** Which kinds of Waze report to show; the basics are on at first. */
    @Published var wazeKinds: Set<WazeAlert.Kind> { didSet { d.set(wazeKinds.map(\.rawValue), forKey: "wazeKinds") } }
    /** Waze reports as icons on the map (they're always warned about on the route). */
    @Published var wazeOnMap: Bool { didSet { d.set(wazeOnMap, forKey: "wazeOnMap") } }
    /** Chime and say "Police reported ahead" while navigating. */
    @Published var wazeVoice: Bool { didSet { d.set(wazeVoice, forKey: "wazeVoice") } }
    /** Reports older than this are ignored, in minutes; 0 keeps everything Waze still lists. */
    @Published var wazeMaxAge: Int { didSet { d.set(wazeMaxAge, forKey: "wazeMaxAge") } }
    /** A glow where police get reported, from what Kite has seen on this phone. */
    @Published var wazeHeatmap: Bool { didSet { d.set(wazeHeatmap, forKey: "wazeHeatmap") } }
    /** "Police risk: high" while driving, from the Waze police reports remembered on this phone. */
    @Published var policeRisk: Bool { didSet { d.set(policeRisk, forKey: "policeRisk") } }
    /** Warn about police planes and helicopters nearby (open ADS-B flight tracking, not Waze). */
    @Published var policeAircraft: Bool { didSet { d.set(policeAircraft, forKey: "policeAircraft") } }
    /** Live camera photos (GitHub #15): camera dots on the map, and the cameras along a route before you go. */
    @Published var liveCams: Bool { didSet { d.set(liveCams, forKey: "liveCams") } }
    /** UK road traffic cameras (National Highways, TfL, Traffic Scotland, Traffic Wales, TrafficWatch NI). */
    @Published var liveRoadCams: Bool { didSet { d.set(liveRoadCams, forKey: "liveRoadCams") } }
    /** Windy's scenic webcams, worldwide. */
    @Published var liveWebcams: Bool { didSet { d.set(liveWebcams, forKey: "liveWebcams") } }
    /** The row of camera photos along the route, before pressing Go. */
    @Published var liveCamsOnRoute: Bool { didSet { d.set(liveCamsOnRoute, forKey: "liveCamsOnRoute") } }
    /** The map's "P" button: save where you parked, and find the way back. */
    @Published var parkingButton: Bool { didSet { d.set(parkingButton, forKey: "parkingButton") } }
    /** Switch to the driving view by itself when you set off with no route (and back once parked). */
    @Published var autoDrive: Bool { didSet { d.set(autoDrive, forKey: "autoDrive") } }
    /** "My car meets the rules": clean air zones on a route aren't flagged. */
    @Published var cleanCar: Bool { didSet { d.set(cleanCar, forKey: "cleanCar") } }
    @Published var home: Place? { didSet { save(home, "home") } }
    @Published var work: Place? { didSet { save(work, "work") } }
    /** Where the car is parked, with when in `statusText`. */
    @Published var parking: Place? { didSet { save(parking, "parking") } }
    /** The first-run choice between Google's data and open data only has been made. */
    /** The trip being driven now (nil when none): offered again if the app closes before it ends. */
    @Published var trip: SavedTrip? { didSet { if trip == nil { d.removeObject(forKey: "trip") } else { save(trip, "trip") } } }
    @Published var welcomed: Bool { didSet { d.set(welcomed, forKey: "welcomed") } }
    @Published var defaultMode: TravelMode { didSet { d.set(defaultMode.rawValue, forKey: "defaultMode") } }
    @Published var saved: [Place] { didSet { save(saved, "saved") } }
    @Published var savedTransit: [SavedTransitPlan] { didSet { save(savedTransit, "kite.savedTransit") } }
    @Published var savedRoadPlans: [SavedRoadPlan] { didSet { save(savedRoadPlans, "kite.savedRoadPlans") } }
    @Published var savedPlaceLists: [SavedPlaceList] { didSet { save(savedPlaceLists, "kite.savedPlaceLists") } }
    @Published var learnWalkingPace: Bool { didSet { d.set(learnWalkingPace, forKey: "kite.learnWalkingPace") } }
    @Published var walkingPace: Double { didSet { d.set(walkingPace, forKey: "kite.walkingPace") } }
    @Published var transitExitAlerts: Bool { didSet { d.set(transitExitAlerts, forKey: "kite.transitExitAlerts") } }
    var personalPace: Double? { learnWalkingPace && (0.65...2.2).contains(walkingPace) ? walkingPace : nil }
    @Published var recents: [String] { didSet { d.set(recents, forKey: "recents") } }
    /** Places you opened lately, newest first. */
    @Published var recentPlaces: [Place] { didSet { save(recentPlaces, "recentPlaces") } }

    private init() {
        theme = ThemeMode(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        mapLighting = MapLighting(rawValue: d.string(forKey: "kite.mapLighting") ?? "") ?? .interface
        hikingTrails = d.bool(forKey: "kite.hikingTrails")
        cyclingTrails = d.bool(forKey: "kite.cyclingTrails")
        units = UnitsMode(rawValue: d.string(forKey: "units") ?? "") ?? .auto
        voice = d.object(forKey: "voice") as? Bool ?? true
        voiceAlertsOnly = d.bool(forKey: "voiceAlertsOnly")
        savedTransit = d.data(forKey: "kite.savedTransit").flatMap { try? JSONDecoder().decode([SavedTransitPlan].self, from: $0) } ?? []
        savedRoadPlans = d.data(forKey: "kite.savedRoadPlans").flatMap { try? JSONDecoder().decode([SavedRoadPlan].self, from: $0) } ?? []
        savedPlaceLists = d.data(forKey: "kite.savedPlaceLists").flatMap { try? JSONDecoder().decode([SavedPlaceList].self, from: $0) } ?? []
        learnWalkingPace = d.object(forKey: "kite.learnWalkingPace") as? Bool ?? true
        walkingPace = d.double(forKey: "kite.walkingPace")
        transitExitAlerts = d.object(forKey: "kite.transitExitAlerts") as? Bool ?? true
        traffic = d.object(forKey: "traffic") as? Bool ?? true
        satellite = d.bool(forKey: "satellite")
        mapboxPublicToken = d.string(forKey: "kite.mapboxPublicToken") ?? ""
        mapboxBasemap = d.object(forKey: "kite.mapboxBasemap") as? Bool ?? true
        offlineBasemap = d.bool(forKey: "kite.offlineBasemap")
        driveEngine = RouteEngine(rawValue: d.string(forKey: "kite.driveEngine") ?? "") ?? .automatic
        walkEngine = RouteEngine(rawValue: d.string(forKey: "kite.walkEngine") ?? "") ?? .openStreetMap
        bikeEngine = RouteEngine(rawValue: d.string(forKey: "kite.bikeEngine") ?? "") ?? .automatic
        terrain = d.bool(forKey: "terrain")
        transitLines = d.bool(forKey: "transitLines")
        avoidTolls = d.bool(forKey: "avoidTolls")
        avoidHighways = d.bool(forKey: "avoidHighways")
        noGoogle = d.bool(forKey: "noGoogle")
        speedCameras = d.object(forKey: "speedCameras") as? Bool ?? true
        surveillanceCameras = d.bool(forKey: "surveillanceCameras")
        plateCameras = d.object(forKey: "plateCameras") as? Bool ?? true
        // On for new users, except where warning of cameras is against the law.
        cameraWarnings = d.object(forKey: "cameraWarnings") as? Bool ?? !Self.camerasRestricted
        speedingAlert = d.bool(forKey: "speedingAlert")
        mapZoom = MapZoom(rawValue: d.string(forKey: "mapZoom") ?? "") ?? .normal
        driveLook = MapLook(rawValue: d.string(forKey: "driveLook") ?? "") ?? .tilted
        parkingButton = d.object(forKey: "parkingButton") as? Bool ?? true
        autoDrive = d.object(forKey: "autoDrive") as? Bool ?? true
        cleanCar = d.bool(forKey: "cleanCar")
        liveCams = d.object(forKey: "liveCams") as? Bool ?? true
        liveRoadCams = d.object(forKey: "liveRoadCams") as? Bool ?? true
        liveWebcams = d.object(forKey: "liveWebcams") as? Bool ?? true
        liveCamsOnRoute = d.object(forKey: "liveCamsOnRoute") as? Bool ?? true
        // Off until the person says yes on the Waze screen.
        waze = d.bool(forKey: "waze")
        wazeAsked = d.bool(forKey: "wazeAsked")
        wazeKinds = (d.stringArray(forKey: "wazeKinds")).map { Set($0.compactMap(WazeAlert.Kind.init(rawValue:))) }
            ?? [.police, .accident, .hazard, .weather]
        wazeOnMap = d.object(forKey: "wazeOnMap") as? Bool ?? true
        wazeVoice = d.object(forKey: "wazeVoice") as? Bool ?? true
        // On from the start, browsing and driving (Matteo: "heat map always on").
        wazeHeatmap = d.object(forKey: "wazeHeatmap") as? Bool ?? true
        wazeMaxAge = d.object(forKey: "wazeMaxAge") as? Int ?? 120
        policeRisk = d.object(forKey: "policeRisk") as? Bool ?? true
        policeAircraft = d.bool(forKey: "policeAircraft")
        home = d.data(forKey: "home").flatMap { try? JSONDecoder().decode(Place.self, from: $0) }
        work = d.data(forKey: "work").flatMap { try? JSONDecoder().decode(Place.self, from: $0) }
        parking = d.data(forKey: "parking").flatMap { try? JSONDecoder().decode(Place.self, from: $0) }
        trip = d.data(forKey: "trip").flatMap { try? JSONDecoder().decode(SavedTrip.self, from: $0) }
        welcomed = d.bool(forKey: "welcomed") || d.object(forKey: "saved") != nil
        defaultMode = TravelMode(rawValue: d.integer(forKey: "defaultMode")) ?? .drive
        saved = (d.data(forKey: "saved")).flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? []
        recents = d.stringArray(forKey: "recents") ?? []
        recentPlaces = d.data(forKey: "recentPlaces").flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? []
        // The OpenWeb Ninja key and counter from 0.7.3, no longer used: don't leave the key on the phone.
        for k in ["ninjaKey", "ninjaMonth", "ninjaUsed"] { d.removeObject(forKey: k) }
    }

    /** Countries where apps may not warn of speed cameras (France, Germany, Switzerland and a few more). */
    static var camerasRestricted: Bool {
        ["FR", "DE", "CH", "CY", "SK", "TR"].contains(Locale.current.regionCode ?? "")
    }

    private func save<T: Encodable>(_ v: T, _ key: String) {
        if let data = try? JSONEncoder().encode(v) { d.set(data, forKey: key) }
    }

    var colorScheme: ColorScheme? {
        switch theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /** Whether reports of this kind are wanted at all. */
    /** Waze belongs to Google, so "Use Kite without Google" turns it off too. */
    var wazeOn: Bool { waze && !noGoogle }

    /** Ask about Waze once: not to someone who chose no Google, since Waze is Google's. */
    var needsWazeChoice: Bool { !wazeAsked && !noGoogle }

    /** Waze still shares police reports, for the heat map and risk score (or the screenshot run's made-up ones). */
    var wazePolice: Bool { Waze.shares.contains(.police) || DemoScript.active }

    /** Live camera dots on the map: road cameras, and Windy's webcams when Kite has a key. */
    var showsRoadCams: Bool { liveCams && liveRoadCams }
    var showsWebcams: Bool { liveCams && liveWebcams && WindyKey.present }

    func wants(_ k: WazeAlert.Kind) -> Bool { wazeOn && wazeKinds.contains(k) }

    /** Whether this report should show and warn: a wanted kind, and not too old. */
    func shows(_ a: WazeAlert) -> Bool {
        wants(a.kind) && (wazeMaxAge == 0 || Date().timeIntervalSince(a.reportedAt) <= Double(wazeMaxAge) * 60)
    }

    func isSaved(_ p: Place) -> Bool { saved.contains { $0.matchesNearby(p) } }

    func isInList(_ place: Place, id: UUID) -> Bool {
        guard let stored = saved.first(where: { $0.matchesNearby(place) }) else { return false }
        return savedPlaceLists.first(where: { $0.id == id })?.places.contains(stored.id) == true
    }

    func toggleList(_ id: UUID, place: Place) {
        guard let i = savedPlaceLists.firstIndex(where: { $0.id == id }) else { return }
        let stored = saved.first(where: { $0.matchesNearby(place) })
        if stored == nil { saved.insert(place, at: 0) }
        let pin = stored?.id ?? place.id
        if savedPlaceLists[i].places.contains(pin) { savedPlaceLists[i].places.remove(pin) }
        else { savedPlaceLists[i].places.insert(pin) }
    }

    func createList(_ title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        savedPlaceLists.append(SavedPlaceList(name: name))
    }

    func toggleSaved(_ p: Place) {
        if let i = saved.firstIndex(where: { $0.matchesNearby(p) }) {
            let removed = saved.remove(at: i)
            for index in savedPlaceLists.indices { savedPlaceLists[index].places.remove(removed.id) }
        } else {
            saved.insert(p, at: 0)
        }
    }

    func renameSaved(_ id: String, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let i = saved.firstIndex(where: { $0.id == id }) else { return }
        saved[i].name = n
    }

    func addRecentPlace(_ p: Place) {
        guard !p.id.hasPrefix("pin:"), !p.id.hasPrefix("link:"), !p.id.hasPrefix("parking"), !p.id.hasPrefix("tap:"), !p.id.hasPrefix("demo") else { return }
        var slim = p
        slim.distanceMeters = nil
        slim.photoUrls = Array(p.photoUrls.prefix(1))
        slim.about = []
        slim.featuredReview = nil
        var r = recentPlaces.filter { $0.id != p.id && $0.name != p.name }
        r.insert(slim, at: 0)
        recentPlaces = Array(r.prefix(15))
    }

    func addRecent(_ q: String) {
        var r = recents.filter { $0.caseInsensitiveCompare(q) != .orderedSame }
        r.insert(q, at: 0)
        recents = Array(r.prefix(12))
    }
}
