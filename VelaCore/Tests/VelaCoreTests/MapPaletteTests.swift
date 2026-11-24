import XCTest
@testable import VelaCore

final class MapPaletteTests: XCTestCase {
    func testPresetsMatchAndroidLightingOrderAndPersistAllColors() {
        XCTAssertEqual(MapPalette.day.map(\.name), ["Coast", "Meadow", "Alpine"])
        XCTAssertEqual(MapPalette.night.map(\.name), ["Moonlit", "Twilight", "Midnight", "Ember"])
        let original = MapPalette.day[0].palette
        var changed = original
        changed[.water] = 0x123456
        XCTAssertEqual(MapPalette(stored: changed.stored), changed)
        XCTAssertEqual(original[.water], 0xA3CFE1)
        XCTAssertEqual(changed[.route], 0x079A9A)
        XCTAssertEqual(MapPalette.night[0].palette[.buildings], 0xC5CCE9)
        XCTAssertNil(MapPalette(stored: [1, 2, 3]))
        XCTAssertNil(MapPalette(stored: [0, 0, 0, 0, 0, 0, 0x01000000]))
    }
}
