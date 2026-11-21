import Foundation

/**
 * The kind of vehicle a transit leg really is. Transitous and GTFS both use broad families
 * ("RAIL", "BUS"), which hides the difference between a metro, a tram, a suburban train and a
 * high-speed train. Kite keeps them apart, because the icon and the fallback color must not
 * pretend a regional train is a metro.
 */
public enum TransitMode: String, CaseIterable, Hashable, Sendable {
    case walk, bus, trolleybus, coach, tram, lightRail, metro, subway
    case suburbanRail, regionalTrain, longDistanceTrain, highSpeedRail
    case ferry, funicular, cableCar, aerialLift, monorail, bike, other

    /** The words used when a line has no name. */
    public var label: String {
        switch self {
        case .walk: return "Walk"
        case .bus: return "Bus"
        case .trolleybus: return "Trolleybus"
        case .coach: return "Coach"
        case .tram: return "Tram"
        case .lightRail: return "Light rail"
        case .metro: return "Metro"
        case .subway: return "Subway"
        case .suburbanRail: return "Suburban rail"
        case .regionalTrain: return "Regional train"
        case .longDistanceTrain: return "Long-distance train"
        case .highSpeedRail: return "High-speed rail"
        case .ferry: return "Ferry"
        case .funicular: return "Funicular"
        case .cableCar: return "Cable car"
        case .aerialLift: return "Aerial lift"
        case .monorail: return "Monorail"
        case .bike: return "Bike"
        case .other: return "Transit"
        }
    }

    public var shortLabel: String {
        switch self {
        case .walk: return "Walk"
        case .bus: return "Bus"
        case .trolleybus: return "Trolley"
        case .coach: return "Coach"
        case .tram: return "Tram"
        case .lightRail: return "Light rail"
        case .metro, .subway: return "Metro"
        case .suburbanRail: return "S-Bahn"
        case .regionalTrain: return "Train"
        case .longDistanceTrain: return "Train"
        case .highSpeedRail: return "High-speed"
        case .ferry: return "Ferry"
        case .funicular: return "Funicular"
        case .cableCar: return "Cable car"
        case .aerialLift: return "Aerial lift"
        case .monorail: return "Monorail"
        case .bike: return "Bike"
        case .other: return "Transit"
        }
    }

    /**
     * An SF Symbol name that exists on iOS 16.2. The icon is part of the line's identity: a
     * metro never borrows the tram icon, and an unknown mode never borrows either.
     */
    public var symbol: String {
        switch self {
        case .walk: return "figure.walk"
        case .bus, .coach: return "bus.fill"
        case .trolleybus: return "bus.fill"
        case .tram, .lightRail, .monorail: return "tram.fill"
        case .metro, .subway: return "tram.fill.tunnel"
        case .suburbanRail, .regionalTrain, .longDistanceTrain, .highSpeedRail: return "train.side.front.car"
        case .ferry: return "ferry.fill"
        case .funicular, .cableCar, .aerialLift: return "cablecar"
        case .bike: return "bicycle"
        case .other: return "questionmark.circle.fill"
        }
    }

    /** A badge drawn beside the icon for modes that share a symbol. */
    public var badge: String? {
        switch self {
        case .trolleybus: return "bolt.fill"
        case .coach: return "arrow.up.right"
        case .highSpeedRail: return "bolt.fill"
        case .suburbanRail: return "s.circle.fill"
        case .lightRail: return "l.circle.fill"
        case .monorail: return "m.circle.fill"
        default: return nil
        }
    }

    public var isRail: Bool {
        [.metro, .subway, .suburbanRail, .regionalTrain, .longDistanceTrain, .highSpeedRail,
         .tram, .lightRail, .monorail].contains(self)
    }

    /**
     * A neutral, mode-specific color, used only when no official line color exists. It is
     * deliberately not one blue for everything: an operator that publishes no colors still
     * gets a bus that looks like a bus and a tram that looks like a tram.
     */
    public var fallbackColor: UInt32 {
        switch self {
        case .walk: return 0x5F6368
        case .bus: return 0x2563EB
        case .trolleybus: return 0x0E7490
        case .coach: return 0x1D4ED8
        case .tram: return 0xB91C1C
        case .lightRail: return 0xDC2626
        case .metro: return 0x7C3AED
        case .subway: return 0x6D28D9
        case .suburbanRail: return 0x0F766E
        case .regionalTrain: return 0x15803D
        case .longDistanceTrain: return 0x334155
        case .highSpeedRail: return 0x0F172A
        case .ferry: return 0x0369A1
        case .funicular: return 0xA16207
        case .cableCar: return 0x92400E
        case .aerialLift: return 0x854D0E
        case .monorail: return 0xBE185D
        case .bike: return 0x047857
        case .other: return 0x4B5563
        }
    }

    public init(mode: String) {
        let key = mode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        switch key {
        case "WALK", "FOOT", "CAR", "RENTAL", "SHARE", "SHARE_CAR", "TAXI", "ODM": self = .walk
        case "BIKE", "BICYCLE", "SHARE_BICYCLE", "BIKESHARE": self = .bike
        case "BUS", "FLEX", "LOCAL_BUS", "NIGHT_BUS", "EXPRESS_BUS": self = .bus
        case "TROLLEYBUS", "TROLLEY": self = .trolleybus
        case "COACH", "INTERCITY_BUS": self = .coach
        case "TRAM", "STREETCAR": self = .tram
        case "LIGHT_RAIL", "LIGHTRAIL", "LRT": self = .lightRail
        case "SUBWAY", "METRO", "U_BAHN", "UBAHN": self = .metro
        case "SUBURBAN", "SUBURBAN_RAIL", "S_BAHN", "SBAHN", "REGIONAL_FAST_RAIL": self = .suburbanRail
        case "REGIONAL_RAIL", "REGIONAL_TRAIN", "REGIONAL": self = .regionalTrain
        case "LONG_DISTANCE", "LONG_DISTANCE_RAIL", "NIGHT_RAIL", "INTERCITY", "INTERCITY_RAIL": self = .longDistanceTrain
        case "HIGHSPEED_RAIL", "HIGH_SPEED_RAIL", "HIGH_SPEED_TRAIN", "HSR": self = .highSpeedRail
        case "RAIL", "TRAIN": self = .regionalTrain
        case "FERRY", "WATER", "WATER_BUS", "BOAT": self = .ferry
        case "FUNICULAR": self = .funicular
        case "CABLE_CAR", "CABLECAR": self = .cableCar
        case "AERIAL_LIFT", "GONDOLA", "AERIALWAY": self = .aerialLift
        case "MONORAIL": self = .monorail
        default:
            // A family word still tells us something ("RAIL_REPLACEMENT", "METRO_BUS").
            if key.contains("TROLLEY") { self = .trolleybus }
            else if key.contains("FERRY") || key.contains("WATER") { self = .ferry }
            else if key.contains("TRAM") { self = .tram }
            else if key.contains("SUBWAY") || key.contains("METRO") { self = .metro }
            else if key.contains("HIGHSPEED") || key.contains("HIGH_SPEED") { self = .highSpeedRail }
            else if key.contains("SUBURBAN") { self = .suburbanRail }
            else if key.contains("RAIL") || key.contains("TRAIN") { self = .regionalTrain }
            else if key.contains("COACH") { self = .coach }
            else if key.contains("BUS") { self = .bus }
            else { self = .other }
        }
    }

    /** Standard and extended GTFS `route_type`, when the feed sends one. */
    public init?(gtfsRouteType type: Int) {
        switch type {
        case 0: self = .tram
        case 1: self = .subway
        case 2: self = .regionalTrain
        case 3: self = .bus
        case 4: self = .ferry
        case 5: self = .cableCar
        case 6: self = .aerialLift
        case 7: self = .funicular
        case 11: self = .trolleybus
        case 12: self = .monorail
        case 100...199:
            switch type {
            case 101: self = .highSpeedRail
            case 102, 103, 105: self = .longDistanceTrain
            case 109: self = .suburbanRail
            default: self = .regionalTrain
            }
        case 200...299: self = .coach
        case 400...499: self = .suburbanRail
        case 700...799: self = .bus
        case 900...999: self = .tram
        case 1000...1099: self = .ferry
        case 1300...1399: self = .aerialLift
        case 1400...1499: self = .funicular
        case 1500...1599: self = .other
        default: return nil
        }
    }
}

/** Where a line's color came from, so a fallback is never presented as the operator's own. */
public enum TransitColorSource: String, Hashable, Sendable {
    case provider
    case gtfs
    case metadata
    case modeFallback
}

/**
 * One line, as the operator means it. Two agencies running a "1" are not the same line, so the
 * identity keeps the provider, agency and route ids alongside the short name and the mode.
 */
public struct TransitLineIdentity: Hashable, Sendable {
    public var provider: String?
    public var feedID: String?
    public var agencyID: String?
    public var routeID: String?
    public var shortName: String
    public var longName: String?
    public var headsign: String?
    public var mode: TransitMode
    public var routeType: Int?
    public var officialColor: UInt32?
    public var officialTextColor: UInt32?
    public var operatorName: String?
    public var source: TransitColorSource
    public var freshness: TransitLiveFreshness

    /** The color to draw, official when it exists, else a neutral color for the mode. */
    public var color: UInt32 { officialColor ?? mode.fallbackColor }
    /** A text color that stays readable on [color], respecting the operator's own when it works. */
    public var textColor: UInt32 {
        if let officialTextColor, TransitLineIdentity.contrast(officialTextColor, on: color) >= 3 {
            return officialTextColor
        }
        return TransitLineIdentity.readableText(on: color)
    }
    public var colorIsOfficial: Bool { officialColor != nil }
    /** A stable key: the same line across cards, the map and the live feed. */
    public var key: String {
        [provider, feedID, agencyID, routeID, shortName, mode.rawValue].compactMap { $0 }.joined(separator: "|")
    }

    public init(provider: String? = nil, feedID: String? = nil, agencyID: String? = nil, routeID: String? = nil,
                shortName: String, longName: String? = nil, headsign: String? = nil, mode: TransitMode,
                routeType: Int? = nil, officialColor: UInt32? = nil, officialTextColor: UInt32? = nil,
                operatorName: String? = nil, source: TransitColorSource = .modeFallback,
                freshness: TransitLiveFreshness = .scheduled) {
        self.provider = provider
        self.feedID = feedID
        self.agencyID = agencyID
        self.routeID = routeID
        self.shortName = shortName
        self.longName = longName
        self.headsign = headsign
        self.mode = mode
        self.routeType = routeType
        self.officialColor = TransitLineIdentity.valid(officialColor)
        self.officialTextColor = TransitLineIdentity.valid(officialTextColor)
        self.operatorName = operatorName
        self.source = officialColor == nil ? .modeFallback : source
        self.freshness = freshness
    }

    /** Resolve everything known about a line into one identity. */
    public static func resolve(shortName: String, longName: String? = nil, headsign: String? = nil,
                               mode: TransitMode, routeType: Int? = nil, officialColor: UInt32? = nil,
                               officialTextColor: UInt32? = nil, provider: String? = nil, feedID: String? = nil,
                               agencyID: String? = nil, routeID: String? = nil, operatorName: String? = nil,
                               source: TransitColorSource = .provider,
                               freshness: TransitLiveFreshness = .scheduled) -> TransitLineIdentity {
        TransitLineIdentity(provider: provider, feedID: feedID, agencyID: agencyID, routeID: routeID,
                            shortName: shortName, longName: longName, headsign: headsign, mode: mode,
                            routeType: routeType, officialColor: officialColor,
                            officialTextColor: officialTextColor, operatorName: operatorName,
                            source: officialColor == nil ? .modeFallback : source, freshness: freshness)
    }

    /** A color that exists: 0xRRGGBB inside the 24-bit range. */
    static func valid(_ value: UInt32?) -> UInt32? {
        guard let value, value <= 0xFFFFFF else { return nil }
        return value
    }

    /** Parse "#RRGGBB", "RRGGBB" or a numeric value, validating the range. */
    public static func hex(_ raw: String?) -> UInt32? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, s.allSatisfy({ $0.isHexDigit }) else { return nil }
        return UInt32(s, radix: 16)
    }

    /** WCAG relative luminance, 0 (black) to 1 (white). */
    public static func luminance(_ hex: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double {
            let c = Double(v) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF)
            + 0.7152 * channel((hex >> 8) & 0xFF)
            + 0.0722 * channel(hex & 0xFF)
    }

    public static func contrast(_ a: UInt32, on b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /** Black or white, whichever reads better on [hex]. */
    public static func readableText(on hex: UInt32) -> UInt32 {
        contrast(0xFFFFFF, on: hex) >= contrast(0x000000, on: hex) ? 0xFFFFFF : 0x000000
    }
}
