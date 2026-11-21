import Foundation

/** One coherent map look, instead of several unrelated switches. */
public enum MapPreset: String, CaseIterable, Identifiable, Sendable {
    case classic, navigation, minimal, explore, transit, outdoors, satellite

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .classic: return "Classic"
        case .navigation: return "Navigation"
        case .minimal: return "Minimal"
        case .explore: return "Explore"
        case .transit: return "Transit"
        case .outdoors: return "Outdoors"
        case .satellite: return "Satellite"
        }
    }

    public var icon: String {
        switch self {
        case .classic: return "map"
        case .navigation: return "location.north.fill"
        case .minimal: return "square.dashed"
        case .explore: return "binoculars.fill"
        case .transit: return "tram.fill"
        case .outdoors: return "mountain.2.fill"
        case .satellite: return "globe.americas.fill"
        }
    }
}

public struct MapPresetProfile: Equatable, Sendable {
    public var showPOI: Bool
    public var showMinorLabels: Bool
    public var showHouseNumbers: Bool
    public var showBuildings: Bool
    public var show3DBuildings: Bool
    public var showTransit: Bool
    public var showPaths: Bool
    public var showTerrain: Bool
    public var showTraffic: Bool
    public var dimMinorRoads: Bool
    public var roadContrast: Double
    public var labelDensity: Double
    public var satellite: Bool

    public init(showPOI: Bool, showMinorLabels: Bool, showHouseNumbers: Bool,
                showBuildings: Bool, show3DBuildings: Bool, showTransit: Bool,
                showPaths: Bool, showTerrain: Bool, showTraffic: Bool,
                dimMinorRoads: Bool, roadContrast: Double,
                labelDensity: Double, satellite: Bool = false) {
        self.showPOI = showPOI
        self.showMinorLabels = showMinorLabels
        self.showHouseNumbers = showHouseNumbers
        self.showBuildings = showBuildings
        self.show3DBuildings = show3DBuildings
        self.showTransit = showTransit
        self.showPaths = showPaths
        self.showTerrain = showTerrain
        self.showTraffic = showTraffic
        self.dimMinorRoads = dimMinorRoads
        self.roadContrast = roadContrast
        self.labelDensity = labelDensity
        self.satellite = satellite
    }
}

public enum MapPresetCatalog {
    public static func profile(for preset: MapPreset) -> MapPresetProfile {
        switch preset {
        case .classic:
            return MapPresetProfile(showPOI: true, showMinorLabels: true, showHouseNumbers: true,
                                    showBuildings: true, show3DBuildings: true, showTransit: false,
                                    showPaths: true, showTerrain: false, showTraffic: true,
                                    dimMinorRoads: false, roadContrast: 1.0, labelDensity: 1.0)
        case .navigation:
            return MapPresetProfile(showPOI: false, showMinorLabels: false, showHouseNumbers: false,
                                    showBuildings: true, show3DBuildings: true, showTransit: false,
                                    showPaths: false, showTerrain: false, showTraffic: true,
                                    dimMinorRoads: true, roadContrast: 1.18, labelDensity: 0.65)
        case .minimal:
            return MapPresetProfile(showPOI: false, showMinorLabels: false, showHouseNumbers: false,
                                    showBuildings: false, show3DBuildings: false, showTransit: false,
                                    showPaths: false, showTerrain: false, showTraffic: false,
                                    dimMinorRoads: true, roadContrast: 0.82, labelDensity: 0.45)
        case .explore:
            return MapPresetProfile(showPOI: true, showMinorLabels: true, showHouseNumbers: true,
                                    showBuildings: true, show3DBuildings: true, showTransit: true,
                                    showPaths: true, showTerrain: false, showTraffic: true,
                                    dimMinorRoads: false, roadContrast: 1.0, labelDensity: 1.15)
        case .transit:
            return MapPresetProfile(showPOI: true, showMinorLabels: true, showHouseNumbers: false,
                                    showBuildings: true, show3DBuildings: false, showTransit: true,
                                    showPaths: true, showTerrain: false, showTraffic: true,
                                    dimMinorRoads: true, roadContrast: 0.9, labelDensity: 0.9)
        case .outdoors:
            return MapPresetProfile(showPOI: true, showMinorLabels: true, showHouseNumbers: false,
                                    showBuildings: true, show3DBuildings: true, showTransit: false,
                                    showPaths: true, showTerrain: true, showTraffic: false,
                                    dimMinorRoads: false, roadContrast: 0.92, labelDensity: 1.05)
        case .satellite:
            return MapPresetProfile(showPOI: true, showMinorLabels: true, showHouseNumbers: false,
                                    showBuildings: true, show3DBuildings: true, showTransit: false,
                                    showPaths: false, showTerrain: false, showTraffic: true,
                                    dimMinorRoads: false, roadContrast: 1.0, labelDensity: 0.8,
                                    satellite: true)
        }
    }

    /** The preset navigation should use without changing the user's browse choice. */
    public static func guidanceProfile(base: MapPreset) -> MapPresetProfile {
        if base == .minimal { return profile(for: .minimal) }
        return profile(for: .navigation)
    }
}
