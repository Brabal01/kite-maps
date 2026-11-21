import XCTest
@testable import VelaCore

final class TransitLineIdentityTests: XCTestCase {
    func testGTFSRouteTypesKeepMetroTramRailAndBusApart() {
        XCTAssertEqual(TransitMode(gtfsRouteType: 0), .tram)
        XCTAssertEqual(TransitMode(gtfsRouteType: 1), .subway)
        XCTAssertEqual(TransitMode(gtfsRouteType: 2), .regionalTrain)
        XCTAssertEqual(TransitMode(gtfsRouteType: 3), .bus)
        XCTAssertEqual(TransitMode(gtfsRouteType: 4), .ferry)
        XCTAssertEqual(TransitMode(gtfsRouteType: 5), .cableCar)
        XCTAssertEqual(TransitMode(gtfsRouteType: 7), .funicular)
        XCTAssertEqual(TransitMode(gtfsRouteType: 11), .trolleybus)
        XCTAssertEqual(TransitMode(gtfsRouteType: 12), .monorail)
        XCTAssertEqual(TransitMode(gtfsRouteType: 101), .highSpeedRail)
        XCTAssertEqual(TransitMode(gtfsRouteType: 109), .suburbanRail)
        XCTAssertEqual(TransitMode(gtfsRouteType: 200), .coach)
        XCTAssertEqual(TransitMode(gtfsRouteType: 700), .bus)
        XCTAssertEqual(TransitMode(gtfsRouteType: 900), .tram)
        XCTAssertEqual(TransitMode(gtfsRouteType: 1000), .ferry)
        XCTAssertNil(TransitMode(gtfsRouteType: 9999))
    }

    func testPlannerModeStrings() {
        XCTAssertEqual(TransitMode(mode: "SUBWAY"), .metro)
        XCTAssertEqual(TransitMode(mode: "METRO"), .metro)
        XCTAssertEqual(TransitMode(mode: "TRAM"), .tram)
        XCTAssertEqual(TransitMode(mode: "LIGHT_RAIL"), .lightRail)
        XCTAssertEqual(TransitMode(mode: "SUBURBAN"), .suburbanRail)
        XCTAssertEqual(TransitMode(mode: "REGIONAL_RAIL"), .regionalTrain)
        XCTAssertEqual(TransitMode(mode: "LONG_DISTANCE"), .longDistanceTrain)
        XCTAssertEqual(TransitMode(mode: "HIGHSPEED_RAIL"), .highSpeedRail)
        XCTAssertEqual(TransitMode(mode: "TROLLEYBUS"), .trolleybus)
        XCTAssertEqual(TransitMode(mode: "CABLE_CAR"), .cableCar)
        XCTAssertEqual(TransitMode(mode: "FUNICULAR"), .funicular)
        XCTAssertEqual(TransitMode(mode: "FERRY"), .ferry)
        XCTAssertEqual(TransitMode(mode: "MONORAIL"), .monorail)
        XCTAssertEqual(TransitMode(mode: "SOMETHING_NEW"), .other)
    }

    func testALineNumberAloneDoesNotDecideTheVehicle() {
        // "S1" is a suburban train in Berlin, not a metro because it has one letter.
        XCTAssertEqual(TransitMode(mode: "RAIL"), .regionalTrain)
        XCTAssertNotEqual(TransitMode(mode: "RAIL"), .metro)
        XCTAssertEqual(TransitMode(mode: "SUBURBAN"), .suburbanRail)
    }

    func testFallbackColorsAreModeSpecificAndNeverOneBlue() {
        let modes: [TransitMode] = [.bus, .trolleybus, .coach, .tram, .lightRail, .metro, .subway,
                                    .suburbanRail, .regionalTrain, .longDistanceTrain, .highSpeedRail,
                                    .ferry, .funicular, .cableCar, .aerialLift, .monorail]
        let colors = Set(modes.map(\.fallbackColor))
        XCTAssertGreaterThanOrEqual(colors.count, 12, "a tram must not look like a bus by color alone")
        XCTAssertNotEqual(TransitMode.bus.fallbackColor, TransitMode.tram.fallbackColor)
        XCTAssertNotEqual(TransitMode.metro.fallbackColor, TransitMode.regionalTrain.fallbackColor)
        XCTAssertNotEqual(TransitMode.ferry.fallbackColor, TransitMode.bus.fallbackColor)
    }

    func testOfficialColorIsUsedAndFallbackIsNotCalledOfficial() {
        let official = TransitLineIdentity.resolve(shortName: "A", mode: .metro, officialColor: 0xFCCC0A)
        XCTAssertEqual(official.color, 0xFCCC0A)
        XCTAssertTrue(official.colorIsOfficial)
        XCTAssertEqual(official.source, .provider)

        let fallback = TransitLineIdentity.resolve(shortName: "52", mode: .bus, officialColor: nil)
        XCTAssertEqual(fallback.color, TransitMode.bus.fallbackColor)
        XCTAssertFalse(fallback.colorIsOfficial)
        XCTAssertEqual(fallback.source, .modeFallback)
    }

    func testInvalidHexIsRejected() {
        XCTAssertEqual(TransitLineIdentity.hex("#0055AA"), 0x0055AA)
        XCTAssertEqual(TransitLineIdentity.hex("0055aa"), 0x0055AA)
        XCTAssertNil(TransitLineIdentity.hex("#12345"))
        XCTAssertNil(TransitLineIdentity.hex("GGGGGG"))
        XCTAssertNil(TransitLineIdentity.hex(""))
        let bad = TransitLineIdentity.resolve(shortName: "X", mode: .bus, officialColor: 0xFF000000)
        XCTAssertFalse(bad.colorIsOfficial)
    }

    func testTextColorKeepsItsContrast() {
        // A dark line gets white text.
        XCTAssertEqual(TransitLineIdentity.readableText(on: 0x0F172A), 0xFFFFFF)
        // A yellow line gets black text, even if the operator sent white.
        let yellow = TransitLineIdentity.resolve(shortName: "N", mode: .metro,
                                                 officialColor: 0xFCCC0A, officialTextColor: 0xFFFFFF)
        XCTAssertEqual(yellow.textColor, 0x000000)
        // A readable official text color is respected.
        let red = TransitLineIdentity.resolve(shortName: "4", mode: .tram,
                                              officialColor: 0xB91C1C, officialTextColor: 0xFFFFFF)
        XCTAssertEqual(red.textColor, 0xFFFFFF)
        XCTAssertGreaterThanOrEqual(TransitLineIdentity.contrast(red.textColor, on: red.color), 3)
    }

    func testSameNumberDifferentAgenciesAreDifferentLines() {
        let prague = TransitLineIdentity.resolve(shortName: "1", mode: .tram, agencyID: "DPP", routeID: "L1")
        let brno = TransitLineIdentity.resolve(shortName: "1", mode: .tram, agencyID: "DPMB", routeID: "L1")
        XCTAssertNotEqual(prague.key, brno.key)
    }

    func testParserUsesTheOfficialColorAndMode() throws {
        let json = """
        {"itineraries":[{"legs":[
          {"mode":"SUBWAY","routeShortName":"A","routeColor":"#FCCC0A","routeTextColor":"#FFFFFF",
           "agencyId":"DPP","routeId":"A","from":{"name":"Muzeum"},"to":{"name":"Můstek"}},
          {"mode":"RAIL","routeShortName":"S1","agencyId":"DB","from":{"name":"Alexanderplatz"},"to":{"name":"Ostkreuz"}},
          {"mode":"BUS","routeShortName":"52","from":{"name":"A"},"to":{"name":"B"}}
        ]}]}
        """
        let trip = try XCTUnwrap(Transitous.parse(Data(json.utf8)).first)
        let metro = trip.legs[0]
        XCTAssertEqual(metro.transitMode, .metro)
        XCTAssertEqual(metro.displayColor, 0xFCCC0A)
        XCTAssertTrue(metro.colorIsOfficial)
        XCTAssertEqual(metro.displayTextColor, 0x000000, "white on yellow is unreadable")

        let train = trip.legs[1]
        XCTAssertEqual(train.transitMode, .regionalTrain, "S1 by name alone is not a metro")
        XCTAssertFalse(train.colorIsOfficial)
        XCTAssertEqual(train.displayColor, TransitMode.regionalTrain.fallbackColor)

        let bus = trip.legs[2]
        XCTAssertEqual(bus.transitMode, .bus)
        XCTAssertEqual(bus.displayColor, TransitMode.bus.fallbackColor)
    }

    func testSharedTrackKeepsEveryLineVisible() throws {
        let json = """
        {"routes":[
          {"mode":"SUBWAY","transitRoutes":[{"color":"FCCC0A","shortName":"N","routeId":"N"}]},
          {"mode":"SUBWAY","transitRoutes":[{"color":"0039A6","shortName":"Q","routeId":"Q"}]},
          {"mode":"BUS","transitRoutes":[{"color":"FF0000","shortName":"M1"}]}
        ],
         "polylines":[{"polyline":{"points":"_p~iF~ps|U_ulLnnqC_mqNvxq`@","precision":5},"routeIndexes":[0,1,2]}]}
        """
        let lines = Transitous.parseLines(Data(json.utf8))
        XCTAssertEqual(lines.count, 2, "the bus is left out below close zoom")
        XCTAssertEqual(Set(lines.map(\.color)), [0xFCCC0A, 0x0039A6])
        XCTAssertEqual(Set(lines.map(\.mode)), [.metro])
        XCTAssertEqual(Set(lines.map(\.offset)).count, 2, "shared geometry is offset, not overpainted")
        XCTAssertTrue(lines.allSatisfy { $0.routeKey != nil })
    }

    func testBusesAppearOnlyWhenTheZoomAsksForThem() {
        let json = """
        {"routes":[{"mode":"BUS","transitRoutes":[{"color":"FF0000","shortName":"M1"}]}],
         "polylines":[{"polyline":{"points":"_p~iF~ps|U_ulLnnqC_mqNvxq`@","precision":5},"routeIndexes":[0]}]}
        """
        XCTAssertTrue(Transitous.parseLines(Data(json.utf8)).isEmpty)
        let buses = Transitous.parseLines(Data(json.utf8), includeBuses: true)
        XCTAssertEqual(buses.count, 1)
        XCTAssertEqual(buses.first?.mode, .bus)
        XCTAssertEqual(buses.first?.color, 0xFF0000)
    }

    func testDepartureBoardKeepsTheLineIdentity() {
        let json = """
        {"stopTimes":[
          {"place":{"departure":"2026-10-23T17:10:00Z"},"mode":"TRAM","realTime":true,
           "headsign":"Břevnov","routeShortName":"22","routeColor":"#B91C1C","routeId":"22","agencyId":"DPP"}
        ]}
        """
        let d = Transitous.parseStopTimes(Data(json.utf8))
        XCTAssertEqual(d.first?.identity.color, 0xB91C1C)
        XCTAssertEqual(d.first?.identity.mode, .tram)
        XCTAssertEqual(d.first?.identity.routeID, "22")
        XCTAssertEqual(d.first?.identity.freshness, .live)
    }

    func testModeIconsAreDistinctAndExist() {
        XCTAssertNotEqual(TransitMode.metro.symbol, TransitMode.tram.symbol)
        XCTAssertNotEqual(TransitMode.tram.symbol, TransitMode.bus.symbol)
        XCTAssertNotEqual(TransitMode.bus.symbol, TransitMode.regionalTrain.symbol)
        XCTAssertNotEqual(TransitMode.ferry.symbol, TransitMode.regionalTrain.symbol)
        XCTAssertEqual(TransitMode.other.symbol, "questionmark.circle.fill",
                       "an unknown mode must not borrow the tram icon")
        XCTAssertEqual(TransitMode.trolleybus.badge, "bolt.fill")
    }
}
