import Foundation

/** The kinds of public transport the map layer can show or hide, as a person would name them. */
public enum TransitMapCategory: String, CaseIterable, Identifiable, Sendable {
    case metro, tram, bus, trolleybus, suburban, rail, ferry, other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .metro: return "Metro"
        case .tram: return "Trams"
        case .bus: return "Buses"
        case .trolleybus: return "Trolleybuses"
        case .suburban: return "Suburban trains"
        case .rail: return "Railway"
        case .ferry: return "Ferries"
        case .other: return "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .metro: return "tram.fill.tunnel"
        case .tram: return "tram.fill"
        case .bus, .trolleybus: return "bus.fill"
        case .suburban, .rail: return "train.side.front.car"
        case .ferry: return "ferry.fill"
        case .other: return "cablecar"
        }
    }

    public init(_ mode: TransitMode) {
        switch mode {
        case .metro, .subway: self = .metro
        case .tram, .lightRail, .monorail: self = .tram
        case .bus, .coach: self = .bus
        case .trolleybus: self = .trolleybus
        case .suburbanRail: self = .suburban
        case .regionalTrain, .longDistanceTrain, .highSpeedRail: self = .rail
        case .ferry: self = .ferry
        case .walk, .bike, .funicular, .cableCar, .aerialLift, .other: self = .other
        }
    }
}

/** Which categories are hidden. Nothing hidden (the default) shows every line in its official colour. */
public enum TransitMapFilter {
    public static func showsNetwork(enabled: Bool, hasActiveJourney: Bool, hasRoutePreview: Bool) -> Bool {
        enabled && !hasActiveJourney && !hasRoutePreview
    }

    public static func shows(_ mode: TransitMode, hidden: Set<String>) -> Bool {
        !hidden.contains(TransitMapCategory(mode).rawValue)
    }

    /** Only [category] on the map: the quick "show just trams" choice. */
    public static func hiddenShowingOnly(_ category: TransitMapCategory) -> Set<String> {
        Set(TransitMapCategory.allCases.filter { $0 != category }.map(\.rawValue))
    }

    /** True when a single category is shown and every other one is hidden. */
    public static func onlyShown(in hidden: Set<String>) -> TransitMapCategory? {
        let visible = TransitMapCategory.allCases.filter { !hidden.contains($0.rawValue) }
        return visible.count == 1 ? visible.first : nil
    }

    /** Unknown names (from a newer or older build) are dropped, so a stale setting can never hide everything. */
    public static func sanitized(_ hidden: [String]) -> Set<String> {
        let known = Set(TransitMapCategory.allCases.map(\.rawValue))
        let kept = Set(hidden).intersection(known)
        return kept.count == known.count ? [] : kept
    }
}
