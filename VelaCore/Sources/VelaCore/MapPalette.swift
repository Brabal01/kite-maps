import Foundation

public enum MapPaletteField: Int, CaseIterable, Identifiable, Sendable {
    case land, water, parks, buildings, streets, highways, route

    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .land: return "Land"
        case .water: return "Water"
        case .parks: return "Parks"
        case .buildings: return "Buildings"
        case .streets: return "Streets"
        case .highways: return "Highways"
        case .route: return "Route"
        }
    }
}

public struct MapPalette: Equatable, Sendable {
    private var rgb: [UInt32]

    public init?(stored: [UInt32]) {
        guard stored.count == MapPaletteField.allCases.count,
              stored.allSatisfy({ $0 <= 0xFFFFFF }) else { return nil }
        rgb = stored
    }

    public var stored: [UInt32] { rgb }

    public subscript(field: MapPaletteField) -> UInt32 {
        get { rgb[field.rawValue] }
        set { rgb[field.rawValue] = min(newValue, 0xFFFFFF) }
    }

    public struct Preset: Identifiable, Sendable {
        public let name: String
        public let palette: MapPalette
        public var id: String { name }

        fileprivate init(_ name: String, _ colors: UInt32...) {
            self.name = name
            palette = MapPalette(stored: colors)!
        }
    }

    public static let day = [
        Preset("Coast", 0xF0EEE7, 0xA3CFE1, 0xBED7B5, 0xD9D3CB, 0xFFFFFF, 0xEFC581, 0x079A9A),
        Preset("Meadow", 0xF3EEE2, 0xA5CCD1, 0xB0CBA4, 0xD7C8B5, 0xFFF8E8, 0xE7B477, 0x197665),
        Preset("Alpine", 0xEDF0F4, 0xA0C4E8, 0xBBD2CC, 0xD3DBE7, 0xFFFFFF, 0xC6BBED, 0x4763C7)
    ]

    public static let night = [
        Preset("Moonlit", 0x6C7F9C, 0x294363, 0x465C59, 0xC5CCE9, 0x70839C, 0x9C81B3, 0x67E5CB),
        Preset("Twilight", 0x202B40, 0x132943, 0x24483F, 0x39445A, 0x48556E, 0x77658C, 0x57DDCA),
        Preset("Midnight", 0x172330, 0x101F3D, 0x263D41, 0x2A3C56, 0x394E65, 0x576F9D, 0x75CFFF),
        Preset("Ember", 0x302A35, 0x202635, 0x344841, 0x4E4048, 0x5C4B57, 0x946D5F, 0xFFC190)
    ]

    public static func presets(dark: Bool) -> [Preset] { dark ? night : day }
}
