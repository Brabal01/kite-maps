import MapLibre
import UIKit
import VelaCore

/** Restyles the Liberty basemap while preserving its layers and zoom ranges. */
enum MapStyler {
    struct Palette {
        var land, water, park, woodland, meadow, wetland, sand, ice: UIColor
        var pitch, landuse, residential, civic, hospital, cemetery: UIColor
        var building, buildingOutline: UIColor
        var minor, secondary, major, motorway, service, path: UIColor
        var casing, majorCasing, motorwayCasing: UIColor
        var rail, airport, runway, border: UIColor
        var label, minorLabel, waterLabel, roadLabel, halo: UIColor
    }

    static let dark = Palette(
        land: UIColor(hex: 0x141C28), water: UIColor(hex: 0x133046),
        park: UIColor(hex: 0x213A30), woodland: UIColor(hex: 0x1B342D),
        meadow: UIColor(hex: 0x243B35), wetland: UIColor(hex: 0x203943),
        sand: UIColor(hex: 0x35352F), ice: UIColor(hex: 0x2C4756),
        pitch: UIColor(hex: 0x2B493E), landuse: UIColor(hex: 0x18222F),
        residential: UIColor(hex: 0x1B2634), civic: UIColor(hex: 0x293247),
        hospital: UIColor(hex: 0x372D41), cemetery: UIColor(hex: 0x253631),
        building: UIColor(hex: 0x2F3B4D), buildingOutline: UIColor(hex: 0x354357),
        minor: UIColor(hex: 0x37465A), secondary: UIColor(hex: 0x485568),
        major: UIColor(hex: 0x66604F), motorway: UIColor(hex: 0x8A7250),
        service: UIColor(hex: 0x303D4F), path: UIColor(hex: 0x4D5A64),
        casing: UIColor(hex: 0x15202B), majorCasing: UIColor(hex: 0x363744), motorwayCasing: UIColor(hex: 0x5A4938),
        rail: UIColor(hex: 0x667487), airport: UIColor(hex: 0x222E3D),
        runway: UIColor(hex: 0x3C4D60), border: UIColor(hex: 0x556579),
        label: UIColor(hex: 0xE0E8F3), minorLabel: UIColor(hex: 0xB7C5D8),
        waterLabel: UIColor(hex: 0x8EC5E2), roadLabel: UIColor(hex: 0xD4DEEC), halo: UIColor(hex: 0x172130))

    static let light = Palette(
        land: UIColor(hex: 0xF4F1E9), water: UIColor(hex: 0xB9DCE8),
        park: UIColor(hex: 0xD7E7CE), woodland: UIColor(hex: 0xC4DBBF),
        meadow: UIColor(hex: 0xDFEAD4), wetland: UIColor(hex: 0xCFE3DB),
        sand: UIColor(hex: 0xF0E3C4), ice: UIColor(hex: 0xE9F2F6),
        pitch: UIColor(hex: 0xCDE3CA), landuse: UIColor(hex: 0xEDEAE3),
        residential: UIColor(hex: 0xEAE7DE), civic: UIColor(hex: 0xE5E6F0),
        hospital: UIColor(hex: 0xF1E3E6), cemetery: UIColor(hex: 0xDCE5D3),
        building: UIColor(hex: 0xD7D0C6), buildingOutline: UIColor(hex: 0xC7BFB4),
        minor: UIColor(hex: 0xFFFEFA), secondary: UIColor(hex: 0xFAF4E7),
        major: UIColor(hex: 0xF7E5C2), motorway: UIColor(hex: 0xF1CC91),
        service: UIColor(hex: 0xF9F7F1), path: UIColor(hex: 0xC8BFAE),
        casing: UIColor(hex: 0xD6D0C2), majorCasing: UIColor(hex: 0xD5BD97), motorwayCasing: UIColor(hex: 0xCFA86C),
        rail: UIColor(hex: 0x9A9FA9), airport: UIColor(hex: 0xE3E3E3),
        runway: UIColor(hex: 0xC2C6CD), border: UIColor(hex: 0xA5A8AA),
        label: UIColor(hex: 0x273747), minorLabel: UIColor(hex: 0x536473),
        waterLabel: UIColor(hex: 0x296788), roadLabel: UIColor(hex: 0x4B565E), halo: UIColor(hex: 0xF9F7EF))

    private static func c(_ u: UIColor) -> NSExpression { NSExpression(forConstantValue: u) }

    /**
     Apply a v30 map preset without rebuilding the style. Only the categories
     the preset owns are changed; everything else keeps MapLibre's own rules.
     */
    static func preset(_ style: MLNStyle, preset: MapPreset) {
        let p = MapPresetCatalog.profile(for: preset)
        for layer in style.layers {
            let id = layer.identifier.lowercased()
            if id.hasPrefix("vela") { continue }
            if let symbol = layer as? MLNSymbolStyleLayer {
                if id.contains("poi") || id.contains("airport") {
                    symbol.isVisible = p.showPOI
                } else if id.contains("housenumber") {
                    symbol.isVisible = p.showHouseNumbers
                } else if id.contains("rail") || id.contains("transit") {
                    symbol.isVisible = p.showTransit
                } else if id.contains("road_shield") || id.contains("road-label") {
                    symbol.isVisible = p.showMinorLabels
                } else if id.contains("minor") || id.contains("place_other") {
                    symbol.isVisible = p.showMinorLabels
                }
            } else if let fill = layer as? MLNFillStyleLayer {
                if id == "building" {
                    fill.isVisible = p.showBuildings
                }
            } else if let extrusion = layer as? MLNFillExtrusionStyleLayer, id == "building-3d" {
                extrusion.isVisible = p.showBuildings && p.show3DBuildings
            } else if let line = layer as? MLNLineStyleLayer {
                if id.contains("path") || id.contains("pedestrian") {
                    line.isVisible = p.showPaths
                } else if id.contains("rail") {
                    line.isVisible = p.showTransit
                } else if id.hasPrefix("road_") || id.hasPrefix("bridge_") || id.hasPrefix("tunnel_") {
                    let major = id.contains("motorway") || id.contains("trunk") || id.contains("primary")
                    if p.dimMinorRoads, !major {
                        line.lineOpacity = NSExpression(forConstantValue: 0.58)
                    } else {
                        line.lineOpacity = NSExpression(forConstantValue: 1)
                    }
                }
            }
        }
    }

    static func apply(_ style: MLNStyle, dark: Bool) {
        let p = dark ? Self.dark : Self.light
        for layer in style.layers {
            let id = layer.identifier
            // Vela's own layers keep their colors (the transit lines' ids contain "rail").
            if id.hasPrefix("vela") { continue }
            if id == "natural_earth" || id == "road_area_pattern" { layer.isVisible = false; continue }
            if let bg = layer as? MLNBackgroundStyleLayer {
                bg.backgroundColor = c(p.land)
            } else if let f = layer as? MLNFillStyleLayer {
                let color: UIColor
                switch id {
                case "water": color = p.water
                case "park": color = p.park
                case "landcover_wood": color = p.woodland
                case "landcover_grass": color = p.meadow
                case "landcover_wetland": color = p.wetland
                case "landcover_sand": color = p.sand
                case "landcover_ice": color = p.ice
                case "landuse_pitch", "landuse_track": color = p.pitch
                case "landuse_residential": color = p.residential
                case "landuse_hospital": color = p.hospital
                case "landuse_school": color = p.civic
                case "landuse_cemetery": color = p.cemetery
                case "aeroway_fill": color = p.airport
                case "building": color = p.building
                default:
                    guard id.hasPrefix("landuse") || id.hasPrefix("landcover") else { continue }
                    color = p.landuse
                }
                if id.hasPrefix("landcover") { f.fillPattern = nil }
                f.fillColor = c(color)
                f.fillOutlineColor = c(id == "building" ? p.buildingOutline : color)
            } else if let e = layer as? MLNFillExtrusionStyleLayer, id == "building-3d" {
                e.fillExtrusionColor = c(p.building)
            } else if let l = layer as? MLNLineStyleLayer {
                if id.hasPrefix("waterway") { l.lineColor = c(p.water); continue }
                if id == "park_outline" || id.hasPrefix("landcover") || id.hasPrefix("park") { l.isVisible = false; continue }
                if id.hasPrefix("aeroway") { l.lineColor = c(p.runway); continue }
                if id.hasPrefix("boundary") { l.lineColor = c(p.border); continue }
                if id.contains("rail") { l.lineColor = c(p.rail); continue }
                guard id.hasPrefix("road_") || id.hasPrefix("bridge_") || id.hasPrefix("tunnel_") else { continue }
                let isMotorway = id.contains("motorway")
                let isMajor = id.contains("trunk_primary") || id.contains("secondary_tertiary")
                if id.contains("casing") {
                    l.lineColor = c(isMotorway ? p.motorwayCasing : isMajor ? p.majorCasing : p.casing)
                } else if isMotorway {
                    l.lineColor = c(p.motorway)
                } else if id.contains("trunk_primary") {
                    l.lineColor = c(p.major)
                } else if id.contains("secondary_tertiary") {
                    l.lineColor = c(p.secondary)
                } else if id.contains("service_track") {
                    l.lineColor = c(p.service)
                } else if id.contains("path_pedestrian") {
                    l.lineColor = c(p.path)
                } else {
                    l.lineColor = c(p.minor)
                }
            } else if let s = layer as? MLNSymbolStyleLayer {
                let textColor: UIColor
                if id.hasPrefix("highway-name") {
                    textColor = p.roadLabel
                    if id == "highway-name-major" || id == "highway-name-minor" {
                        s.textFontSize = NSExpression(forConstantValue: id == "highway-name-major" ? 13 : 11)
                    }
                } else if id.hasPrefix("water") {
                    textColor = p.waterLabel
                } else if id.hasPrefix("label_village") || id.hasPrefix("label_other") || id.hasPrefix("poi_") {
                    textColor = p.minorLabel
                } else if id.hasPrefix("label_") || id == "airport" {
                    textColor = p.label
                } else {
                    continue
                }
                s.textColor = c(textColor)
                s.textHaloColor = c(p.halo)
                s.textHaloWidth = NSExpression(forConstantValue: id.hasPrefix("highway-name") ? 1.5 : 1.1)
            }
        }
    }

    /** Decorative layers that only get in the way while driving. Keep places tappable. */
    private static func clutter(_ id: String) -> Bool {
        id.contains("path_pedestrian")
            || id == "highway-name-path" || id.hasSuffix("_hatching")
            || ["landuse_pitch", "landuse_track", "landuse_cemetery", "landuse_hospital", "landuse_school",
                "aeroway_fill", "aeroway_runway", "aeroway_taxiway"].contains(id)
    }

    private static var savedShieldSpacing: [String: NSExpression] = [:]
    private static var savedShieldPadding: [String: NSExpression] = [:]
    private static var savedLineOpacity: [String: NSExpression] = [:]

    /** Side streets and service roads: a little quieter while driving, so the roads that matter stand out. */
    private static func sideRoad(_ id: String) -> Bool {
        (id.hasPrefix("road_") || id.hasPrefix("bridge_") || id.hasPrefix("tunnel_")) && (id.contains("minor") || id.contains("service_track"))
    }

    /** Strips the map to roads, water, parks and road names while navigating, and puts it back after. */
    static func drive(_ style: MLNStyle, on: Bool) {
        for layer in style.layers where !layer.identifier.hasPrefix("vela") {
            let id = layer.identifier
            if clutter(id) { layer.isVisible = !on; continue }
            // Road number signs (M27, A27): Liberty repeats them every 200 points along every road, both
            // carriageways of a motorway included, a dozen at once near a junction. While driving, one
            // now and then is plenty, the way Waze shows them; the padding keeps two near each other apart.
            if let s = layer as? MLNSymbolStyleLayer, id.contains("shield") {
                if savedShieldSpacing[id] == nil {
                    savedShieldSpacing[id] = s.symbolSpacing
                    savedShieldPadding[id] = s.iconPadding
                }
                s.symbolSpacing = on ? NSExpression(forConstantValue: 900) : savedShieldSpacing[id]!
                s.iconPadding = on ? NSExpression(forConstantValue: 30) : savedShieldPadding[id]!
                continue
            }
            if let l = layer as? MLNLineStyleLayer, sideRoad(id) {
                if savedLineOpacity[id] == nil { savedLineOpacity[id] = l.lineOpacity }
                l.lineOpacity = on ? NSExpression(forConstantValue: 0.6) : savedLineOpacity[id]!
                continue
            }
        }
    }
}
