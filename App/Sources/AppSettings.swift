import Foundation
import SwiftUI
import VelaCore

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/**
 One of the shortcuts under the search bar. The list is user-editable, so it is
 stored as raw strings and unknown values are dropped on load instead of
 breaking old data.
 */
enum QuickActionKind: String, CaseIterable, Identifiable {
    case home, work, parking, transit, fuel, food, lastDestination, justDrive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .work: return "Work"
        case .parking: return "Parking"
        case .transit: return "Transit"
        case .fuel: return "Fuel"
        case .food: return "Food"
        case .lastDestination: return "Last destination"
        case .justDrive: return "Just drive"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .work: return "briefcase.fill"
        case .parking: return "parkingsign"
        case .transit: return "tram.fill"
        case .fuel: return "fuelpump.fill"
        case .food: return "fork.knife"
        case .lastDestination: return "clock.arrow.circlepath"
        case .justDrive: return "car.fill"
        }
    }
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

    @Published var language: KiteLanguage { didSet { d.set(language.rawValue, forKey: "language") } }
    @Published var useAppleMaps = UserDefaults.standard.bool(forKey: "useAppleMaps") {
        didSet { d.set(useAppleMaps, forKey: "useAppleMaps") }
    }
    @Published var mapboxToken = MapboxCredential.load() {
        didSet { MapboxCredential.save(mapboxToken) }
    }
    @Published var useMapbox = UserDefaults.standard.bool(forKey: "useMapbox") {
        didSet { d.set(useMapbox, forKey: "useMapbox") }
    }
    @Published var theme: ThemeMode { didSet { d.set(theme.rawValue, forKey: "theme") } }
    @Published var units: UnitsMode { didSet { d.set(units.rawValue, forKey: "units") } }
    /** The shortcuts shown under the search bar, in the user's order. */
    @Published var quickActions: [QuickActionKind] {
        didSet { d.set(quickActions.map(\.rawValue), forKey: "quickActions") }
    }
    /** The browse map's last meaningful camera, so a launch does not flash London.
     *  Deliberately not @Published: the map itself asks for it at creation time and
     *  writing it must not re-render every screen that observes settings. */
    var lastMapCenter: LatLng? { didSet { save(lastMapCenter, "lastMapCenter") } }
    var lastMapZoom: Double { didSet { d.set(lastMapZoom, forKey: "lastMapZoom") } }
    @Published var voice: Bool { didSet { d.set(voice, forKey: "voice") } }
    /** Optional haptic taps for maneuvers and alerts; off when the user turns it off. */
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    /** The speaker button was last left on "Alerts only" (cameras and police, no turns). */
    @Published var voiceAlertsOnly: Bool { didSet { d.set(voiceAlertsOnly, forKey: "voiceAlertsOnly") } }
    /** The speaker button was last left on "Turns only" (no warnings). */
    @Published var voiceManeuversOnly: Bool { didSet { d.set(voiceManeuversOnly, forKey: "voiceManeuversOnly") } }
    @Published var traffic: Bool { didSet { d.set(traffic, forKey: "traffic") } }
    @Published var satellite: Bool { didSet { d.set(satellite, forKey: "satellite") } }
    /** One coherent map look; the old individual switches remain readable and additive. */
    @Published var mapPreset: MapPreset {
        didSet { d.set(mapPreset.rawValue, forKey: "mapPreset") }
    }
    var mapPresetProfile: MapPresetProfile { MapPresetCatalog.profile(for: mapPreset) }
    /** Navigation HUD 3.0: one coherent density choice. */
    @Published var hudMode: HUDMode { didSet { d.set(hudMode.rawValue, forKey: "hudMode") } }
    @Published var hudCustomLanes: Bool { didSet { d.set(hudCustomLanes, forKey: "hudCustomLanes") } }
    @Published var hudCustomThen: Bool { didSet { d.set(hudCustomThen, forKey: "hudCustomThen") } }
    @Published var hudCustomJunction: Bool { didSet { d.set(hudCustomJunction, forKey: "hudCustomJunction") } }
    var hudProfile: HUDProfile {
        HUDCatalog.profile(for: hudMode, customLanes: hudCustomLanes,
                           customThen: hudCustomThen, customJunction: hudCustomJunction)
    }
    /** Hill shading, and metro/rail lines in their colors. */
    @Published var terrain: Bool { didSet { d.set(terrain, forKey: "terrain") } }
    @Published var transitLines: Bool { didSet { d.set(transitLines, forKey: "transitLines") } }
    @Published var avoidTolls: Bool { didSet { d.set(avoidTolls, forKey: "avoidTolls") } }
    @Published var avoidHighways: Bool { didSet { d.set(avoidHighways, forKey: "avoidHighways") } }
    /** "Use Kite without Google": search and routes from open data only. */
    @Published var preferGoogleSearch = UserDefaults.standard.object(forKey: "preferGoogleSearch") as? Bool ?? true {
        didSet { d.set(preferGoogleSearch, forKey: "preferGoogleSearch") }
    }
    var googleSearchEnabled: Bool { !noGoogle && preferGoogleSearch }
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
    /** Show 2D footprints and 3D extrusions on the navigation map, not just while browsing. */
    @Published var navArrowScale: Double { didSet { d.set(navArrowScale, forKey: "navArrowScale") } }
    @Published var speedOnRight: Bool { didSet { d.set(speedOnRight, forKey: "speedOnRight") } }
    @Published var showNavSpeed: Bool { didSet { d.set(showNavSpeed, forKey: "showNavSpeed") } }
    @Published var showNavRoad: Bool { didSet { d.set(showNavRoad, forKey: "showNavRoad") } }
    @Published var speakLimitDrops: Bool { didSet { d.set(speakLimitDrops, forKey: "speakLimitDrops") } }
    @Published var suggestFasterRoutes = UserDefaults.standard.object(forKey: "suggestFasterRoutes") as? Bool ?? true {
        didSet { d.set(suggestFasterRoutes, forKey: "suggestFasterRoutes") }
    }
    @Published var showMusicControls: Bool { didSet { d.set(showMusicControls, forKey: "showMusicControls") } }
    @Published var navBuildings: Bool { didSet { d.set(navBuildings, forKey: "navBuildings") } }
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
    /** An optional GTFS-Realtime feed for the transit planner: delays, alerts and vehicle positions. */
    @Published var gtfsRealtimeURL: String { didSet { d.set(gtfsRealtimeURL, forKey: "gtfsRealtimeURL") } }
    /**
     * Discover a public GTFS-Realtime feed from the Mobility Database catalog when no manual URL
     * is set. Only keyless, active feeds inside the journey's area are tried; failure falls back to
     * the scheduled timetable.
     */
    @Published var autoTransitFeeds: Bool {
        didSet { d.set(autoTransitFeeds, forKey: "autoTransitFeeds") }
    }
    /** UK road traffic cameras (National Highways, TfL, Traffic Scotland, Traffic Wales, TrafficWatch NI). */
    @Published var liveRoadCams: Bool { didSet { d.set(liveRoadCams, forKey: "liveRoadCams") } }
    /** Windy's scenic webcams, worldwide. */
    @Published var liveWebcams: Bool { didSet { d.set(liveWebcams, forKey: "liveWebcams") } }
    /** The row of camera photos along the route, before pressing Go. */
    @Published var liveCamsOnRoute: Bool { didSet { d.set(liveCamsOnRoute, forKey: "liveCamsOnRoute") } }
    /** The map's "P" button: save where you parked, and find the way back. */
    @Published var parkingButton: Bool { didSet { d.set(parkingButton, forKey: "parkingButton") } }
    @Published var home: Place? { didSet { save(home, "home") } }
    @Published var work: Place? { didSet { save(work, "work") } }
    /** Where the car is parked, with when in `statusText`. */
    @Published var parking: Place? { didSet { save(parking, "parking") } }
    /** The first-run choice between Google's data and open data only has been made. */
    /** The trip being driven now (nil when none): offered again if the app closes before it ends. */
    @Published var trip: SavedTrip? {
        didSet {
            if trip == nil {
                d.removeObject(forKey: "trip")
                AppModel.interruptedJourneys.clear()
            } else { save(trip, "trip") }
        }
    }
    @Published var welcomed: Bool { didSet { d.set(welcomed, forKey: "welcomed") } }
    @Published var defaultMode: TravelMode { didSet { d.set(defaultMode.rawValue, forKey: "defaultMode") } }
    @Published var saved: [Place] { didSet { save(saved, "saved") } }
    /** Complete journeys the user saved, separate from an interrupted drive. */
    @Published var savedJourneys: [SavedJourney] { didSet { save(savedJourneys, "savedJourneys") } }
    @Published var recents: [String] { didSet { d.set(recents, forKey: "recents") } }
    /** Places you opened lately, newest first. */
    @Published var recentPlaces: [Place] { didSet { save(recentPlaces, "recentPlaces") } }

    private init() {
        language = KiteLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .system
        theme = ThemeMode(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        units = UnitsMode(rawValue: d.string(forKey: "units") ?? "") ?? .auto
        quickActions = (d.stringArray(forKey: "quickActions"))
            .map { $0.compactMap(QuickActionKind.init(rawValue:)) }
            ?? [.home, .work, .parking, .transit, .lastDestination]
        lastMapCenter = d.data(forKey: "lastMapCenter").flatMap { try? JSONDecoder().decode(LatLng.self, from: $0) }
        lastMapZoom = d.object(forKey: "lastMapZoom") as? Double ?? 0
        voice = d.object(forKey: "voice") as? Bool ?? true
        haptics = d.object(forKey: "haptics") as? Bool ?? true
        voiceAlertsOnly = d.bool(forKey: "voiceAlertsOnly")
        voiceManeuversOnly = d.bool(forKey: "voiceManeuversOnly")
        traffic = d.object(forKey: "traffic") as? Bool ?? true
        satellite = d.bool(forKey: "satellite")
        mapPreset = MapPreset(rawValue: d.string(forKey: "mapPreset") ?? "") ?? .classic
        hudMode = HUDMode(rawValue: d.string(forKey: "hudMode") ?? "") ?? .advanced
        hudCustomLanes = d.object(forKey: "hudCustomLanes") as? Bool ?? true
        hudCustomThen = d.object(forKey: "hudCustomThen") as? Bool ?? true
        hudCustomJunction = d.object(forKey: "hudCustomJunction") as? Bool ?? true
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
        navArrowScale = min(1.35, max(0.75, d.object(forKey: "navArrowScale") as? Double ?? 1))
        speedOnRight = d.bool(forKey: "speedOnRight")
        showNavSpeed = d.object(forKey: "showNavSpeed") as? Bool ?? true
        showNavRoad = d.object(forKey: "showNavRoad") as? Bool ?? true
        speakLimitDrops = d.bool(forKey: "speakLimitDrops")
        showMusicControls = d.bool(forKey: "showMusicControls")
        navBuildings = d.object(forKey: "navBuildings") as? Bool ?? true
        parkingButton = d.object(forKey: "parkingButton") as? Bool ?? true
        liveCams = d.object(forKey: "liveCams") as? Bool ?? true
        liveRoadCams = d.object(forKey: "liveRoadCams") as? Bool ?? true
        gtfsRealtimeURL = d.string(forKey: "gtfsRealtimeURL") ?? ""
        autoTransitFeeds = d.object(forKey: "autoTransitFeeds") as? Bool ?? true
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
        savedJourneys = (d.data(forKey: "savedJourneys"))
            .flatMap { try? JSONDecoder().decode([SavedJourney].self, from: $0) } ?? []
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

    /** Apply one preset as a coherent set of map choices, without deleting old settings. */
    func applyMapPreset(_ preset: MapPreset) {
        mapPreset = preset
        satellite = preset == .satellite
        switch preset {
        case .outdoors:
            terrain = true
            transitLines = false
        case .transit:
            terrain = false
            transitLines = true
        case .minimal, .navigation:
            terrain = false
            transitLines = false
        case .satellite:
            terrain = false
            transitLines = false
        case .classic, .explore:
            terrain = false
            transitLines = false
        }
    }

    /** Forget the restored browse camera (used by tests and by "centre on me"). */
    func clearLastMapCenter() {
        lastMapCenter = nil
        lastMapZoom = 0
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

    func toggleSaved(_ p: Place) {
        if let i = saved.firstIndex(where: { $0.matchesNearby(p) }) { saved.remove(at: i) } else { saved.insert(p, at: 0) }
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
