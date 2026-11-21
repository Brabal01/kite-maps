import XCTest
@testable import VelaCore

final class VoiceLevelTests: XCTestCase {
    func testWhatEachLevelSpeaks() {
        XCTAssertTrue(VoiceLevel.all.allows(.info))
        XCTAssertTrue(VoiceLevel.maneuvers.allows(.maneuver))
        XCTAssertFalse(VoiceLevel.maneuvers.allows(.alert))
        XCTAssertFalse(VoiceLevel.maneuvers.allows(.info))
        XCTAssertTrue(VoiceLevel.alerts.allows(.alert))
        XCTAssertFalse(VoiceLevel.alerts.allows(.maneuver))
        for kind in [SpeechKind.maneuver, .alert, .info] { XCTAssertFalse(VoiceLevel.off.allows(kind)) }
    }

    func testTheButtonCyclesThroughEveryLevelAndBack() {
        var level = VoiceLevel.all
        var seen: [VoiceLevel] = []
        for _ in 0..<4 { seen.append(level); level = level.next }
        XCTAssertEqual(seen, [.all, .maneuvers, .alerts, .off])
        XCTAssertEqual(level, .all)
    }

    func testStoredSwitchesRoundTripAndOldSettingsStillMean() {
        for level in VoiceLevel.allCases {
            let s = level.storedSwitches
            XCTAssertEqual(VoiceLevel(voice: s.voice, alertsOnly: s.alertsOnly, maneuversOnly: s.maneuversOnly), level)
        }
        // v31 stored only voice and alertsOnly.
        XCTAssertEqual(VoiceLevel(voice: true, alertsOnly: false, maneuversOnly: false), .all)
        XCTAssertEqual(VoiceLevel(voice: true, alertsOnly: true, maneuversOnly: false), .alerts)
        XCTAssertEqual(VoiceLevel(voice: false, alertsOnly: true, maneuversOnly: false), .off)
    }
}
