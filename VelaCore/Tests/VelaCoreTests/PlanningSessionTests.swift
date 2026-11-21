import XCTest
@testable import VelaCore

final class PlanningSessionTests: XCTestCase {
    private let home = LatLng(50.0000, -1.0000)
    private let shop = LatLng(50.0400, -1.0200)
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func fix(_ point: LatLng, _ at: Date, accuracy: Double = 10) -> PlanningFix {
        PlanningFix(point: point, timestamp: at, horizontalAccuracy: accuracy)
    }

    private func origin(_ point: LatLng, _ at: Date, accuracy: Double = 10,
                        kind: PlanningOriginKind = .device) -> PlanningOrigin {
        PlanningOrigin(point: point, capturedAt: at, accuracy: accuracy, kind: kind)
    }

    private func openSession(origin: PlanningOrigin? = nil,
                             mode: PlanningMode = .drive,
                             at: Date? = nil) -> (PlanningSession, [PlanningEffect]) {
        var session = PlanningSession(destinationID: "shop", destinationName: "Shop",
                                      destination: shop, mode: mode, deviceOrigin: origin)
        let effects = session.start(now: at ?? t0)
        return (session, effects)
    }

    private func has(_ effects: [PlanningEffect], _ kind: PlanningEffect.Kind) -> Bool {
        effects.contains { $0.kind == kind }
    }

    // 1. A user standing still for more than 15 seconds.
    func testStandingStillForMoreThan15SecondsStillPlans() {
        var (session, effects) = openSession(origin: origin(home, t0))
        XCTAssertEqual(session.phase, .ready)
        XCTAssertTrue(has(effects, .loadRoute))
        let originBefore = session.origin

        // The old code rejected every fix older than 15 s and then waited forever.
        let later = session.tick(now: t0.addingTimeInterval(30))
        XCTAssertEqual(session.phase, .ready)
        XCTAssertFalse(session.isWaitingForLocation)
        XCTAssertEqual(session.origin, originBefore)
        XCTAssertTrue(later.isEmpty)

        _ = session.routeLoaded(mode: .drive, requestID: session.requestID, count: 2,
                                now: t0.addingTimeInterval(31))
        XCTAssertEqual(session.selectedRouteState, .loaded(count: 2))
    }

    // 2. Standing still for five minutes.
    func testStandingStillForFiveMinutesKeepsAUsablePreviewAndRefreshes() {
        var (session, _) = openSession(origin: origin(home, t0))
        _ = session.routeLoaded(mode: .drive, requestID: session.requestID, count: 1,
                                now: t0.addingTimeInterval(2))

        let effects = session.tick(now: t0.addingTimeInterval(300))
        XCTAssertEqual(session.selectedRouteState, .loaded(count: 1), "the preview stays on screen")
        XCTAssertTrue(session.originUsability.canPlan)
        if case .stale(let age, _) = session.originUsability {
            XCTAssertEqual(age, 300, accuracy: 0.1)
        } else {
            XCTFail("a five-minute-old fix must be labelled stale, not fresh")
        }
        XCTAssertTrue(has(effects, .requestFreshLocation), "a stale start asks for a fresh fix")
        XCTAssertEqual(session.origin?.point, home, "the stable start point must not drift")

        // Past the reasonable window it stops pretending the old fix is a start.
        _ = session.tick(now: t0.addingTimeInterval(601))
        XCTAssertEqual(session.phase, .searching)
        XCTAssertTrue(session.isWaitingForLocation)
    }

    // 3. Reopening the planner.
    func testReopeningThePlannerReusesTheStartAndAsksForFreshData() {
        var (first, _) = openSession(origin: origin(home, t0))
        _ = first.routeLoaded(mode: .drive, requestID: first.requestID, count: 1, now: t0)
        let closed = first.close(now: t0.addingTimeInterval(10))
        XCTAssertTrue(has(closed, .cancelRouteLoads))

        var second = PlanningSession(destinationID: "shop", destinationName: "Shop",
                                     destination: shop, mode: .drive,
                                     deviceOrigin: origin(home, t0.addingTimeInterval(10)))
        let effects = second.start(now: t0.addingTimeInterval(20))
        XCTAssertTrue(has(effects, .loadRoute))
        XCTAssertTrue(has(effects, .requestFreshLocation))
        XCTAssertEqual(second.phase, .ready)
        XCTAssertEqual(second.origin?.point, home)
    }

    // 4. Switching drive -> walk -> bike -> transit.
    func testSwitchingAllModesSharesOneStableOrigin() {
        var (session, _) = openSession(origin: origin(home, t0))
        _ = session.routeLoaded(mode: .drive, requestID: session.requestID, count: 1, now: t0)
        let stable = session.origin
        let generation = session.requestID

        for mode in [PlanningMode.walk, .bike, .transit, .drive] {
            let effects = session.selectMode(mode, now: t0.addingTimeInterval(20))
            XCTAssertEqual(session.origin, stable)
            XCTAssertEqual(session.requestID, generation, "switching modes must not invalidate the location")
            if mode == .drive {
                XCTAssertTrue(has(effects, .frameRoute), "a loaded route appears at once")
            } else {
                XCTAssertTrue(has(effects, .loadRoute))
                _ = session.routeLoaded(mode: mode, requestID: session.requestID, count: 1,
                                        now: t0.addingTimeInterval(21))
                XCTAssertEqual(session.modeStates[mode], .loaded(count: 1))
            }
        }
    }

    // 5. Rapid repeated mode switching.
    func testRapidModeSwitchingDoesNotDuplicateRequestsOrMoveTheOrigin() {
        var (session, _) = openSession(origin: origin(home, t0))
        _ = session.routeLoaded(mode: .drive, requestID: session.requestID, count: 1, now: t0)
        let stable = session.origin
        let generation = session.requestID

        let walk = session.selectMode(.walk, now: t0.addingTimeInterval(1))
        let bike = session.selectMode(.bike, now: t0.addingTimeInterval(2))
        let walkAgain = session.selectMode(.walk, now: t0.addingTimeInterval(3))
        let transit = session.selectMode(.transit, now: t0.addingTimeInterval(4))

        XCTAssertTrue(has(walk, .loadRoute))
        XCTAssertTrue(has(bike, .loadRoute))
        XCTAssertTrue(walkAgain.isEmpty, "a mode already loading must not start a second request")
        XCTAssertTrue(has(transit, .loadRoute))
        XCTAssertEqual(session.origin, stable)
        XCTAssertEqual(session.requestID, generation)
        XCTAssertEqual(session.modeStates[.walk], .loading)
    }

    // 6. A GPS fix arrives after 30 seconds.
    func testLateFixAfter30SecondsStartsTheChosenRouteAutomatically() {
        var (session, start) = openSession()
        XCTAssertEqual(session.phase, .searching)
        XCTAssertTrue(has(start, .requestFreshLocation))
        XCTAssertTrue(session.tick(now: t0.addingTimeInterval(10)).isEmpty)

        let slow = session.tick(now: t0.addingTimeInterval(15))
        XCTAssertTrue(has(slow, .showSlowNotice))

        let late = session.location(fix(home, t0.addingTimeInterval(30)), now: t0.addingTimeInterval(30))
        XCTAssertEqual(session.phase, .ready)
        XCTAssertFalse(session.isWaitingForLocation)
        XCTAssertTrue(has(late, .loadRoute))
        XCTAssertTrue(has(late, .frameRoute))
        XCTAssertEqual(late.first?.requestID, session.requestID)

        _ = session.routeLoaded(mode: .drive, requestID: session.requestID, count: 1,
                                now: t0.addingTimeInterval(31))
        XCTAssertEqual(session.selectedRouteState, .loaded(count: 1))
    }

    // 7. A fix arrives even after the original timeout.
    func testFixAfterTheTimeoutStillRecoversWithoutPolling() {
        var (session, _) = openSession()
        _ = session.tick(now: t0.addingTimeInterval(45))
        XCTAssertTrue(session.manualOriginOffered)
        let later = session.tick(now: t0.addingTimeInterval(90))
        XCTAssertTrue(later.isEmpty || has(later, .requestFreshLocation))

        let revived = session.location(fix(home, t0.addingTimeInterval(60)), now: t0.addingTimeInterval(60))
        XCTAssertTrue(has(revived, .loadRoute))
        XCTAssertFalse(session.manualOriginOffered)
        XCTAssertFalse(session.slowLocationNotice)
        XCTAssertFalse(session.isWaitingForLocation)
    }

    // 8. Updates paused automatically by iOS.
    func testPausedUpdatesAskAgainAndResumeCleanly() {
        var (session, _) = openSession(origin: origin(home, t0))
        _ = session.routeLoaded(mode: .drive, requestID: session.requestID, count: 1, now: t0)
        let effects = session.updatesPaused(now: t0.addingTimeInterval(20))
        XCTAssertTrue(has(effects, .requestFreshLocation))
        XCTAssertEqual(effects.first?.reason, .resumeFromPause)
        XCTAssertEqual(session.selectedRouteState, .loaded(count: 1))

        _ = session.location(fix(home, t0.addingTimeInterval(21)), now: t0.addingTimeInterval(21))
        XCTAssertEqual(session.selectedRouteState, .loaded(count: 1), "the same start keeps its route")
        XCTAssertFalse(session.isRefreshingLocation)
    }

    // 9. The app returns from the background.
    func testReturningFromBackgroundKeepsThePlanAndRefreshesTheFix() {
        var (session, _) = openSession(origin: origin(home, t0))
        _ = session.routeLoaded(mode: .drive, requestID: session.requestID, count: 2, now: t0)
        let stable = session.origin
        let effects = session.returnedToForeground(now: t0.addingTimeInterval(120))
        XCTAssertTrue(has(effects, .requestFreshLocation))
        XCTAssertEqual(effects.first?.reason, .returnedToForeground)
        XCTAssertEqual(session.origin, stable)
        XCTAssertEqual(session.selectedRouteState, .loaded(count: 2))

        // A 20 m GPS wobble is not a new trip: no reload.
        let wobble = session.location(fix(LatLng(home.lat + 0.0002, home.lng), t0.addingTimeInterval(121)),
                                      now: t0.addingTimeInterval(121))
        XCTAssertTrue(wobble.isEmpty)
        XCTAssertEqual(session.selectedRouteState, .loaded(count: 2))
    }

    // 10. Locking and unlocking the phone.
    func testLockUnlockBehavesLikeAForegroundReturn() {
        var (session, _) = openSession(origin: origin(home, t0))
        _ = session.routeLoaded(mode: .drive, requestID: session.requestID, count: 1, now: t0)
        _ = session.returnedToForeground(now: t0.addingTimeInterval(30))
        let lock = session.updatesPaused(now: t0.addingTimeInterval(31))
        XCTAssertTrue(has(lock, .requestFreshLocation))
        let unlock = session.returnedToForeground(now: t0.addingTimeInterval(200))
        XCTAssertTrue(has(unlock, .requestFreshLocation))
        XCTAssertEqual(session.selectedRouteState, .loaded(count: 1))
        XCTAssertEqual(session.phase, .ready)
    }

    // 11. Location permission denied.
    func testDeniedPermissionIsItsOwnStateAndManualPlanningStillWorks() {
        var (denied, _) = openSession()
        _ = denied.permissionChanged(granted: false, denied: true, servicesOff: false,
                                     now: t0.addingTimeInterval(1))
        XCTAssertEqual(denied.phase, .failed(.permissionDenied))
        XCTAssertFalse(denied.isWaitingForLocation)
        XCTAssertTrue(denied.tick(now: t0.addingTimeInterval(120)).isEmpty,
                      "a denial is not an endless search")

        var (manual, _) = openSession()
        let effects = manual.setManualOrigin(PlanningOrigin(point: home, capturedAt: t0, kind: .manual),
                                             now: t0.addingTimeInterval(2))
        XCTAssertTrue(has(effects, .loadRoute), "manual start + manual destination never needs GPS")
        _ = manual.permissionChanged(granted: false, denied: true, servicesOff: false,
                                     now: t0.addingTimeInterval(3))
        XCTAssertEqual(manual.phase, .ready)
        XCTAssertFalse(manual.isWaitingForLocation)
        _ = manual.routeLoaded(mode: .drive, requestID: manual.requestID, count: 1,
                               now: t0.addingTimeInterval(4))
        XCTAssertEqual(manual.selectedRouteState, .loaded(count: 1))
    }

    // 12. An approximate location.
    func testApproximateLocationAllowsPreviewButNotNavigation() {
        var (session, _) = openSession()
        let effects = session.location(fix(home, t0, accuracy: 3_000), now: t0)
        XCTAssertTrue(has(effects, .loadRoute))
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.origin?.kind, .approximate)
        XCTAssertTrue(session.originUsability.canPlan)
        XCTAssertFalse(session.canStartNavigation)

        let navigation = session.prepareNavigation(fix: fix(home, t0, accuracy: 3_000), now: t0)
        XCTAssertFalse(navigation.canStart)
        XCTAssertEqual(navigation.failure, .impreciseFix)
        XCTAssertTrue(has(navigation.effects, .requestFreshLocation))
    }

    // 13. A manually typed start and destination.
    func testManualStartAndDestinationLoadsWithNoGPS() {
        var session = PlanningSession(destinationID: "shop", destinationName: "Shop",
                                      destination: shop, mode: .walk,
                                      manualOrigin: PlanningOrigin(point: home, capturedAt: t0, kind: .manual))
        let effects = session.start(now: t0)
        XCTAssertTrue(has(effects, .loadRoute))
        XCTAssertFalse(has(effects, .requestFreshLocation))
        XCTAssertFalse(session.isWaitingForLocation)
        XCTAssertEqual(session.phase, .ready)

        _ = session.location(fix(LatLng(51, -2), t0.addingTimeInterval(1)), now: t0.addingTimeInterval(1))
        XCTAssertEqual(session.origin?.point, home, "device fixes never replace a manual start")
    }

    // 14. The destination changes while waiting.
    func testDestinationChangeWhileWaitingInvalidatesTheOldAnswer() {
        var (session, _) = openSession()
        let oldGeneration = session.requestID
        let effects = session.changeDestination(id: "station", name: "Station",
                                                point: LatLng(50.2, -1.3),
                                                now: t0.addingTimeInterval(5))
        XCTAssertGreaterThan(session.requestID, oldGeneration)
        XCTAssertTrue(has(effects, .cancelRouteLoads))
        XCTAssertTrue(has(effects, .requestFreshLocation))

        let late = session.routeLoaded(mode: .drive, requestID: oldGeneration, count: 3,
                                       now: t0.addingTimeInterval(6))
        XCTAssertTrue(late.isEmpty)
        XCTAssertEqual(session.selectedRouteState, .idle)

        let current = session.location(fix(home, t0.addingTimeInterval(7)), now: t0.addingTimeInterval(7))
        XCTAssertTrue(has(current, .loadRoute))
        XCTAssertEqual(current.first?.requestID, session.requestID)
    }

    // 15. The planner is closed while waiting.
    func testClosingWhileWaitingCancelsEverythingAndIgnoresLateFixes() {
        var (session, _) = openSession()
        let oldGeneration = session.requestID
        let effects = session.close(now: t0.addingTimeInterval(4))
        XCTAssertTrue(has(effects, .cancelRouteLoads))
        XCTAssertFalse(session.isOpen)
        XCTAssertFalse(session.isWaitingForLocation)

        let lateFix = session.location(fix(home, t0.addingTimeInterval(30)), now: t0.addingTimeInterval(30))
        XCTAssertTrue(lateFix.isEmpty)
        let lateRoute = session.routeLoaded(mode: .drive, requestID: oldGeneration, count: 1,
                                            now: t0.addingTimeInterval(30))
        XCTAssertTrue(lateRoute.isEmpty)
        XCTAssertEqual(session.phase, .idle)
    }

    // 16. A stale routing-provider answer.
    func testStaleRoutingAnswerNeverLandsOnANewerPlan() {
        var (session, _) = openSession(origin: origin(home, t0))
        let first = session.requestID
        XCTAssertTrue(session.routeLoaded(mode: .drive, requestID: first - 1, count: 3, now: t0).isEmpty)

        _ = session.changeDestination(id: "station", name: "Station", point: LatLng(50.2, -1.3),
                                      now: t0.addingTimeInterval(10))
        let second = session.requestID
        XCTAssertNotEqual(first, second)

        let stale = session.routeLoaded(mode: .drive, requestID: first, count: 9,
                                        now: t0.addingTimeInterval(11))
        XCTAssertTrue(stale.isEmpty)
        XCTAssertEqual(session.modeStates[.drive], .loading)

        let current = session.routeLoaded(mode: .drive, requestID: second, count: 2,
                                          now: t0.addingTimeInterval(12))
        XCTAssertTrue(has(current, .frameRoute))
        XCTAssertEqual(session.selectedRouteState, .loaded(count: 2))
    }

    // 17. No internet is not the same as no route.
    func testOfflineAndNoRouteAreDistinctStates() {
        var (session, _) = openSession(origin: origin(home, t0))
        _ = session.routeFailed(mode: .drive, requestID: session.requestID, failure: .offline, now: t0)
        XCTAssertEqual(session.selectedFailure, .offline)

        _ = session.routeFailed(mode: .drive, requestID: session.requestID, failure: .noRoute, now: t0)
        XCTAssertEqual(session.selectedFailure, .noRoute)
        XCTAssertNotEqual(PlanningFailure.offline, PlanningFailure.noRoute)
        XCTAssertNotEqual(PlanningFailure.routerUnavailable, PlanningFailure.permissionDenied)
    }

    // 18. Starting active navigation after a preliminary plan.
    func testNavigationAfterPreliminaryPlanReroutesWhenThePhoneMoved() {
        var (session, _) = openSession(origin: origin(home, t0))
        _ = session.tick(now: t0.addingTimeInterval(120))
        XCTAssertTrue(session.originUsability.canPlan)
        _ = session.routeLoaded(mode: .drive, requestID: session.requestID, count: 1,
                                now: t0.addingTimeInterval(121))

        // Standing still but the preview fix is old: navigation asks for a fresh fix.
        let oldFix = session.prepareNavigation(fix: fix(home, t0.addingTimeInterval(1)),
                                                now: t0.addingTimeInterval(122))
        XCTAssertFalse(oldFix.canStart)
        XCTAssertEqual(oldFix.failure, .impreciseFix)

        // A fresh fix 300 m away must recalculate from where the phone is now.
        let movedPoint = LatLng(home.lat + 0.0027, home.lng)
        let moved = session.prepareNavigation(fix: fix(movedPoint, t0.addingTimeInterval(122)),
                                               now: t0.addingTimeInterval(122))
        XCTAssertFalse(moved.canStart)
        XCTAssertTrue(moved.rerouted)
        XCTAssertEqual(moved.origin?.point, movedPoint)
        XCTAssertEqual(moved.origin?.kind, .device)
        XCTAssertGreaterThan(moved.requestID, 1)
        XCTAssertTrue(has(moved.effects, .cancelRouteLoads))
        XCTAssertTrue(has(moved.effects, .loadRoute))

        _ = session.routeLoaded(mode: .drive, requestID: session.requestID, count: 1,
                                now: t0.addingTimeInterval(123))
        let ready = session.prepareNavigation(fix: fix(movedPoint, t0.addingTimeInterval(123)),
                                               now: t0.addingTimeInterval(123))
        XCTAssertTrue(ready.canStart)
        XCTAssertFalse(ready.rerouted)
    }

    func testSignificantMovementWhilePlanningRecalculatesButSmallDriftDoesNot() {
        var (session, _) = openSession(origin: origin(home, t0))
        _ = session.routeLoaded(mode: .drive, requestID: session.requestID, count: 1, now: t0)

        let near = LatLng(home.lat + 0.0005, home.lng)
        let small = session.location(fix(near, t0.addingTimeInterval(10)), now: t0.addingTimeInterval(10))
        XCTAssertTrue(small.isEmpty)
        XCTAssertEqual(session.origin?.point, home)

        let far = LatLng(home.lat + 0.0030, home.lng)
        let moved = session.location(fix(far, t0.addingTimeInterval(20)), now: t0.addingTimeInterval(20))
        XCTAssertTrue(has(moved, .cancelRouteLoads))
        XCTAssertTrue(has(moved, .loadRoute))
        XCTAssertEqual(session.origin?.point, far)
    }
}
